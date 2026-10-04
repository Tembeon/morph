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

  Widget _row(String label, Widget picker) => MorphListRow(
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: FittedBox(
        fit: .scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: picker,
      ),
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
    return Stack(
      children: [
        GalleryPage(
          title: 'Date picker',
          slivers: [
            SliverToBoxAdapter(
              child: MorphListSection(
                children: [
                  _row('Date', _picker(.date)),
                  _row('Time', _picker(.time)),
                  _row('Starts', _picker(.dateAndTime)),
                  _row('Disabled', _picker(.date, enabled: false)),
                ],
              ),
            ),
            SliverPadding(
              padding: const .symmetric(horizontal: 36),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Picked: $_value',
                  style: TextStyle(color: gallerySecondaryColor(context)),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: galleryCardColor(context),
              borderRadius: const .all(
                .circular(MorphListMetrics.cornerRadius),
              ),
            ),
            child: Padding(padding: const .all(8), child: _picker(.date)),
          ),
        ),
      ],
    );
  }
}
