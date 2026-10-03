import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Alerts and action sheets the way iOS 27 presents them: alerts with a
/// row or a column of buttons, a text field and a preferred action, and
/// action sheets that grow out of the button that summoned them, or show
/// as an alert when nothing summoned them.
class AlertPage extends StatefulWidget {
  /// Creates the page.
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage> {
  String _last = 'Show an alert or an action sheet';

  void _said(String what) {
    if (mounted) setState(() => _last = what);
  }

  List<MorphAlertAction> _actions(List<(String, MorphAlertActionStyle)> list) =>
      [
        for (final (title, style) in list)
          MorphAlertAction(
            title: title,
            style: style,
            onPressed: () => _said('$title chosen'),
          ),
      ];

  Future<void> _alert(String name, {bool field = false}) async {
    final (title, message, actions) = switch (name) {
      'two' => (
        'Allow notifications?',
        'Alerts, sounds and badges keep you in the loop.',
        _actions(const [("Don't Allow", .cancel), ('Allow', .normal)]),
      ),
      'three' => (
        'Delete this photo?',
        'It is removed from all your devices.',
        _actions(const [
          ('Keep', .normal),
          ('Delete', .destructive),
          ('Cancel', .cancel),
        ]),
      ),
      'preferred' => (
        'Save changes?',
        null,
        [
          MorphAlertAction(
            title: 'Discard',
            style: .destructive,
            onPressed: () => _said('Discard chosen'),
          ),
          MorphAlertAction(
            title: 'Save',
            isPreferred: true,
            onPressed: () => _said('Save chosen'),
          ),
        ],
      ),
      _ => (
        'Rename',
        'Enter a new name for the album.',
        _actions(const [('Cancel', .cancel), ('Rename', .normal)]),
      ),
    };
    final controller = TextEditingController(text: field ? 'Summer' : null);
    final chosen = await showMorphAlert(
      context,
      title: title,
      message: message,
      actions: actions,
      textFields: [
        if (field)
          MorphAlertTextField(placeholder: 'Name', controller: controller),
      ],
    );
    if (field && chosen?.title == 'Rename') {
      _said('Renamed to ${controller.text}');
    }
    controller.dispose();
  }

  Future<void> _sheet(BuildContext anchor, {bool anchored = true}) async {
    await showMorphActionSheet(
      context,
      anchor: anchored ? anchor : null,
      title: 'Share photo',
      message: 'Choose where it goes.',
      actions: _actions(const [
        ('Messages', .normal),
        ('Mail', .normal),
        ('Delete', .destructive),
        ('Cancel', .cancel),
      ]),
    );
  }

  Widget _button(String label, VoidCallback onTap) => SizedBox(
    height: 48,
    child: MorphGlassButton(onPressed: onTap, child: Text(label)),
  );

  Widget _sheetButton(String label, {bool anchored = true}) => Builder(
    builder: (BuildContext anchor) =>
        _button(label, () => _sheet(anchor, anchored: anchored)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GalleryBar(title: 'Alerts'),
      body: Stack(
        children: [
          ListView(
            padding: const .fromLTRB(20, 20, 20, 120),
            children: [
              Text(_last, style: const TextStyle(color: Color(0xFF8E8E93))),
              const SizedBox(height: 16),
              for (final (label, name, field) in const [
                ('Two buttons in a row', 'two', false),
                ('Three buttons, destructive, cancel last', 'three', false),
                ('A preferred action', 'preferred', false),
                ('A text field', 'field', true),
              ])
                Padding(
                  padding: const .only(bottom: 12),
                  child: _button(label, () => _alert(name, field: field)),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const .only(bottom: 12),
                child: _sheetButton('Action sheet from this button'),
              ),
              Padding(
                padding: const .only(bottom: 12),
                child: _sheetButton(
                  'Action sheet without a source',
                  anchored: false,
                ),
              ),
            ],
          ),
          Positioned(
            left: 20,
            bottom: 40,
            child: SizedBox(width: 120, child: _sheetButton('Low left')),
          ),
          Positioned(
            right: 20,
            bottom: 40,
            child: SizedBox(width: 120, child: _sheetButton('Low right')),
          ),
        ],
      ),
    );
  }
}
