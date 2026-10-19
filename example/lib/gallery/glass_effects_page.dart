import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';
// The inspector is a development overlay, not public API.
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_inspector.dart';

/// Glass effects in every shape, style and tint, interactive or not, with
/// and without a shared glass container.
///
/// The page options pick the tint, the interaction and the container of
/// the shapes, and show a glass inspector over the page at a chosen
/// corner, which counts the glass layers the two clusters at the bottom
/// draw with and without a [MorphGlassContainer].
class GlassEffectsPage extends StatefulWidget {
  /// Creates the page.
  const GlassEffectsPage({super.key});

  @override
  State<GlassEffectsPage> createState() => _GlassEffectsPageState();
}

class _GlassEffectsPageState extends State<GlassEffectsPage> {
  Color? _tint;
  bool _interactive = true;
  bool _contained = false;
  bool _inspector = false;
  AlignmentDirectional _alignment = AlignmentDirectional.bottomStart;

  static final _alignments = {
    AlignmentDirectional.topStart: 'Top',
    AlignmentDirectional.center: 'Center',
    AlignmentDirectional.bottomStart: 'Bottom',
    AlignmentDirectional.bottomEnd: 'End',
  };

  static const _rounded = RoundedRectangleBorder(
    borderRadius: .all(.circular(16)),
  );

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Shapes'),
      children: [
        GalleryColorChoice(
          label: 'Tint',
          value: _tint,
          onChanged: (Color? c) => setState(() => _tint = c),
        ),
        GalleryToggle(
          label: 'Interactive',
          value: _interactive,
          onChanged: (bool v) => setState(() => _interactive = v),
        ),
        GalleryToggle(
          label: 'In a glass container',
          value: _contained,
          onChanged: (bool v) => setState(() => _contained = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('Inspector'),
      footer: const Text(
        'The inspector counts the glass layers of each frame. The '
        'contained cluster shades its four shapes in one layer; the '
        'other draws four.',
      ),
      children: [
        if (!kReleaseMode)
          GalleryToggle(
            label: 'Glass inspector here',
            value: _inspector,
            onChanged: (bool v) => setState(() => _inspector = v),
          ),
        GalleryChoice<AlignmentDirectional>(
          label: 'Alignment',
          options: _alignments,
          value: _alignment,
          onChanged: kReleaseMode
              ? null
              : (AlignmentDirectional a) => setState(() => _alignment = a),
        ),
      ],
    ),
  ];

  Widget _effect(
    BuildContext context, {
    required ShapeBorder shape,
    required MorphGlassStyle style,
    required Widget child,
  }) {
    final enabled = !GalleryGlassScope.of(context, .disabled).disabled;
    return MorphGlassEffect(
      shape: shape,
      style: style,
      tint: _tint,
      interactive: _interactive && enabled,
      child: child,
    );
  }

  Widget _shapes(BuildContext context, MorphGlassStyle style) {
    final name = switch (style) {
      MorphGlassStyle.regular => 'Regular',
      MorphGlassStyle.clear => 'Clear',
    };
    return Column(
      children: [
        Text(name, style: const TextStyle(fontWeight: .w600)),
        const SizedBox(height: 14),
        _effect(
          context,
          shape: const StadiumBorder(),
          style: style,
          child: const Padding(
            padding: .symmetric(horizontal: 20, vertical: 12),
            child: Text('Capsule'),
          ),
        ),
        const SizedBox(height: 16),
        _effect(
          context,
          shape: const CircleBorder(),
          style: style,
          child: const SizedBox.square(
            dimension: 56,
            child: Icon(Icons.favorite_border),
          ),
        ),
        const SizedBox(height: 16),
        _effect(
          context,
          shape: _rounded,
          style: style,
          child: const SizedBox(
            width: 128,
            height: 64,
            child: Center(child: Text('Rounded')),
          ),
        ),
      ],
    );
  }

  Widget _cluster(BuildContext context, String label) => Column(
    children: [
      Text(label, style: const TextStyle(fontWeight: .w600)),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: .center,
        children: [
          for (final icon in const [
            Icons.play_arrow,
            Icons.pause,
            Icons.skip_next,
            Icons.repeat,
          ])
            _effect(
              context,
              shape: const CircleBorder(),
              style: .regular,
              child: SizedBox.square(dimension: 48, child: Icon(icon)),
            ),
        ],
      ),
    ],
  );

  Widget _scene(BuildContext context, bool dark) {
    final shapes = Row(
      mainAxisAlignment: .spaceEvenly,
      crossAxisAlignment: .start,
      children: [_shapes(context, .regular), _shapes(context, .clear)],
    );
    return Stack(
      children: [
        Positioned.fill(child: _Backdrop(dark: dark)),
        DefaultTextStyle.merge(
          style: TextStyle(color: dark ? Colors.white : Colors.black),
          child: IconTheme.merge(
            data: IconThemeData(color: dark ? Colors.white : Colors.black),
            child: Padding(
              padding: const .fromLTRB(16, 24, 16, 32),
              child: Column(
                children: [
                  if (_contained)
                    MorphGlassContainer(child: shapes)
                  else
                    shapes,
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: MorphGlassContainer(
                          child: _cluster(context, 'In a container'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _cluster(context, 'On their own')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GalleryPage(
      title: 'Glass effects',
      options: _options,
      slivers: [
        SliverToBoxAdapter(
          child: BackdropGroup(
            child: MorphGlassInspector(
              enabled: _inspector,
              alignment: _alignment,
              child: _scene(context, dark),
            ),
          ),
        ),
        const SliverPadding(
          padding: .fromLTRB(32, 0, 32, 120),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption(
              'MorphGlassEffect puts glass behind any content: a capsule, a '
              'circle or a rounded rectangle, in the regular or the clear '
              'material, tinted or not. Interactive glass lifts and '
              'stretches toward a dragging finger like a glass button. '
              'Page options tint the shapes, turn the interaction off, join '
              'them in one MorphGlassContainer and show the glass '
              'inspector.',
            ),
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    const stripes = <(double, Color)>[
      (0.1, Color(0xFFFF2D55)),
      (0.35, Color(0xFFFF9500)),
      (0.6, Color(0xFF34C759)),
      (0.85, Color(0xFF5856D6)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: .topLeft,
          end: .bottomRight,
          colors: dark
              ? const [Color(0xFF0B1E3D), Color(0xFF2B0B3D)]
              : const [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => Stack(
          children: [
            for (final (x, color) in stripes)
              Positioned(
                left: box.maxWidth * x - 18,
                top: 0,
                bottom: 0,
                width: 36,
                child: ColoredBox(
                  color: color.withValues(alpha: dark ? 0.55 : 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
