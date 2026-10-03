import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The iOS 27 compact date picker: a date, a time, both, one near the
/// bottom of the screen whose calendar opens above it, one at the trailing
/// edge, and a disabled one.
class DatePickerPage extends StatefulWidget {
  /// Creates the page.
  const DatePickerPage({super.key});

  @override
  State<DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<DatePickerPage> {
  DateTime _value = DateTime(2026, 10, 3, 9, 41);

  Widget _row(String label, Widget picker) => Container(
    height: 56,
    padding: const .symmetric(horizontal: 16),
    child: Row(
      children: [
        Text(label),
        const SizedBox(width: 16),
        Expanded(
          child: FittedBox(
            fit: .scaleDown,
            alignment: .centerRight,
            child: picker,
          ),
        ),
      ],
    ),
  );

  MorphDatePicker _picker(MorphDatePickerMode mode, {bool enabled = true}) =>
      MorphDatePicker(
        value: _value,
        mode: mode,
        semanticLabel: 'Event',
        onChanged: enabled ? (DateTime v) => setState(() => _value = v) : null,
      );

  @override
  Widget build(BuildContext context) {
    final card = galleryCardColor(context);
    return Scaffold(
      appBar: const GalleryBar(title: 'Date picker'),
      body: Stack(
        children: [
          ListView(
            padding: const .all(16),
            children: [
              Material(
                color: card,
                borderRadius: .circular(26),
                clipBehavior: .antiAlias,
                child: Column(
                  children: [
                    _row('Date', _picker(.date)),
                    _row('Time', _picker(.time)),
                    _row('Starts', _picker(.dateAndTime)),
                    _row('Disabled', _picker(.date, enabled: false)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Picked: $_value',
                style: const TextStyle(color: Color(0xFF8E8E93)),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 48,
            child: Material(
              color: card,
              borderRadius: .circular(26),
              child: Padding(padding: const .all(8), child: _picker(.date)),
            ),
          ),
        ],
      ),
    );
  }
}
