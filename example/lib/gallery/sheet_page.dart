import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Sheets the way UIKit presents them: a floating glass sheet at the
/// medium detent that docks edge to edge at the large one, a large-only
/// sheet, an undimmed medium detent over a live page, a sheet with a
/// grouped list that hands its drags to the sheet and turns its
/// background with it, and a sheet that zooms out of the button that
/// presents it.
///
/// The page options build a sheet of their own: its detents (fitted,
/// custom, fraction), the detent it opens at, the grabber, the undimmed
/// detent, a sheet that refuses dismissal (`dismissible: false` or a
/// `PopScope`, both reporting the attempt), and a [MorphSheetRoute]
/// pushed directly instead of [showMorphSheet]. The page reads out every
/// detent change and dismissal attempt.
class SheetPage extends StatefulWidget {
  /// Creates the page.
  const SheetPage({super.key});

  @override
  State<SheetPage> createState() => _SheetPageState();
}

enum _Detents { mediumLarge, large, three, fitted, custom, fraction }

enum _Refuse { none, dismissible, popScope }

class _SheetPageState extends State<SheetPage> {
  String _last = 'Present a sheet';
  String _detent = '-';
  int _attempts = 0;
  int _taps = 0;

  _Detents _detents = .mediumLarge;
  bool _openLarge = false;
  bool _grabber = true;
  bool _undimmed = false;
  _Refuse _refuse = .none;
  bool _route = false;
  bool _listContent = false;

  static double _custom(double maximum) => maximum - 160;

  List<MorphSheetDetent> get _built => switch (_detents) {
    .mediumLarge => const [MorphSheetDetent.medium, MorphSheetDetent.large],
    .large => const [MorphSheetDetent.large],
    .three => const [
      MorphSheetDetent.height(200),
      MorphSheetDetent.medium,
      MorphSheetDetent.large,
    ],
    .fitted => const [MorphSheetDetent.fitted, MorphSheetDetent.large],
    .custom => const [
      MorphSheetDetent.custom(_custom, identifier: 'maximum - 160'),
    ],
    .fraction => const [
      MorphSheetDetent.fraction(0.3),
      MorphSheetDetent.fraction(0.7),
    ],
  };

  void _detentChanged(MorphSheetDetent detent) {
    if (mounted) setState(() => _detent = '$detent');
  }

  void _attempted() {
    if (mounted) setState(() => _attempts++);
  }

  Future<void> _present(
    String name,
    List<MorphSheetDetent> detents, {
    MorphSheetDetent? undimmed,
    bool list = false,
    Object? from,
  }) async {
    final result = await showMorphSheet<String>(
      context,
      from: from,
      detents: detents,
      largestUndimmedDetent: undimmed,
      grabberVisible: detents.length > 1,
      semanticLabel: name,
      onDetentChanged: _detentChanged,
      builder: (BuildContext context) =>
          list ? const _ListSheet() : _PlainSheet(title: name),
    );
    if (!mounted) return;
    setState(() => _last = result ?? '$name dismissed');
  }

  Future<void> _presentBuilt() async {
    final detents = _built;
    const name = 'Built from the options';
    Widget content(BuildContext context) {
      final body = _listContent
          ? const _ListSheet()
          : _PlainSheet(title: name, fitted: _detents == .fitted);
      if (_refuse != .popScope) return body;
      return PopScope<String>(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, String? result) {
          if (!didPop) _attempted();
        },
        child: body,
      );
    }

    final initial = _openLarge ? detents.last : detents.first;
    final undimmed = _undimmed && detents.length > 1 ? detents.first : null;
    final dismissible = _refuse != .dismissible;
    final String? result;
    if (_route) {
      result = await Navigator.of(context).push<String>(
        MorphSheetRoute<String>(
          builder: content,
          detents: detents,
          initialDetent: initial,
          largestUndimmedDetent: undimmed,
          grabberVisible: _grabber,
          dismissible: dismissible,
          semanticLabel: name,
          onDetentChanged: _detentChanged,
          onDismissAttempt: _refuse == .dismissible ? _attempted : null,
        ),
      );
    } else {
      result = await showMorphSheet<String>(
        context,
        builder: content,
        detents: detents,
        initialDetent: initial,
        largestUndimmedDetent: undimmed,
        grabberVisible: _grabber,
        dismissible: dismissible,
        semanticLabel: name,
        onDetentChanged: _detentChanged,
        onDismissAttempt: _refuse == .dismissible ? _attempted : null,
      );
    }
    if (!mounted) return;
    setState(() => _last = result ?? '$name dismissed');
  }

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Detents'),
      children: [
        GalleryChoice<_Detents>(
          label: 'Detents',
          options: const {
            _Detents.mediumLarge: 'M+L',
            _Detents.large: 'L',
            _Detents.three: '3',
          },
          value: _detents,
          onChanged: (_Detents v) => setState(() => _detents = v),
        ),
        GalleryChoice<_Detents>(
          label: 'Sized',
          options: const {
            _Detents.fitted: 'Fitted',
            _Detents.custom: 'Custom',
            _Detents.fraction: 'Fraction',
          },
          value: _detents,
          onChanged: (_Detents v) => setState(() => _detents = v),
        ),
        GalleryToggle(
          label: 'Open at the largest',
          value: _openLarge,
          onChanged: (bool v) => setState(() => _openLarge = v),
        ),
        GalleryToggle(
          label: 'Grabber',
          value: _grabber,
          onChanged: (bool v) => setState(() => _grabber = v),
        ),
        GalleryToggle(
          label: 'Smallest undimmed',
          value: _undimmed,
          onChanged: (bool v) => setState(() => _undimmed = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Dismissal'),
      footer: const Text(
        'A refused dismissal rubber-bands and reports the attempt.',
      ),
      children: [
        GalleryChoice<_Refuse>(
          label: 'Refuse',
          options: const {
            _Refuse.none: 'No',
            _Refuse.dismissible: 'Flag',
            _Refuse.popScope: 'PopScope',
          },
          value: _refuse,
          onChanged: (_Refuse v) => setState(() => _refuse = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Presentation'),
      children: [
        GalleryToggle(
          label: 'Push MorphSheetRoute',
          value: _route,
          onChanged: (bool v) => setState(() => _route = v),
        ),
        GalleryToggle(
          label: 'Grouped list content',
          value: _listContent,
          onChanged: (bool v) => setState(() => _listContent = v),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Sheets',
      options: _options,
      slivers: [
        SliverPadding(
          padding: const .all(20),
          sliver: SliverToBoxAdapter(
            child: MorphGlassContainer(
              solidBackdrop: MorphListAppearance.resolve(
                context,
                null,
              ).backgroundColor,
              child: Column(
                crossAxisAlignment: .stretch,
                children: _list(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _button(String label, VoidCallback onTap) => Padding(
    padding: const .only(bottom: 12),
    child: SizedBox(
      height: 48,
      child: MorphGlassButton(onPressed: onTap, child: Text(label)),
    ),
  );

  List<Widget> _list(BuildContext context) {
    final secondary = TextStyle(color: gallerySecondaryColor(context));
    return [
      Text(_last, style: secondary),
      const SizedBox(height: 4),
      Text('Detent changed to: $_detent', style: secondary),
      const SizedBox(height: 4),
      Text('Dismiss attempts: $_attempts', style: secondary),
      const SizedBox(height: 16),
      _button('Sheet from the page options', _presentBuilt),
      _button(
        'Medium and large',
        () => _present('Medium and large', const [
          MorphSheetDetent.medium,
          MorphSheetDetent.large,
        ]),
      ),
      _button(
        'Large only',
        () => _present('Large only', const [MorphSheetDetent.large]),
      ),
      _button(
        'Small, medium, large',
        () => _present('Three detents', const [
          MorphSheetDetent.height(200),
          MorphSheetDetent.medium,
          MorphSheetDetent.large,
        ]),
      ),
      _button(
        'Undimmed medium',
        () => _present('Undimmed medium', const [
          MorphSheetDetent.medium,
          MorphSheetDetent.large,
        ], undimmed: MorphSheetDetent.medium),
      ),
      _button(
        'Grouped list that drags the sheet',
        () => _present('List', const [
          MorphSheetDetent.medium,
          MorphSheetDetent.large,
        ], list: true),
      ),
      Padding(
        padding: const .only(bottom: 12),
        child: SizedBox(
          height: 48,
          child: MorphTag(
            id: 'zoom',
            shape: const StadiumBorder(),
            child: MorphGlassButton(
              onPressed: () => _present('Zoomed from its button', const [
                MorphSheetDetent.medium,
                MorphSheetDetent.large,
              ], from: 'zoom'),
              child: const Text('Zoom from this button'),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Taps on the page behind an undimmed sheet: $_taps',
        style: secondary,
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 48,
        child: MorphGlassButton(
          onPressed: () => setState(() => _taps++),
          child: const Text('Tap me through the sheet'),
        ),
      ),
    ];
  }
}

class _PlainSheet extends StatelessWidget {
  const _PlainSheet({required this.title, this.fitted = false});

  final String title;

  /// Whether the content takes only its own height (a fitted detent).
  final bool fitted;

  @override
  Widget build(BuildContext context) {
    final sheet = MorphSheet.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const .fromLTRB(24, 32, 24, 16),
        child: MorphGlassContainer(
          child: Column(
            mainAxisSize: fitted ? .min : .max,
            crossAxisAlignment: .stretch,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: .w700),
              ),
              const SizedBox(height: 16),
              for (final detent in sheet.detents)
                Padding(
                  padding: const .only(bottom: 10),
                  child: SizedBox(
                    height: 44,
                    child: MorphGlassButton(
                      onPressed: () => sheet.animateTo(detent),
                      child: Text('Go to $detent'),
                    ),
                  ),
                ),
              SizedBox(
                height: 44,
                child: MorphGlassButton(
                  onPressed: () => Navigator.of(context).pop('Done in $title'),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped list in a sheet: its background is clear while the sheet
/// floats and turns grouped gray when it docks, as UIKit's inset grouped
/// table does.
class _ListSheet extends StatelessWidget {
  const _ListSheet();

  @override
  Widget build(BuildContext context) {
    return MorphListBackground(
      child: CustomScrollView(
        controller: MorphSheet.scrollControllerOf(context),
        slivers: [
          const SliverPadding(padding: .only(top: 24)),
          MorphSliverListSection(
            header: const Text('Rows'),
            itemCount: 40,
            itemBuilder: (BuildContext context, int i) => MorphListRow(
              title: Text('Row $i'),
              onTap: () => Navigator.of(context).pop('Row $i'),
            ),
          ),
        ],
      ),
    );
  }
}
