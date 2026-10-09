# morph: Liquid Glass — исследование производительности, рендеринга и визуальной достоверности

> **Статус:** рабочий исследовательский документ / knowledge base, версия 1.0  
> **Дата сверки источников:** 2026-10-08  
> **Базовая версия Flutter:** **3.47.2** (уточнять при обновлении)  
> **Основной тестовый путь:** Android, **Pixel 6a, Impeller Vulkan**  
> **Назначение:** хранить первоисточники, проверяемые гипотезы, ограничения Flutter и план экспериментов для UI kit `morph`. Документ предназначен для продолжения обсуждений с разработчиком или AI-агентом внутри репозитория.

**Важно о доказательствах.** Здесь специально разделены: **[ФАКТ]** — непосредственно проверяемое утверждение из указанного первоисточника; **[НАБЛЮДЕНИЕ]** — сведения об измерениях конкретного проекта, ещё не воспроизведённые независимо; **[ГИПОТЕЗА]** — инженерная идея для тестирования; **[ОГРАНИЧЕНИЕ]** — недостаток доступной информации/API. Наличие реализации в AOSP, Apple или Chromium **не доказывает**, что такая же техника ускорит Flutter на Pixel 6a. Ссылки на `main` могут меняться; важные Flutter-ссылки закреплены на теге 3.47.2.

---

## Содержание

1. [Цель, контекст, исходные показатели](#1-цель-контекст-исходные-показатели)
2. [Карта затрат и правила интерпретации](#2-карта-затрат-и-правила-интерпретации)
3. [Проверенные детали Impeller 3.47.2](#3-проверенные-детали-impeller-3472)
4. [Внешние реализации: Apple, Android, Windows, Chromium и игры](#4-внешние-реализации-apple-android-windows-chromium-и-игры)
5. [Алгоритмы размытия](#5-алгоритмы-размытия)
6. [Backdrop sharing, пространственные группы и damage tracking](#6-backdrop-sharing-пространственные-группы-и-damage-tracking)
7. [Мобильные GPU: bandwidth, tile memory, синхронизация](#7-мобильные-gpu-bandwidth-tile-memory-синхронизация)
8. [Оптическая модель и перцептивные оптимизации](#8-оптическая-модель-и-перцептивные-оптимизации)
9. [Фактические возможности Flutter GPU и границы API](#9-фактические-возможности-flutter-gpu-и-границы-api)
10. [Реестр гипотез H01–H20](#10-реестр-гипотез-h01h20)
11. [Полная программа бенчмарков](#11-полная-программа-бенчмарков)
12. [Схемы альтернативной архитектуры](#12-схемы-альтернативной-архитектуры)
13. [Decision tree, приоритизация и критерии успеха](#13-decision-tree-приоритизация-и-критерии-успеха)
14. [Ошибки, артефакты и контроль качества](#14-ошибки-артефакты-и-контроль-качества)
15. [Реестр первоисточников и репозиториев](#15-реестр-первоисточников-и-репозиториев)
16. [Незакрытые вопросы и шаблон следующего исследования](#16-незакрытые-вопросы-и-шаблон-следующего-исследования)

---

## 1. Цель, контекст, исходные показатели

### 1.1. Цель

Приблизиться к характерному визуальному поведению Apple Liquid Glass, но обеспечить приемлемые **GPU time, CPU time, использование памяти, энергопотребление и плавность** на слабых Android-устройствах. Решение должно быть пригодно для **распространяемого Flutter-пакета**, а не только для одного конкретного экрана.

### 1.2. Известная архитектура `morph` (по контексту проекта)

- Flutter GPU рисует **matte-текстуру** геометрии стекла.
- Применяется `BackdropFilterLayer` с последовательностью `ImageFilter.blur` и `ImageFilter.shader`.
- Финальный shader реализует **преломление, окраску и блики**.
- Уже существуют **кэширование геометрии**, `BackdropGroup`/`BackdropKey`, некоторые механизмы группировки захватов.
- В исследованных сценах остаются примерно **3–5 независимых захватов фона**.
- На **Pixel 6a / Impeller Vulkan** в исследованных активных кадрах наблюдались примерно **5–10 мс GPU**; «полное стекло» требовало **приблизительно в 4–6 раз больше GPU cycles**, чем flat. Эти цифры **проектные**, не измерения из внешних источников.
- **Не установлено**, какую долю дают capture, downsample, Gaussian, shader, композиция, texture allocation, driver overhead и GPU scheduling.

### 1.3. Чего нельзя предполагать

1. Что Gaussian в Impeller всегда выполняется в полном разрешении — **неверно**, движок уже downsample-ит для больших `sigma` [S01].
2. Что `BackdropGroup` обязательно объединяет **все** фильтры/шейдеры или корректно работает при перекрытии — **неверно как общее утверждение** [S02].
3. Что малое число texture fetches гарантирует малое GPU time — зависит от bandwidth, cache, render pass barriers, blending и драйвера.
4. Что метрика GPU cycles эквивалентна миллисекундам, энергии или памяти.
5. Что технология нативного Liquid Glass Apple полностью доступна из публичных API или из Swift-метаданных.
6. Что наличие `gpu.Texture.fromImage()` делает снимок **живого** UI бесплатным или синхронным [S05].

### 1.4. Ключевой принцип

**Оптимизировать нужно end-to-end render graph, а не только fragment shader.** Хорошая архитектура может обойтись более дорогим локальным шейдером, но меньшим числом захватов и материализаций текстур; простейший shader может проиграть из-за full-screen read/write.

---

## 2. Карта затрат и правила интерпретации

Условная схема текущего пути:

```text
Flutter scene
  ├─ lower content ──> [Backdrop sampling / snapshot] ──> [downsample]
  │                                                        │
  │                                             [vertical Gaussian]
  │                                                        │
  │                                             [horizontal Gaussian]
  │                                                        │
  └─ [geometry] ──> [matte texture] ─────────────────────────┤
                                                           v
                                      [refraction + tint + highlights]
                                                           v
                                            [blend / composition]
```

Этот рисунок **логический**: реальные render passes и порядок могут отличаться, а некоторые стадии могут переиспользовать общий input.

### 2.1. Составляющие затрат

| Ступень | Возможные ресурсы | Типовые симптомы | Чем измерять |
|---|---|---|---|
| Rasterization нижней сцены | CPU/raster, GPU | скачки raster time даже без стекла | Flutter DevTools, Perfetto |
| Backdrop capture | render target, копирование/сохранение tile contents | цена растёт с площадью и количеством групп | RenderDoc, attachment inspection |
| Downsample/upsample | texture bandwidth, промежуточные поверхности | цена зависит от pixels/pass | RenderDoc, counters |
| Blur | texture reads, cache, bandwidth | цена зависит от sigma и площади | pass-level GPU timing |
| Matte/SDF | GPU pass и отдельная текстура | дорого при morph/resize | isolate geometry benchmark |
| Refraction shader | ALU, dependent texture reads | зависит от overdraw и формы | shader isolation, frame capture |
| Финальная композиция | blending, fill rate | цена растёт с перекрытием и размером | overdraw / GPU counters |
| Allocator / resource lifetimes | CPU, память, синхронизация | spikes, рост transient memory | Perfetto, GPU tools |
| Display presentation | очередь кадров, pacing | высокий p99, input latency | Perfetto, FrameTiming |
| Тепловой режим | clocks, energy | снижение FPS через минуты | sustained runs, clocks |

### 2.2. Закон Амдала

Если доля текущего времени, занимаемая оптимизируемым участком, равна `p`, а его ускорение равно `s`, то полное ускорение:

\[
S = \frac{1}{(1-p)+p/s}
\]

Пример: если shader занимает **20%** GPU-времени и даже полностью исчезнет, максимальное ускорение **1.25×**. Поэтому нужна декомпозиция.

### 2.3. Как считать стоимость материала

```text
incremental_gpu_ms = gpu_ms(scene + glass) - gpu_ms(scene + flat)
```

Это **диагностическая оценка**, а не точная аддитивная стоимость: возможны overlap и различия scheduling. Нужно повторять в одинаковых условиях, чередовать A/B, строить распределения и проверять стабильность частот.

### 2.4. CPU/GPU, cycles/time, throughput/latency

- **GPU cycles** и **GPU ms** — разные метрики: частота GPU и энергополитика могут меняться.
- **Текстурные выборки** ≠ **DRAM bytes**: часть попадёт в cache, часть — в tile/texture compression.
- **Render passes** ≠ **command buffers** ≠ **GPU waits**. Три command buffers сами по себе не доказывают три полные GPU-остановки.
- **Средние кадры** скрывают spikes: смотреть p50/p90/p95/p99, missed frames, frame pacing.
- **Низкая энергия** может потребовать меньшей средней загрузки GPU, а не просто прохождения 60 FPS.

---

## 3. Проверенные детали Impeller 3.47.2

**Главный источник:** [`gaussian_blur_filter_contents.cc` на теге `3.47.2`][S01]. Этот файл — одна из наиболее полезных точек входа в текущую реализацию.

### 3.1. Downsample уже есть — конкретное правило

**[ФАКТ]** `GaussianBlurFilterContents::CalculateScale(sigma)`:

- для `sigma <= 4` возвращает `1`;
- для большего `sigma` берёт исходно `4/sigma`;
- округляет к степени двойки через `round(log2(...))`;
- ограничивает downsample до **1/16** по линейному масштабу;
- для самых сильных blur имеет дополнительную поправку на kernel size и мерцание.

См. [S01, `CalculateScale`](https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/impeller/entity/contents/filters/gaussian_blur_filter_contents.cc) — ищи символ `CalculateScale` в закреплённой версии исходника.

Примерное соответствие до дополнительных поправок:

| sigma | linear scale | доля пикселей |
|---:|---:|---:|
| 4 | 1 | 100% |
| 8 | 1/2 | 25% |
| 16 | 1/4 | 6.25% |
| 32 | 1/8 | 1.5625% |

**[ГИПОТЕЗА]** Dual Kawase/mip-based путь сможет сэкономить затраты на повторных фильтрах. **Контргипотеза:** адаптивный Gaussian Impeller настолько эффективен, что новые passes и подготовка пирамиды делают альтернативу медленнее.

### 3.2. Реальный Gaussian pipeline

**[ФАКТ]** в ненулевом пути создаются три command buffers:

1. downsample;
2. вертикальное размытие;
3. горизонтальное размытие.

Комментарий в engine связывает разделение с прежними `deviceLost` на старых Adreno при объединении и с issue [S03]. **Не пытаться удалять барьер/сливать буферы до проверки на широком парке GPU**.

**[ФАКТ]** движок использует одномерные проходы и комбинирование kernel taps с аппаратной линейной интерполяцией (`LerpHackKernelSamples`, `kLinear`). Таким образом, грубая стратегия «сделаем separable blur вместо квадратного» давно реализована.

### 3.3. Mip reuse и bounded blur

**[ФАКТ]** `MakeDownsampleSubpass` проверяет доступность уже сгенерированных mip-уровней и может их использовать. Однако **bounded blur** запрещает такой путь, потому что за пределами bounds содержимое должно интерпретироваться как прозрачное [S01].

Следствие: при анализе группировки обязательно разделять **bounded/unbounded** и одинаковые/разные фильтры. Сравнение «группировка не помогает» без этого некорректно. См. также реальный performance report [S04] — он относится к **Windows**, а не является доказательством поведения Pixel 6a.

### 3.4. Halo, gutter, bounds, shimmer

**[ФАКТ]** в engine есть подготовка прозрачного gutter для blur halo и обработка `coverage_hint`/выравнивания координат. Комментарий рядом с `CalculateDownsamplePassArgs` сообщает, что агрессивное исключение padding вызывало **shimmer** ([S06]) и не было включено.

Другой TODO возле `MakeBlurSubpass` отмечает, что в некоторых случаях blur охватывает **всю** входную текстуру, хотя clip мог бы позволить сузить вычисляемую область.

Важные вопросы для RenderDoc:

- Совпадает ли область фактического input snapshot с визуальным bounds стекла?
- Сколько halo пикселей добавляется при разных sigma и refractive displacement?
- Какое отношение `allocatedPixels / visiblePixels` для каждой поверхности?
- Меняется ли размер intermediate при движении на дробные координаты?
- Насколько cache-friendly кадры с одинаковыми sigma, но разными позициями?

### 3.5. BackdropGroup и корректность

**[ФАКТ]** Flutter API говорит, что несколько backdrop filters могут быть объединены, когда используют общий `BackdropKey`, однако **перекрывающиеся** элементы **не должны** использовать один и тот же key, если требуется эквивалентный результат независимых фильтров [S02].

Не смешивать:

- общий **входной backdrop**;
- общий **blur result**;
- общий **material shader**;
- общую **геометрию/merged glass**;
- общую **композицию**.

Это разные ресурсы/стадии, объединяемые при разных условиях.

### 3.6. ImageFilter DAG остаётся ограничением

**[ФАКТ]** feature request [S07] предлагает граф вида `f(x, g(x))`, который использует одновременно **оригинальный** и **обработанный** backdrop. Нынешняя последовательная композиция `f(g(x))` не выражает такой граф без дополнительных ресурсов/API. В issue прямо упоминаются SDF, normals и refraction для Liquid Glass.

**[ГИПОТЕЗА]** многовходовый граф фильтров может быть большим engine-level выигрышем для `morph`, чем ещё одна микрооптимизация Gaussian.

---

## 4. Внешние реализации: Apple, Android, Windows, Chromium и игры

### 4.1. Apple — группировка и качество материала

**[ФАКТ]** WWDC25 AppKit [S10] описывает `NSGlassEffectContainerView`:

- связанные элементы могут объединяться/разделяться (morph);
- разделяют адаптивный appearance;
- стекло выбирает окружение из **более широкой области**, чем контур стекла;
- стекло **не должно напрямую сэмплировать другое стекло** той же группы;
- единая группа использует **один sampling pass** вместо отдельных sampling passes для каждого элемента.

Это **описание внешнего поведения и архитектурного принципа**, а не публикация Metal pass graph Apple. Из сказанного нельзя вывести точный алгоритм blur, формат intermediate, число fetches или команд.

**[ФАКТ]** WWDC25 Meet Liquid Glass [S11] подчёркивает lensing, refraction, adaptivity, изменение характера материала при изменении размера. Поэтому «нативный вид» — это не только степень размытия.

**[ГИПОТЕЗА]** визуально убедительный пакет может использовать разные уровни качества в зависимости от **размера, скорости движения, контраста фона, режима UI и класса GPU**.

### 4.2. Android SurfaceFlinger — Kawase вместо полного Gaussian

**[ФАКТ]** AOSP в `SurfaceFlinger.cpp` [S12] прямо указывает, что Kawase предлагается по умолчанию как более быстрый алгоритм с близкой картинкой. В системе присутствуют обычный Kawase и Dual Kawase.

- [S13] `KawaseBlurFilter.cpp`: five-tap kernel — центр + четыре диагональные выборки, несколько проходов, spatial downsample.
- [S14] `KawaseBlurDualFilter.cpp`: пирамида уменьшенных изображений, проходы вниз/вверх, crossfade, другое ядро (в указанной ревизии центр + семь точек по окружности), то есть **не просто 5-tap Kawase**.

**Важно:** выбранный SurfaceFlinger blur не означает, что Flutter сможет напрямую вызвать его для произвольных виджетов или что системный код использует точно такую же оптическую модель, как Apple Liquid Glass.

### 4.3. Microsoft Mica — не вычислять живой фон всегда

**[ФАКТ]** Mica [S15] — **не эквивалент live glass**: это непрозрачный материал на основе desktop wallpaper, который ради производительности сэмплируется однократно. Предусмотрены solid fallback для energy saver, low-end hardware и некоторых состояний интерфейса.

**Урок:** fallback не обязательно должен быть «плохим стеклом». Может быть другим, намеренно созданным материалом, который сохраняет иерархию интерфейса и читаемость.

### 4.4. Chromium Viz — damage tracking

**[ФАКТ]** [S16] исходники `SurfaceAggregator` отслеживают damage rects, render passes, cached surfaces и pixel-moving backdrop filters. При пересечении повреждения с фильтром damage расширяется на область, которую эффект может затронуть. В некоторых случаях возможна инвалидация всего pass — не каждый backdrop способен дешёво кешироваться частично.

**Урок:** invalidation — это отдельная задача. Нельзя обновлять кэш только когда изменился bounding box **самого стекла**: фон мог измениться *под* ним или в halo вокруг него.

### 4.5. Godot — уменьшенные цепочки и компромисс passes/bandwidth

**[ФАКТ]** Godot `renderer_scene_render_rd.cpp` [S17] явно описывает mobile glow как downsample/upsample mip-chain: приблизительно `2*level - 1` passes, снижение texture read bandwidth при необходимости уменьшать passes.

В Godot docs [S18] отдельно объяснено, почему tile-local subpasses удобны для локальных операций, а glow/depth-of-field плохо укладываются в такие ограничения: они читают соседние пиксели.

**Урок:** не оптимизировать число shader samples в отрыве от resolution и pass count.

### 4.6. Unity/URP и индустриальный постпроцессинг

Glow/bloom, depth-of-field и soft background делят с Liquid Glass ключевые проблемы: размывание, многоуровневые textures, temporary buffers, cross-pass traffic. В игровых движках часто используются пониженное разрешение, цепочки down/up и разные уровни качества. Но **bloom отличается от backdrop blur**: обычно обрабатываются яркие области, у стекла же нужен цветной фон и точный refractive displacement. Проверять эквивалентность нельзя без тестов.

---

## 5. Алгоритмы размытия

### 5.1. Separable Gaussian — референс, а не наивный full-res

Непосредственная 2D convolution имеет порядок `O(W*H*K^2)`. Separable Gaussian — `O(W*H*K)` при двух проходах. GPU-реализация с downsample, bilinear taps и хорошим reuse **обычно значительно дешевле**, чем наивный shader.

**Что сравнивать**: Impeller **фактический** Gaussian как baseline; не абстрактный full-resolution 2D kernel.

### 5.2. Kawase

Вариант AOSP: центр + четыре диагональные выборки на шаге `offset`, повторённые для приближения Gaussian. Плюсы — простой kernel и управление числом проходов; минусы — иная PSF (point spread function), отклонения на резких границах и потенциальное накопление ошибок.

**Тест**: подобрать параметры по **визуальной ошибке**, а не просто `blurRadius = sigma`.

### 5.3. Dual Kawase

Последовательно downsample + фильтрация, затем upsample + фильтрация/смешивание. Плюсы: много работы на малых размерах; минусы: промежуточные поверхности, несколько переходов между passes, реконструкция тонких деталей. Конкретное ядро зависит от реализации — не считать все Dual Kawase одинаковыми.

**Тест**: варианты с 2, 3, 4 уровнями и разными scale, отдельно фиксировать память и transient render targets.

### 5.4. Обычная mip-пирамида + LOD

Очень дешёвый fragment fetch после построения пирамиды. Можно выбирать непрерывный `lod` (при поддержке sampler API) и масштабировать **эффективную** степень размытия. Но mip-фильтр не является произвольным Gaussian; профиль, цветовые границы и temporal shimmer могут не совпадать.

**Тесты**: `textureLod`/trilinear, nearest mip vs smooth LOD, точность на тексте и high-frequency patterns.

**Скрытая цена:** создание всех mip-levels и преобразование live backdrop в текстуру не бесплатны. Экономия возможна прежде всего при **повторном использовании** пирамиды для нескольких элементов/вариантов материала.

### 5.5. Hybrid: mip + small Gaussian/Kawase

**[ГИПОТЕЗА]** снять крупномасштабное размытие из mip-chain, а остаток выполнить маленьким корректирующим ядром. Хорошо, если нужно избежать сильных искажений на границах и приблизиться к целевой PSF.

Нужно проверить дополнительные passes vs blur fidelity: один extra pass может съесть весь выигрыш.

### 5.6. Другие классы: box, tent, SAT, IIR, FFT

- **Box / tent:** дешёвый kernel, хорошая база для приближений; возможны directional artifacts.
- **Summed area table / integral image:** дешёвые box-average queries после дорогостоящей подготовки; не очевидно выгодно для динамического UI.
- **IIR / recursive Gaussian:** слабая зависимость от больших radius, но последовательные зависимости и boundaries осложняют GPU-путь.
- **FFT convolution:** полезна при больших изображениях/ядрах и иных нагрузках, но обычно слишком много setup/temporary resources для небольшого real-time стекла.

Не исключать полностью, но низкий приоритет до frame decomposition.

### 5.7. Сложные граничные условия

Чтобы сравнение было честным, закрепить:

- одинаковый source rectangle **включая halo**;
- edge handling: clamp / transparent / decal / tile;
- alpha: straight vs premultiplied, необходимость unpremultiply;
- colour space: linear RGB vs gamma-encoded sRGB;
- input/output pixel format (RGBA8, RGBA16F и др.);
- jitter и texel alignment при дробных координатах;
- одинаковый target visual sigma/PSF, а не одинаковая номинальная настройка.

**Важно:** сверка одного статичного screenshot недостаточна. Во время scroll/animation может появиться shimmer или ghosting.

---

## 6. Backdrop sharing, пространственные группы и damage tracking

### 6.1. Разделять пять уровней reuse

| Уровень | Предмет sharing | Совместимость |
|---|---|---|
| 1 | source capture | соседние элементы с подходящими зависимостями |
| 2 | prefiltered texture / mip pyramid | общая область, совместимая частота обновления |
| 3 | конкретный blur | одинаковая PSF, bounds, sampling semantics |
| 4 | matte/normals | одинаковая или стабильная геометрия |
| 5 | material merging | специальная композиция перекрывающихся стёкол |

Один `BackdropKey` **не означает**, что автоматически доступны уровни 2–5.

### 6.2. Область зависимости стекла

Грубая консервативная модель:

```text
inputBounds = expand(
  visualBounds,
  blurSupportRadius + maxRefractionDisplacement + filterFootprint + safetyMargin
)
```

Здесь `blurSupportRadius` — практически используемый радиус поддержки фильтра, **не обязательно sigma**; Gaussian теоретически имеет бесконечные хвосты, в реализации ядро усечено.

При группировке анализировать **union входных прямоугольников**, а не только видимых форм.

### 6.3. Почему одна огромная группа может проиграть

Если две стеклянные кнопки расположены по разным концам экрана, единый bounding rectangle может включать пустую область огромного размера. Единый capture уменьшает число операций, но увеличивает processed pixels, intermediate allocation и частоту invalidation. Apple рекомендует группировать близкие элементы [S10]; оценку реального выигрыша должен дать профиль кадра.

### 6.4. Простейшая модель стоимости группы

\[
C(G) \approx \alpha N_{passes} + \beta \sum_i A_{renderTarget,i} +
\gamma B_{memory} + \delta I_{updates} + \varepsilon T_{sync}
\]

Коэффициенты нельзя переносить между устройствами без измерения. Практический алгоритм:

1. получить `inputBounds` каждого элемента;
2. соединить близкие/пересекающиеся прямоугольники;
3. сравнивать раздельные vs объединённые группы по *измеренной* модели;
4. учитывать совместимость blur mode, sigma, backdrop depth, blending;
5. учитывать вероятную **частоту изменения** содержимого;
6. вводить **гистерезис** против скачкообразной перегруппировки на анимациях;
7. для перекрывающихся линз — отдельная ветвь material merging.

### 6.5. Damage/invalidation

Кэш должен инвалидироваться, когда изменяется **любой источник, влияющий на выборки**. Это может быть:

- движение/анимация контента под стеклом;
- изменение backdrop внутри halo;
- изменение самого стекла, анимация параметров, sigma, нормалей;
- изменение clip/transform/devicePixelRatio/viewport;
- изменение цветового пространства/HDR/surface resize;
- стекло поверх стекла или изменение z-order.

Общий Flutter-пакет не получает универсальную идеальную карту всех dirty regions UI. Реалистичные варианты:

- **live** — каждый кадр корректен;
- **static** — явно неизменный фон;
- **onDemand** — внешний владелец сцены сигналит об изменении;
- **region-aware** — интеграция с контролируемой сценой, источники предоставляют dirty rects;
- **adaptive** — эвристика с оговоркой о возможной задержке и артефактах.

### 6.6. Стекло поверх стекла

Две семантики:

**A. Serial glass:** `glass(B(glass(A(scene))))` — приёмник читает уже обработанный результат. Дороже и оптически может выглядеть как двойная мутная линза.

**B. Shared scene glass:** обе линзы читают один исходный source и участвуют в едином материальном объединении. Может быть быстрее/чище, но требует специфической композиции и правил overlap.

**[ФАКТ]** Apple описывает группировку как способ избегать sampling glass by glass [S10]. **[ОГРАНИЧЕНИЕ]** прямое копирование этой идеи через совпадающий BackdropKey для перекрывающихся Flutter-фильтров не гарантирует правильность [S02].

---

## 7. Мобильные GPU: bandwidth, tile memory, синхронизация

### 7.1. Числовой масштаб

Для `1080 × 2400` и `RGBA8`:

- один уровень: `1080 × 2400 × 4 = 10,368,000` байт, то есть **10.37 MB** (или **9.89 MiB**);
- полная mip-chain в грубом приближении `4/3` от уровня 0: **~13.82 MB**;
- одна полная **чтение + запись** того же объёма: **~20.74 MB логических bytes**;
- при 60 FPS: **~1.24 GB/s логического traffic** до учёта fetch amplification, cache, compression и прочих passes.

Это **не фактические DRAM bytes**. На реальном tile-based GPU compression, кеши и layout меняют картину.

### 7.2. Цена разрешения

| Линейный масштаб | Пикселей относительно полного |
|---:|---:|
| 1 | 100% |
| 1/2 | 25% |
| 1/4 | 6.25% |
| 1/8 | 1.5625% |
| 1/16 | 0.390625% |

Для маленькой UI-линзы экономия от downsample может быть скромнее, если **halo/gutter** доминируют над самим полезным прямоугольником.

### 7.3. Tile-based deferred rendering

**[ФАКТ]** Vulkan TBR guidance [S19] описывает выигрыш от сохранения данных в tile-local/on-chip storage и от корректных load/store/subpass решений.

**[ОГРАНИЧЕНИЕ]** Input attachments и tile-local framebuffer fetch обычно не дают *произвольной выборки соседних пикселей*. Blur/refraction требуют `sample(offsetUV)` по более широкой области. Поэтому нельзя автоматически слить нелокальное blur в один tile-local pass без промежуточного изображения.

### 7.4. Принципы работы с памятью

- выбирать минимальные корректные attachment sizes;
- сравнивать RGBA8 / RGBA16F и влияние HDR/gamut/точности;
- избегать избыточного load предыдущего содержимого при полном overwrite;
- `transient` и pooling использовать только при корректной **GPU lifetime**;
- явно понимать барьеры между texture writes и subsequent reads;
- не делать дополнительных `blit/copy`, если уже доступен GPU-resident input;
- не перераспределять textures при каждом изменении размеров на ±1 px, если выгоднее округление и reuse;
- не пытаться без профиля переносить всё в compute: compute shader может проиграть raster pipeline на мобильном чипе.

### 7.5. Pool, frames in flight, синхронизация

`submit()` на CPU не обязательно значит, что GPU завершил чтения. Если один и тот же texture slot перезаписать слишком рано, возможны data hazards. Реализовывать буферизацию/пул с учётом fences/frame completion и гарантий Flutter GPU API. Issue по детерминированному освобождению `Texture`/`DeviceBuffer` — [S20].

### 7.6. Контроль p95/p99 и thermal throttling

Мгновенная победа 0.5 мс может не сохраниться через 5–10 минут. Проверять **sustained load**, частоты GPU, энергию (где измеримо), температуру и pacing. Скорость — это не единственная метрика UX.

---

## 8. Оптическая модель и перцептивные оптимизации

### 8.1. Разложение материала

Условно:

```text
appearance = optics(background, normals, thickness)
           + adaptive tint / exposure / saturation
           + edge highlights / reflections
           + shadow / depth
           + antialiasing / compositing
```

По Apple [S11], ощущение стекла во многом формируется **lensing**, динамикой и адаптацией. Поэтому точное Gaussian blur не всегда важнейшая характеристика.

### 8.2. Центр и край: разные требования

**[ГИПОТЕЗА]** высокая точность refraction нужна прежде всего вблизи края и на контрастных деталях фона, тогда как центр может использовать дешёвый prefiltered sample. Проверить три реализации:

1. единый shader со всеми вычислениями;
2. shader с runtime branches по distance-to-edge;
3. несколько **pipeline variants** с фиксированным набором возможностей.

Runtime branch не всегда выигрывает из-за divergence, а несколько вариантов увеличивают сложность и стоимость подготовки pipelines.

### 8.3. Matte vs SDF vs normals

| Геометрический ресурс | Плюсы | Минусы |
|---|---|---|
| `R8` alpha matte | минимум памяти | нормали и thickness вычислять отдельно |
| `R8`/`R16` SDF | геометрия и distance-to-edge | точность, масштаб, границы |
| `RG8` packed normal | мало ALU в финальном shader | квантование, дополнительные texture fetches |
| `RG16F` normal | выше точность | больше bandwidth/память |
| packed normal+thickness | меньше финальных вычислений | формат/обновление/совместимость |

**Эксперимент**: сравнивать арифметический путь с чтением отдельной texture. Не предполагать, что precomputed normal дешевле: на многих GPU несколько ALU-инструкций лучше одной зависимой выборки.

### 8.4. Упрощение освещения и хроматической аберрации

- выключить aberration, сравнить visual error;
- ограничить edge highlight вдоль контура;
- разделить small/large lenses;
- использовать LUT для дорогих nonlinear curves при доказанном ALU bottleneck;
- профильные shader variants вместо гигантского наборного shader;
- не пытаться автоматически удалить все `pow`, `sqrt`, `normalize`: компилятор уже делает оптимизации, а lookup может стоить дороже.

### 8.5. Adaptivity через предварительно фильтрованный фон

**[ГИПОТЕЗА]** средние mip-уровни уже содержат низкочастотный сигнал для оценки яркости/цвета; его можно использовать для tint и уменьшения дополнительных reduction passes. Важно отличать среднюю яркость **всей группы** и **локальный** цвет непосредственно под линзой.

### 8.6. Reverse engineering QuartzCore

Репозиторий [S23] заявляет о восстановлении части алгоритмов Apple QuartzCore, включая mip LOD, адаптивный tint и lens/refraction. Это **самоописание стороннего проекта**, не подтверждение от Apple и не гарантия идентичности реализации. Сравнивать по исходникам и эталонным кадрам. Swift metadata analyzer [S28] извлекает интерфейсы типов, а не полные GPU-алгоритмы; [S29] анализирует Metal libraries/bitcode, но не гарантирует восстановление оригинального исходника.

### 8.7. Нативный эталон

Создать маленькое native iOS/macOS приложение с фиксированной текстурой фона и несколькими `UIGlassEffect`/`NSGlassEffectView`. Снимать парные состояния при одинаковом масштабе и цветовой конфигурации. Тестировать:

- текст/тонкие линии;
- checkerboard/grids;
- высококонтрастные границы;
- яркие участки + тёмные участки;
- движение стекла поверх неподвижного фона;
- scroll под неподвижным стеклом;
- размеры и геометрию линзы;
- близкие и пересекающиеся стёкла;
- адаптацию к динамическому фону.

Метрики: SSIM, LPIPS (для perceptual similarity), ROI по краям, temporal stability. Любая численная метрика — только дополнение к visual review.

---

## 9. Фактические возможности Flutter GPU и границы API

### 9.1. `gpu.Texture.fromImage()`

**[ФАКТ]** PR [S05] влит 2026-06-29 и присутствует в release notes Flutter 3.47 [S08]. Оборачивает GPU-resident texture из `ui.Image` без CPU roundtrip.

**Но:**

- Поддерживается путь через асинхронный `RepaintBoundary.toImage` / `Picture.toImage`; `toImageSync` может ещё не иметь готовой texture.
- Обёрнутый ресурс предназначен прежде всего для **sampling**, использование как render attachment **не гарантируется**.
- Готовность `ui.Image` требует rasterization; это не бесплатный capture текущего framebuffer.
- Захват поддерева не эквивалентен произвольной backdrop-семантике, особенно с overlay, platform views, z-order и стеклом над стеклом.
- Проверить реальную задержку и возможность избежать лишних frame barriers на Pixel 6a.

### 9.2. Multi-mip GPU textures

**[ФАКТ]** в release notes 3.47 [S08] перечислены PR по multi-mip allocations, запись в конкретный `(mip,slice)`, возможность рендерить в отдельный mip-level, explicit mip sampling и blits. Поддержка зависит от backend/драйвера/формата; GLES имеет дополнительные ограничения.

**Практический путь для изолированного прототипа:** `controlled ui.Image or asset` → `gpu.Texture` → собственный pass graph → `Texture.asImage()` → сравнение с baseline. Затем переходить к живому capture.

### 9.3. ImageFilter.shader и sampler ограничения

Issue [S09] описывает случаи неудовлетворительного filtering implicit backdrop sampler и необходимость ручной билинейной выборки в shader. **Не утверждать**, что баг воспроизводится на всех устройствах и конкретно в твоём 3.47.2 до теста.

Вопрос для capture: sampler mode? Один ли fetch в refraction или четыре ручных? Как ведут себя дробные UV?

### 9.4. Render-to-texture orientation на GLES

[ФАКТ] Flutter 3.47 изменил поведение ориентации render-to-texture для GLES; см. migration notes [S21]. Для нового backend необходимо тестировать Vulkan/Metal/GLES, особенно UV-transform и blur halo.

### 9.5. Когда нужен форк Impeller

Рассматривать только если профили подтвердят, что основной проигрыш вызван **ограничениями render graph/compositor API**:

- отсутствие многовходовых фильтров `f(x,g(x))`;
- невозможность переиспользовать prefilter без повторного capture;
- лишний full-screen target;
- дорогостоящий offscreen/resolve, который на уровне пакета не устранить;
- недоступность sampler/format/visibility управления.

Форк повышает долгосрочную стоимость поддержки движка и совместимости. Предпочитать узкий engine PR/issue с воспроизводимым benchmark.

---

## 10. Реестр гипотез H01–H20

Каждая гипотеза требует заранее определённого теста, ожидаемого выигрыша **и способа опровержения**. Не считать рейтинг фактом.

| ID | Гипотеза | Как опровергнуть / подтвердить | Зависимость |
|---|---|---|---|
| H01 | Capture dominates | capture-only близок к full glass по GPU ms | pass decomposition |
| H02 | Blur dominates | blur-only повторяет большую долю полной цены | pass decomposition |
| H03 | Refraction shader dominates | `identity shader` сильно дешевле full shader при том же blur | identity baseline |
| H04 | Large halo/allocated bounds dominates | стоимость сильно коррелирует с allocated area, не visible area | attachment capture |
| H05 | Dual Kawase beats Impeller Gaussian for large sigma | Pareto-frontier GPU ms/visual error лучше baseline | isolated blur tests |
| H06 | mip LOD + correction beats Gaussian | учитывая **полную** стоимость generation + sampling | controlled texture |
| H07 | Shared prefilter amortizes across N lenses | выигрыш растёт с N; на N=1 может быть проигрыш | N sweep |
| H08 | Grouping by locality beats one large group | spatial separation vs processing area | grouped scenes |
| H09 | Grouping by update frequency improves FPS/power | локальная анимация не инвалидирует весь background | dirty region demo |
| H10 | Cache static geometry saves GPU time | animated background/static shape vs morphing geometry | geometry-only test |
| H11 | Packed normals save ALU | trade-off texture reads vs ALU positive на Pixel 6a | shader variants |
| H12 | Shader specialization beats branching | разница в GPU ms после shader warm-up | compile variants |
| H13 | Edge-only expensive optics visually acceptable | blind pair visual tests + ROI error | reference images |
| H14 | Less refraction on small controls acceptable | perceptual ranking в маленьких UI | multiple sizes |
| H15 | Adaptive tint via pyramid saves pass | mean color matches local reference sufficiently | tint benchmarks |
| H16 | Temporal caching safe for low-motion background | absence of ghosting/lag при scroll и translations | temporal tests |
| H17 | Different tileMode/bounded mode changes reuse | same sigma, bounded/unbounded performance profile | grouped tests |
| H18 | Implicit sampler quality increases fetches | manual 4-tap vs hardware linear profile | shader inspection |
| H19 | Direct Flutter GPU backend faster end-to-end | include snapshot, mip generation, presentation, synchronization | full pipeline |
| H20 | Multi-device quality policy beats fixed default | reproducible quality/perf envelopes on target classes | device matrix |

**Главное правило:** если `H01` подтверждается и `H02` нет, оптимизация Gaussian может быть почти бесполезна. Если `H19` не проходит end-to-end, оставить нынешний API даже при более быстром автономном blur.

---

## 11. Полная программа бенчмарков

### 11.1. Ступень A: установить baseline

Собрать отдельное приложение `morph_bench` с воспроизводимыми конфигурациями. Сохранить точные версии Flutter engine/Dart, build mode (`profile` / `release`), device/OS/GPU, resolution, physical DPR, refresh rate, battery/thermal state, debug flags.

**Сравнение стадий:**

| Variant | Capture | Blur | Material | Matte | Зачем |
|---|---|---|---|---|---|
| A0 flat | нет | нет | нет | нет | floor |
| A1 capture + identity | да | нет | identity | нет | isolate capture/composition |
| A2 capture + blur | да | да | identity | нет | blur delta |
| A3 capture + refraction | да | нет | да | да | material delta |
| A4 matte only | нет | нет | нет | да | geometry delta |
| A5 full | да | да | да | да | actual cost |
| A6 full + grouped | да/grouped | да | да | да | grouping delta |

**Важно:** `A5-A2` не всегда чистая цена shader из-за pipeline interactions. Для серьёзных выводов дополнить pass-level GPU timestamps и RenderDoc inspection.

### 11.2. Ступень B: матрица сцен

| Сцена | Изменяемый параметр | Проверяемое |
|---|---|---|
| Статичный сложный фон | N=1,2,4,8,16 | reuse и пассы |
| Скроллинг текста | scroll velocity | halo, shimmer, capture |
| Движущееся стекло | скорость/координаты | pixel alignment и latency |
| Изменение геометрии | scale/morph progress | matte cache |
| Разнесённые кнопки | расстояние | grouping area |
| Перекрытия | overlap ratio | sharing semantics |
| Разные sigma | sigma distribution | blur reuse |
| Множество мелких стекол | size distribution | halo overhead |
| Большой sheet | площадь покрытия | fill-rate/bandwidth |
| Mixed dynamic/static | dirty regions | invalidation |
| Длительная нагрузка | 5–15 минут | thermals/clock stability |

Контрольные фоны: тестовая сетка, контрастный текст, checkerboard, фотографии, gradient, HDR/highlights, движущийся low/high-frequency texture. Для каждой сцены визуальные артефакты сохранять как **видео**, не только PNG.

### 11.3. Ступень C: алгоритмы blur

- `sigma`: малый/средний/большой набор (например 4, 8, 16, 32; если в проекте иные рабочие значения — заменить);
- baseline Impeller Gaussian;
- Kawase с tuned offset/pass counts;
- Dual Kawase 2/3/4 уровня;
- mip + trilinear LOD;
- mip + low-tap correction;
- качество в `full`, `1/2`, `1/4`, `1/8` resolution;
- одинаковые blur support/bounds/color handling;
- N=1 и N>1 с общей предварительной обработкой.

**Не сравнивать** одну fast blurry картинку с другой по одному nominal `sigma`: подбирать параметры по внешнему Gaussian/Apple appearance reference.

### 11.4. Ступень D: GPU-профилирование

Инструменты:

- [S30] Flutter DevTools Performance — UI/raster measurements;
- [S31] Flutter Impeller RenderDoc capture — render pass, attachments, texture sizes;
- [S32] Android GPU Inspector — GPU analysis/counters при поддержке железа;
- [S33] Perfetto — CPU/GPU scheduling, frame pacing;
- [S34] Xcode profiling — iOS/Metal/power.

Собирать:

```yaml
run_id: morph-pixel6a-001
build:
  flutter: 3.47.2
  engine_revision: TODO
  mode: profile
  backend: impeller-vulkan
  commit: TODO
device:
  model: Pixel 6a
  os_build: TODO
  gpu_driver: TODO
  resolution_px: TODO
  refresh_hz: TODO
scene:
  name: scrolling_text
  lens_count: 4
  sigma_px: TODO
  geometry: capsule
  overlap: false
  grouped: true
  bounded: false
  capture_policy: live
measurements:
  gpu_frame_ms_p50: null
  gpu_frame_ms_p95: null
  gpu_frame_ms_p99: null
  raster_ms_p95: null
  jank_frames_pct: null
  render_pass_count: null
  full_res_pass_count: null
  temporary_texture_mb_est: null
  gpu_cycles: null
  gpu_clock_mhz: null
  gpu_memory_read_mb: null
  gpu_memory_write_mb: null
visual:
  baseline_image: TODO
  candidate_image: TODO
  video: TODO
  ssim: null
  lpips: null
  shimmer_observed: null
notes: TODO
```

Метрики `null` значат **не измерено**, не «ноль».

### 11.5. Ступень E: reproducibility

- Одни и те же физические размеры, animation timeline, source content.
- A/B чередовать; фиксировать порядок и условия.
- Прогреть pipeline и разделить cold shader startup от steady state.
- Не включать GPU capture overhead в основные frame-time показатели без контроля.
- Записывать GPU clocks/thermal state; при невозможности — хотя бы battery/power/температурный контекст.
- Не считать на глаз framebuffer bandwidth по формуле `samples * pixels * bytes` — это **логическая верхнеуровневая оценка**, не counter.
- Использовать одинаковые image formats и color spaces.
- Проверять release/profile, не делать выводы по debug сборке.
- Проверять p95/p99 и длительный прогон.

### 11.6. Критерии принятия альтернативы

Кандидат интересен, если он:

1. выигрывает **end-to-end**, включая capture и подготовку фоновых уровней;
2. выигрывает в нескольких репрезентативных сценах и не делает `p99` хуже;
3. не ломает fidelity на тексте, границах, движении и пересечениях;
4. не создаёт неконтролируемых peak texture memory;
5. поддерживает необходимые Android GPU/backends или предлагает корректный fallback;
6. имеет понятную инвалидацию ресурсов и жизненный цикл;
7. допускает поддержку как отдельного backend в публичном пакете.

---

## 12. Схемы альтернативной архитектуры

### 12.1. Базовый вариант — сохранить Impeller compositor

```text
Flutter Scene
  └─ BackdropFilterLayer
       ├─ Impeller Gaussian
       ├─ ImageFilter.shader
       └─ matte resource
```

**Плюсы:** зрелая интеграция, корректная презентация, ниже стоимость поддержки. **Минусы:** ограничения filter graph и reuse; некоторое offscreen-поведение контролирует engine.

### 12.2. Flutter GPU prefilter для управляемой сцены

```text
Controlled Flutter subtree
     └─ asynchronous toImage()              ← capture STILL costs
           └─ gpu.Texture.fromImage()       ← avoids CPU roundtrip
                 └─ shared mip pyramid / blur cache
                        ├─ material shader A + matte A
                        ├─ material shader B + matte B
                        └─ material shader C + matte C
                             └─ presentation as Image/Flutter layer
```

**Важный тест:** latency/jitter между scene update и реальным стеклом. Возникновение one-frame stale background может перечеркнуть пользу.

### 12.3. Идеальный shared compositor (требует поддержки engine или сложной сцены)

```text
Scene/layer graph
  ├─ damage regions
  ├─ backdrop dependencies
  ├─ spatial glass groups
  ├─ shared capture snapshots
  ├─ shared prefilter/mip resources
  ├─ geometry cache: matte/SDF/normals
  ├─ optical material variants
  └─ merged group compositing
```

Для каждой группы раздельно отслеживать:

- capture source/viewport/scale;
- blur support/PSF/tile semantics;
- dirty rect and generation ID;
- `backdropDepth`/z-order;
- geometry hash + material param version;
- GPU resource lifetime, final frame consumer.

### 12.4. Разделение ответственности в пакете

Возможная дизайн-модель (не готовый Dart API):

```text
MorphSceneCoordinator
  ├─ BackdropProvider [impeller | flutterGpuSnapshot | cached]
  ├─ PrefilterStrategy [gaussian | kawase | dualKawase | mipHybrid]
  ├─ GroupingStrategy [manual | boundsAware | updateAware]
  ├─ GeometryProvider [matte | sdf | packedNormals]
  ├─ QualityPolicy [auto | high | balanced | low]
  └─ MaterialCompositor [independent | merged]
```

**Не выставлять всё наружу сразу.** Это оси исследования и внутренних experiment flags. Пользователю пакета лучше предложить предсказуемые quality/performance профили с возможностью overrides.

---

## 13. Decision tree, приоритизация и критерии успеха

```text
1. Есть достоверный GPU capture полного кадра?
   ├─ Нет → Получить, записать passes, texture bounds, timings.
   └─ Да
       ├─ Capture/resolve dominant?
       │    └─ Да → group locality, clip/sample bounds, shared scene, damage.
       ├─ Gaussian dominant?
       │    └─ Да → Kawase/Dual/mip hybrid, сравнить с Impeller baseline.
       ├─ Material dominant?
       │    └─ Да → variant specialization, normals vs ALU, edge-only optics.
       ├─ Memory/bandwidth dominant?
       │    └─ Да → smaller targets, formats, transients, lower-res passes.
       ├─ CPU/submission dominant?
       │    └─ Да → command overhead, allocations, animation layout/caching.
       └─ Всё относительно дешево, но p99/thermal плохие?
            └─ sustained load, synchronization, peak work, adaptive policy.
```

### Рейтинг **полезности исследования**, не ожидаемого ускорения

1. **Профиль render graph** — обязательное условие всех остальных решений.
2. **Capture area + grouping + prefilter reuse** — наибольшая архитектурная перспектива.
3. **Blur algorithm showdown** — полезно, если blur действительно значим.
4. **Отделение оптики/геометрии от фона** — ключ к независимому кэшу.
5. **Shader simplification и perceptual quality policy** — особенно для маленьких контролов.
6. **Temporal caching** — только при гарантированной или управляемой инвалидации.
7. **Engine fork/low-level Vulkan** — последняя ступень при подтверждённом API bottleneck.

### Что не делать без доказательств

- Полный CPU readback каждый кадр.
- «Сделать downsample» без осознания, что Impeller его уже делает.
- Принудительно применять одинаковый BackdropKey к перекрытиям.
- Один гигантский render target на весь экран ради всех стёкол.
- Бездумно заменять Gaussian на FFT/compute.
- Считать уменьшение выборок достаточным доказательством ускорения.
- Использовать temporal reuse при fast scrolling без проверки ghosting.
- Заявлять pixel-perfect Apple Liquid Glass на основе сторонней reverse-engineered модели.

---

## 14. Ошибки, артефакты и контроль качества

| Ошибка | Причина | Проверка |
|---|---|---|
| Shimmer при движении | fractional UV/downsample alignment | subpixel motion на checkerboard |
| Светлый/тёмный halo | неверный clamp/transparent handling | яркий прямоугольник у края |
| Цветовые ореолы | premultiplication/colour space | прозрачные цветные края |
| Ступенчатый blur | дискретный LOD без интерполяции | плавная смена размера/sigma |
| Ghosting | stale cached backdrop | scrolling text под неподвижным стеклом |
| Double glass | serial blur compositing | пересекающиеся линзы |
| Избыточная мутность | blur PSF/refraction не соответствует эталону | high-contrast ROI |
| Неустойчивый tint | средняя яркость на слишком большой области | half-black half-white фон |
| Pixelation | слишком низкий mip для мелкого текста | small print background |
| Jank при первом показе | shader pipeline compilation / allocation | cold-start profiling |
| Memory creep | lifetime cache/pool | долгий screen churn |
| GLES upside-down | orientation/UV assumptions | backend cross-tests |
| Banding | точность RT или nonlinear conversion | smooth gradients HDR/SDR |
| Overdraw | большие прозрачные quads и blending | dense glass overlaps |

Также проверять accessibility/contrast и устройство в режимах reduce transparency / battery saver. Производительность не должна улучшаться за счёт непредсказуемой читаемости содержимого.

---

## 15. Реестр первоисточников и репозиториев

Список разделён по уровню надёжности. **Первоисточник** здесь означает исходник соответствующего проекта/официальную документацию; **репозиторий третьей стороны** может отражать мнение автора и нуждается в проверке. Если URL закреплён на `main`, при важном выводе сохранить commit hash отдельно.

### A. Flutter / Impeller (наибольший приоритет)

- **[S01] Flutter Engine 3.47.2 — `gaussian_blur_filter_contents.cc`.** Downsample scale, 3 command buffers, mip reuse, bounded blur, gutters, TODO по clipping/padding. [Исходник](https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/impeller/entity/contents/filters/gaussian_blur_filter_contents.cc). **Проверено, pinned version.** Поиск по символам `CalculateScale`, `MakeBlurSubpass`, `CalculateDownsamplePassArgs`, `may_reuse_mipmap`, `deviceLost`.
- **[S02] Flutter `BackdropFilter` docs.** Объединение через BackdropKey, clip, предупреждение о перекрывающихся фильтрах. [API docs](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html). **Проверено; текущие docs могут изменяться.**
- **[S03] Flutter #154046.** `deviceLost` на Samsung S21/Adreno при backdrop submission. [Issue](https://github.com/flutter/flutter/issues/154046). **Проверено как linked rationale из исходника.**
- **[S04] Flutter #191207.** Сравнительный репорт grouped/bounded blur на Windows Impeller, с benchmark-сценами и последующими корректировками выводов. [Issue](https://github.com/flutter/flutter/issues/191207). **Чужие измерения; не переносить на Pixel 6a.**
- **[S05] Flutter #188605.** `Texture.fromImage`, ограничения `toImageSync` и render attachment. [Merged PR](https://github.com/flutter/flutter/pull/188605). **Проверено, merged 2026-06-29.**
- **[S06] Flutter #140193.** Shimmer/flicker с blur. [Issue](https://github.com/flutter/flutter/issues/140193). **Контекст TODO в исходнике.**
- **[S07] Flutter #177133.** Предложение multi-input ImageFilter graph, `f(x,g(x))`, SDF/normal/refraction. [Issue](https://github.com/flutter/flutter/issues/177133). **Проверено как открытый feature request на дату сверки.**
- **[S08] Flutter 3.47 release notes.** Multi-mip textures, render to mip/slice, manual mip sampling, `Texture.fromImage`. [Release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0). **Проверено.**
- **[S09] Flutter #188365.** Проблема implicit sampler/filtering в `ImageFilter.shader`. [Issue](https://github.com/flutter/flutter/issues/188365). **Проверено как репорт, применимость к 3.47.2 требует проверки.**
- **[S20] Flutter #191867.** Deterministic disposal for `DeviceBuffer` / `Texture`. [Issue](https://github.com/flutter/flutter/issues/191867). **Проверено как отмеченное ограничение API.**
- **[S21] Flutter GLES orientation migration.** [Breaking change](https://docs.flutter.dev/release/breaking-changes/opengles-render-to-texture-top-down). **Проверено.**

### B. Apple / Android / Windows

- **[S10] Apple WWDC25 — Build an AppKit app with the new design.** Общий sampling region, grouped glass, один sampling pass для контейнера, поведение стекло-поверх-стекла. [Видео и transcript](https://developer.apple.com/videos/play/wwdc2025/310/). **Первичный официальный источник.**
- **[S11] Apple WWDC25 — Meet Liquid Glass.** Lensing, adaptive appearance, увеличение оптических эффектов с размером. [Видео и transcript](https://developer.apple.com/videos/play/wwdc2025/219/). **Первичный официальный источник.**
- **[S12] Android AOSP `SurfaceFlinger.cpp`.** Рекомендация Kawase vs Gaussian, выбор blur algorithm. [Исходник](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/SurfaceFlinger.cpp). **Первичный исходник; branch main, проверить commit при повторном анализе.**
- **[S13] Android AOSP `KawaseBlurFilter.cpp`.** Центр + 4 taps, несколько проходов. [Исходник](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/libs/renderengine/skia/filters/KawaseBlurFilter.cpp). **Первичный исходник; main.**
- **[S14] Android AOSP `KawaseBlurDualFilter.cpp`.** Multi-scale dual pass, heptagon taps, crossfade. [Pinned commit](https://android.googlesource.com/platform/frameworks/native/+/d647d6cde7f28d83dd03aeff48c3f1bdfe4622df/libs/renderengine/skia/filters/KawaseBlurDualFilter.cpp). **Первичный исходник; фиксированная ревизия.**
- **[S15] Microsoft Mica docs.** Single wallpaper sample, low-end/power fallback. [Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/style/mica). **Первичная официальная документация.**

### C. Chromium / Godot / GPU architecture

- **[S16] Chromium Viz `SurfaceAggregator`.** Damage regions, cached render passes, backdrop moving-pixel filters. [Фиксированный исходник Chromium](https://chromium.googlesource.com/chromium/src/+/d35902cb7a90d0820970468f46e5ed472645d358/components/viz/service/display/surface_aggregator.cc). **Первичный исходник, pinned commit; см. `intersects_damage_under`, `backdrop_filters`, `damage_rect`.**
- **[S17] Godot `renderer_scene_render_rd.cpp`.** Glow down/up mip, мобильный branch и pass/bandwidth tradeoff. [Исходник](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp). **Первичный исходник; main.**
- **[S18] Godot rendering architecture docs.** Mobile GPU, tile/subpass ограничения для glow/DOF. [Исходник документации](https://github.com/godotengine/godot-docs/blob/master/engine_details/architecture/internal_rendering_architecture.rst). **Первичная документация.**
- **[S19] Khronos — Tile Based Rendering Best Practices.** Attachments, render passes, load/store, bandwidth. [Vulkan Guide](https://docs.vulkan.org/guide/latest/tile_based_rendering_best_practices.html). **Первичная документация.**

### D. Репозитории Liquid Glass — читать, но критически

- **[S22] `whynotmake-it/flutter_liquid_glass`.** Архитектура Flutter glass, renderer и взаимодействие поверхностей. [GitHub](https://github.com/whynotmake-it/flutter_liquid_glass). **Проверить реализацию конкретной версии и лицензии.**
- **[S23] `medfa12/liquid-glass-react-native`.** Заявленные reverse-engineered QuartzCore shader techniques: mip LOD, optical lens, adaptive tint; Metal/iOS + GLES3/Android. [GitHub](https://github.com/medfa12/liquid-glass-react-native). **Самоописание автора; эталонность не установлена. В README указан внешний backdrop input — это не готовый захват RN UI.**
- **[S24] `rit3zh/expo-liquid-glass-view`.** iOS 26 native backend и собственный Metal backend для старых версий, `captureQuality` и knobs материала. [GitHub](https://github.com/rit3zh/expo-liquid-glass-view). **Реальный репозиторий; смотреть реализацию захвата и buffering, не полагаться на краткое описание.**
- **[S25] `himanshu-lal4/react-native-liquid-glassmorphism`.** Android AGSL/refraction и ограничения backdrop capture. [GitHub](https://github.com/himanshu-lal4/react-native-liquid-glassmorphism). **Сторонний проект, профилировать самостоятельно.**
- **[S26] `AhmeedGamil/liquid_glass_easy`.** Варианты Flutter glass batching/blending, ограничения overlap. [GitHub](https://github.com/AhmeedGamil/liquid_glass_easy). **Сторонний пакет.**
- **[S27] `liquid_glass_renderer` на pub.dev.** Пакет/исходники для сравнения решений Flutter. [pub.dev](https://pub.dev/packages/liquid_glass_renderer). **Версионировать сравнение.**

### E. Reverse engineering и GPU inspection

- **[S28] Jacob Bartlett — How do researchers reverse-engineer private frameworks?** Исходная статья обсуждения. [Статья](https://blog.jacobstechtavern.com/p/reverse-engineer-private-frameworks). **Не путать работу со Swift metadata с восстановлением shaders.**
- **[S29] YuAo/MetalLibraryArchive.** Извлечение Metal functions из `.metallib` и исследование структуры библиотек. [GitHub](https://github.com/YuAo/MetalLibraryArchive). **Доступность IR зависит от бинарника; оригинальный исходник не гарантирован.**
- **[S30] Flutter DevTools Performance.** [Docs](https://docs.flutter.dev/tools/devtools/performance). **Официально.**
- **[S31] Flutter Impeller RenderDoc Frame Capture.** [Движковая инструкция](https://flutter.googlesource.com/mirrors/flutter.git/+/HEAD/docs/engine/impeller/docs/renderdoc_frame_capture.md). **Официальный Flutter source.**
- **[S32] Android GPU Inspector.** [Docs](https://developer.android.com/agi). **Официально; ограничения по устройствам/GPU.**
- **[S33] Perfetto.** [Docs](https://perfetto.dev/docs/). **Официально.**
- **[S34] Apple WWDC — Profile and optimize power usage in your app.** [Видео](https://developer.apple.com/videos/play/wwdc2025/226/). **Официально.**
- **[S35] Dortania MetallibSupportPkg.** [GitHub](https://github.com/dortania/MetallibSupportPkg). **Исследовательский инструмент; не готовый Liquid Glass extractor.**
- **[S36] Khronos Vulkan Samples, subpasses.** [GitHub](https://github.com/KhronosGroup/Vulkan-Samples/tree/main/samples/performance/subpasses). **Пример low-level реализации/измерений, не Flutter benchmark.**

### Важное о лицензиях и заимствовании

- Исследовать и сравнивать алгоритмы — не то же самое, что копировать код в распространяемый пакет.
- Проверять **лицензии** каждой реализации и условия использования материалов Apple/SDK.
- Примеры reverse engineering полезны как исследовательские данные; не предполагать, что можно беспрепятственно переносить бинарники/декомпилированные шейдеры.
- Для публикации движкового PR лучше иметь собственную минимальную реализацию и воспроизводимый performance case.

---

## 16. Незакрытые вопросы и шаблон следующего исследования

### 16.1. Вопросы к текущему `morph`

1. Полная версия source pipeline: какие Flutter/Impeller classes, какие shader sources и formats?
2. Какая **реальная** физическая площадь capture для каждой поверхности?
3. Какие sigma встречаются в продуктовых сценах: распределение значений, а не один пример?
4. Что происходит на стекле поверх стекла: serial capture или общий источник?
5. Какая часть matte обновляется при изменении формы? Можно ли считать только грязную область?
6. Используются ли bounded blur / explicit source bounds / нестандартные tile modes?
7. Сколько texture samples у material shader и какие sampler states?
8. Есть ли subpixel shimmer при scroll и morph?
9. Как ведут себя low-end Mali/Adreno, а не только Pixel 6a?
10. Сколько GPU ms занимает первая/повторная активация стекла, и есть ли память/thermal деградация?
11. Каково качество near-native оптики на заранее заданных `Apple reference scenes`?
12. Можно ли обеспечить **живую** корректность scene texture для альтернативного Flutter GPU backend?

### 16.2. Готовый запрос для следующей работы с кодом

> Мы развиваем Flutter UI kit `morph`, Flutter 3.47.2. Ознакомься с `morph_gpu_liquid_glass_research.md`. Не начинай с предположения, что Gaussian всегда full-res или что BackdropGroup не используется. Сначала проверь фактический код `morph` и сопоставь с исходниками Impeller 3.47.2. Предложи **изолированные** измеримые эксперименты для Pixel 6a/Impeller Vulkan, с минимальными diff, чёткими метриками и стратегией отмены. Не выдавай гипотезы за доказанные ускорения. При чтении ссылок перепроверяй актуальность статусов issues/PR.

### 16.3. Шаблон карточки новой гипотезы

```md
### H21 — [краткое название]
- Статус: proposed | measuring | confirmed | rejected | superseded
- Предпосылка:
- Источники: [S..] и конкретные места в коде
- Почему это может ускорить именно morph:
- Что должно измениться в render graph:
- Риски/побочные эффекты:
- Контрольные сцены:
- A/B варианты:
- GPU/CPU/memory/power метрики:
- Визуальная оценка:
- Признак подтверждения:
- Признак опровержения:
- Устройства и backend:
- Результаты/ссылки на захваты:
- Решение:
```

### 16.4. Приоритет для ближайшего исследовательского цикла

1. **RenderDoc frame decomposition** существующего pipeline и запись фактических attachment dimensions.
2. **A/B** `capture-only / blur-only / material-only / matte-only / full`.
3. Подтверждение, где теряется время: **capture, Gaussian, shader, composition или их взаимодействие**.
4. На контролируемом фоне — **Impeller Gaussian vs Kawase vs Dual vs mip hybrid**.
5. С несколькими линзами — **общий prefiltered backdrop** и benchmark зависимости от N.
6. Только затем — архитектура producer/consumer для динамического Flutter subtree и end-to-end latency.

---

## Краткое резюме для будущего обсуждения

**Известно:** Impeller Gaussian уже делает downsample, reuse mip при условиях, separable passes; engine имеет ограничения/защитные обходы для старых GPU. Flutter 3.47 предоставляет `Texture.fromImage` и расширенные multi-mip возможности, но **не предоставляет автоматически бесплатный синхронный backdrop capture**. Apple делает grouping с shared sampling region; AOSP выбирает Kawase как практичный компромисс; Chromium показывает необходимость damage-aware invalidation; Godot показывает баланс passes и bandwidth.

**Не известно:** фактическое распределение затрат `morph` по стадиям на Pixel 6a. Значит, нельзя обоснованно обещать ускорение от любого одного blur алгоритма.

**Основная архитектурная гипотеза:** минимизировать число и размер захватов, переиспользовать один GPU-resident prefiltered background в нескольких линзах, отдельно кэшировать matte/normal geometry и выбирать минимально достаточную оптическую сложность.

**Следующий шаг:** сначала **профиль реального GPU кадра** с разбивкой на render passes и render target sizes. После этого выбор эксперимента станет инженерным, а не интуитивным.

---

_Документ намеренно сохраняет и альтернативные теории, и условия их опровержения; ссылки — отправная точка для исследования, а не список гарантированных оптимизаций._

<!-- Reference links for the Markdown labels used throughout. -->
[S01]: https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/impeller/entity/contents/filters/gaussian_blur_filter_contents.cc
[S02]: https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html
[S03]: https://github.com/flutter/flutter/issues/154046
[S04]: https://github.com/flutter/flutter/issues/191207
[S05]: https://github.com/flutter/flutter/pull/188605
[S06]: https://github.com/flutter/flutter/issues/140193
[S07]: https://github.com/flutter/flutter/issues/177133
[S08]: https://docs.flutter.dev/release/release-notes/release-notes-3.47.0
[S09]: https://github.com/flutter/flutter/issues/188365
[S10]: https://developer.apple.com/videos/play/wwdc2025/310/
[S11]: https://developer.apple.com/videos/play/wwdc2025/219/
[S12]: https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/SurfaceFlinger.cpp
[S13]: https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/libs/renderengine/skia/filters/KawaseBlurFilter.cpp
[S14]: https://android.googlesource.com/platform/frameworks/native/+/d647d6cde7f28d83dd03aeff48c3f1bdfe4622df/libs/renderengine/skia/filters/KawaseBlurDualFilter.cpp
[S15]: https://learn.microsoft.com/en-us/windows/apps/design/style/mica
[S16]: https://chromium.googlesource.com/chromium/src/+/d35902cb7a90d0820970468f46e5ed472645d358/components/viz/service/display/surface_aggregator.cc
[S17]: https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp
[S18]: https://github.com/godotengine/godot-docs/blob/master/engine_details/architecture/internal_rendering_architecture.rst
[S19]: https://docs.vulkan.org/guide/latest/tile_based_rendering_best_practices.html
[S20]: https://github.com/flutter/flutter/issues/191867
[S21]: https://docs.flutter.dev/release/breaking-changes/opengles-render-to-texture-top-down
[S23]: https://github.com/medfa12/liquid-glass-react-native
[S28]: https://blog.jacobstechtavern.com/p/reverse-engineer-private-frameworks
[S29]: https://github.com/YuAo/MetalLibraryArchive
[S30]: https://docs.flutter.dev/tools/devtools/performance
[S31]: https://flutter.googlesource.com/mirrors/flutter.git/+/HEAD/docs/engine/impeller/docs/renderdoc_frame_capture.md
[S32]: https://developer.android.com/agi
[S33]: https://perfetto.dev/docs/
[S34]: https://developer.apple.com/videos/play/wwdc2025/226/
[S22]: https://github.com/whynotmake-it/flutter_liquid_glass
[S24]: https://github.com/rit3zh/expo-liquid-glass-view
[S25]: https://github.com/himanshu-lal4/react-native-liquid-glassmorphism
[S26]: https://github.com/AhmeedGamil/liquid_glass_easy
[S27]: https://pub.dev/packages/liquid_glass_renderer
[S35]: https://github.com/dortania/MetallibSupportPkg
[S36]: https://github.com/KhronosGroup/Vulkan-Samples/tree/main/samples/performance/subpasses
