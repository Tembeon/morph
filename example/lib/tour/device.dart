import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

/// A phone-shaped stage for a scene mockup. On a roomy layout it draws
/// the device shell (bezel, status bar, home indicator); in a tight
/// one the mockup fills the slot with only a soft clip.
///
/// The frame hosts its OWN [MorphScope] and [Navigator], so every
/// flight, popover and route launched by the mockup stays inside the
/// glass - a dialog cannot outgrow the phone, and a morph route pushes
/// into the phone's history like on a real device.
class PhoneFrame extends StatelessWidget {
  /// Creates the stage around the app built by [app].
  const PhoneFrame({super.key, required this.app, this.keyboard});

  /// Builds the mockup's home page inside the phone's navigator.
  final WidgetBuilder app;

  /// The key of the drawn keyboard, for tests that check what it covers.
  static const Key keyboardKey = ValueKey<String>('phone-keyboard');

  /// The height of a software keyboard drawn over the app, live: the
  /// phone reports it as the bottom view inset (exactly what a real
  /// keyboard does) and covers the app's bottom with a key panel, so
  /// anything that must stay clear of the keyboard has to move. Null
  /// means no keyboard.
  final ValueListenable<double>? keyboard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool framed =
            constraints.maxWidth >= 500 && constraints.maxHeight >= 520;
        final Widget navigator = Navigator(
          onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (BuildContext context) => _PhoneHome(app: app),
          ),
        );
        final ValueListenable<double>? keyboard = this.keyboard;
        final Widget core = MorphScope(
          child: ClipRRect(
            borderRadius: .circular(framed ? 30 : 22),
            child: ColoredBox(
              color: const Color(0xFF15121F),
              child: keyboard == null
                  ? navigator
                  : ValueListenableBuilder<double>(
                      valueListenable: keyboard,
                      // The navigator is built once; only the inset
                      // it reads and the panel over it move.
                      child: navigator,
                      builder:
                          (BuildContext context, double height, Widget? child) {
                            return Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      viewInsets: EdgeInsets.only(
                                        bottom: height,
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: height,
                                  child: const _Keyboard(
                                    key: PhoneFrame.keyboardKey,
                                  ),
                                ),
                              ],
                            );
                          },
                    ),
            ),
          ),
        );
        if (!framed) {
          return core;
        }
        final double height = constraints.maxHeight.clamp(0, 780).toDouble();
        return Center(
          child: SizedBox(
            width: 372,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: .circular(40),
                color: const Color(0xFF0B0910),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(padding: const .all(9), child: core),
            ),
          ),
        );
      },
    );
  }
}

/// The software keyboard the phone draws over its app: a key panel
/// that covers whatever sits under it.
class _Keyboard extends StatelessWidget {
  const _Keyboard({super.key});

  static const List<int> _rows = <int>[10, 9, 7];

  @override
  Widget build(BuildContext context) {
    final Color key = Colors.white.withValues(alpha: 0.16);
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1A2B),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Padding(
            padding: const .fromLTRB(6, 12, 6, 0),
            child: Column(
              mainAxisSize: .min,
              children: <Widget>[
                for (final int count in _rows)
                  Padding(
                    padding: const .only(bottom: 9),
                    child: Row(
                      mainAxisAlignment: .center,
                      children: <Widget>[
                        for (int i = 0; i < count; i++)
                          Padding(
                            padding: const .symmetric(horizontal: 2.5),
                            child: Container(
                              width: 28,
                              height: 38,
                              decoration: BoxDecoration(
                                color: key,
                                borderRadius: .circular(6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  width: 190,
                  height: 38,
                  decoration: BoxDecoration(
                    color: key,
                    borderRadius: .circular(6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's root page: a fake status bar and home indicator around
/// the scene's mockup, so every scene reads as an app, not a canvas.
class _PhoneHome extends StatelessWidget {
  const _PhoneHome({required this.app});

  final WidgetBuilder app;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const _StatusBar(),
        Expanded(child: app(context)),
        const _HomeIndicator(),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final Color dim = Colors.white.withValues(alpha: 0.55);
    return Padding(
      padding: const .fromLTRB(24, 10, 22, 2),
      child: Row(
        children: <Widget>[
          Text(
            '9:41',
            style: TextStyle(fontSize: 12, fontWeight: .w600, color: dim),
          ),
          const Spacer(),
          Icon(Icons.signal_cellular_alt_rounded, size: 13, color: dim),
          const SizedBox(width: 5),
          Icon(Icons.wifi_rounded, size: 13, color: dim),
          const SizedBox(width: 5),
          Icon(Icons.battery_5_bar_rounded, size: 13, color: dim),
        ],
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(top: 6, bottom: 8),
      child: Container(
        width: 110,
        height: 4,
        decoration: BoxDecoration(
          borderRadius: .circular(2),
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

/// Adaptive chapter layout: the lesson's own chrome (layer tabs,
/// knobs, hints) sits BESIDE the phone on wide screens and above it on
/// narrow ones. The mockup inside the frame never carries lesson
/// chrome - the phone shows the app, the panel teaches.
class SceneScaffold extends StatelessWidget {
  /// Creates the layout around [phone] with optional lesson [controls].
  const SceneScaffold({super.key, required this.phone, this.controls});

  /// The [PhoneFrame] (or any demo stage).
  final Widget phone;

  /// Lesson-side chrome; keep it compact - narrow layouts stack it
  /// above the phone.
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final Widget? panel = controls;
    if (panel == null) {
      return phone;
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 860) {
          return Row(
            children: <Widget>[
              SizedBox(
                width: 300,
                child: ListView(
                  padding: const .only(top: 8, right: 4),
                  children: <Widget>[panel],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(child: phone),
            ],
          );
        }
        return Column(
          children: <Widget>[
            panel,
            const SizedBox(height: 10),
            Expanded(child: phone),
          ],
        );
      },
    );
  }
}

/// A labeled block inside the lesson panel: small caps title over
/// content, matching the taste-note styling of the chapter header.
class PanelSection extends StatelessWidget {
  /// Creates a labeled panel block.
  const PanelSection({super.key, required this.label, required this.child});

  /// Small-caps section label.
  final String label;

  /// Section content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(bottom: 14),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: .w700,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// A labeled slider row for the lesson panel. Sliders stay plain by
/// design: a slider is direct manipulation, the finger owns it 1:1.
class PanelKnob extends StatelessWidget {
  /// Creates a labeled slider row.
  const PanelKnob({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  /// Row label.
  final String label;

  /// Current value.
  final double value;

  /// Slider minimum.
  final double min;

  /// Slider maximum.
  final double max;

  /// Formats the value readout.
  final String Function(double value) format;

  /// Change handler.
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            format(value),
            textAlign: .right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// A hint line under the lesson controls.
class PanelHint extends StatelessWidget {
  /// Creates a dim hint line.
  const PanelHint(this.text, {super.key});

  /// The hint text.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(top: 2, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.4,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
