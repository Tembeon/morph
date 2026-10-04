import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Shows the deformation and lift UIKit derives for a surface size.
class SpecInspectorPage extends StatefulWidget {
  /// Creates the page.
  const SpecInspectorPage({super.key});

  @override
  State<SpecInspectorPage> createState() => _SpecInspectorPageState();
}

class _SpecInspectorPageState extends State<SpecInspectorPage> {
  double _width = 94;
  double _height = 54;
  bool _loupe = false;

  @override
  Widget build(BuildContext context) {
    final size = Size(_width, _height);
    final spec = _loupe
        ? MorphFlexSpec.loupeForSize(size)
        : MorphFlexSpec.forSize(size);
    final rows = <(String, String)>[
      ('Lift', '${spec.liftScalePoints.toStringAsFixed(2)} px'),
      (
        'Release spring',
        '${spec.scaleSpring.response.toStringAsFixed(3)} s, '
            'damping ${spec.scaleSpring.dampingRatio.toStringAsFixed(3)}',
      ),
      (
        'Tracking spring',
        '${spec.trackingSpring.response.toStringAsFixed(3)} s, '
            'damping ${spec.trackingSpring.dampingRatio.toStringAsFixed(3)}',
      ),
      ('Movement', '${spec.movementScalePoints.toStringAsFixed(1)} px'),
      (
        'Scale range',
        '${spec.movementMinScale.toStringAsFixed(3)} - '
            '${spec.movementMaxScale.toStringAsFixed(3)}',
      ),
      ('Stretch threshold', spec.scaleDistanceThreshold.toStringAsFixed(0)),
    ];
    return GalleryPage(
      title: 'Size to physics',
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            child: Center(
              child: Container(
                width: _width,
                height: _height,
                decoration: BoxDecoration(
                  color: galleryCardColor(context),
                  borderRadius: .circular(_height / 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x22000000), blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: MorphListSection(
            header: 'Surface',
            children: [
              MorphListRow(
                title: const Text('Loupe'),
                trailing: MorphSwitch(
                  value: _loupe,
                  semanticLabel: 'Loupe',
                  onChanged: (bool v) => setState(() => _loupe = v),
                ),
              ),
              _Knob(
                label: 'Width',
                value: _width,
                min: 20,
                max: 360,
                onChanged: (double v) => setState(() => _width = v),
              ),
              _Knob(
                label: 'Height',
                value: _height,
                min: 20,
                max: 200,
                onChanged: (double v) => setState(() => _height = v),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: MorphListSection(
            header: 'Physics',
            children: [
              for (final (label, value) in rows)
                MorphListRow(
                  title: Text(label),
                  detail: Text(
                    value,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return MorphListRow(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text('$label ${value.round()}'),
          const SizedBox(height: 8),
          MorphSlider(
            value: (value - min) / (max - min),
            semanticLabel: label,
            onChanged: (double t) => onChanged(min + t * (max - min)),
          ),
        ],
      ),
    );
  }
}
