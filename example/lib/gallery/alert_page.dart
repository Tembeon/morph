import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Alerts and action sheets the way iOS 27 presents them: alerts with a
/// row or a column of buttons, a text field and a preferred action, and
/// action sheets that grow out of the button that summoned them, or show
/// as an alert when nothing summoned them.
///
/// Text fields show their options: an action that waits for text, a
/// password, capitalized words and digits only. The page options drop the
/// messages and the action sheet's title.
class AlertPage extends StatefulWidget {
  /// Creates the page.
  const AlertPage({super.key});

  @override
  State<AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<AlertPage> {
  String _last = 'Show an alert or an action sheet';
  bool _messages = true;
  bool _sheetTitle = true;

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
      'disabled' => (
        'Disabled actions',
        'A disabled action keeps its fill and dims its title.',
        [
          MorphAlertAction(title: 'Enabled', onPressed: () => _said('Enabled')),
          const MorphAlertAction(title: 'Disabled', enabled: false),
          const MorphAlertAction(
            title: 'Delete',
            style: .destructive,
            enabled: false,
          ),
          MorphAlertAction(
            title: 'Cancel',
            style: .cancel,
            onPressed: () => _said('Cancel chosen'),
          ),
        ],
      ),
      'disabledPreferred' => (
        'Name the album',
        'A disabled preferred action loses its accent fill.',
        [
          MorphAlertAction(
            title: 'Cancel',
            style: .cancel,
            onPressed: () => _said('Cancel chosen'),
          ),
          const MorphAlertAction(
            title: 'OK',
            isPreferred: true,
            enabled: false,
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
      message: _messages ? message : null,
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

  Future<void> _waitsForText() async {
    final ready = ValueNotifier(false);
    final controller = TextEditingController();
    final chosen = await showMorphAlert(
      context,
      title: 'New playlist',
      message: _messages ? 'OK stays off until the name has text.' : null,
      textFields: [
        MorphAlertTextField(
          placeholder: 'Playlist name',
          controller: controller,
          textCapitalization: .sentences,
          onChanged: (String text) => ready.value = text.trim().isNotEmpty,
        ),
      ],
      actions: [
        MorphAlertAction(
          title: 'Cancel',
          style: .cancel,
          onPressed: () => _said('Cancel chosen'),
        ),
        MorphAlertAction(
          title: 'OK',
          isPreferred: true,
          enabledListenable: ready,
        ),
      ],
    );
    if (chosen?.title == 'OK') _said('Created ${controller.text}');
    controller.dispose();
    ready.dispose();
  }

  Future<void> _password() async {
    final controller = TextEditingController();
    final chosen = await showMorphAlert(
      context,
      title: 'Wi-Fi password',
      message: _messages ? 'Enter the password for the network.' : null,
      textFields: [
        MorphAlertTextField(
          placeholder: 'Password',
          controller: controller,
          obscureText: true,
          keyboardType: .visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          semanticLabel: 'Password',
        ),
      ],
      actions: [
        ..._actions(const [('Cancel', .cancel)]),
        const MorphAlertAction(title: 'Join'),
      ],
    );
    if (chosen?.title == 'Join') {
      _said('Joined with ${controller.text.length} characters');
    }
    controller.dispose();
  }

  Future<void> _formatted() async {
    final name = TextEditingController();
    final zip = TextEditingController();
    final chosen = await showMorphAlert(
      context,
      title: 'Shipping',
      message: _messages
          ? 'Words start capitalized; the ZIP takes '
                'five digits.'
          : null,
      textFields: [
        MorphAlertTextField(
          placeholder: 'Full name',
          controller: name,
          textCapitalization: .words,
          keyboardType: .name,
        ),
        MorphAlertTextField(
          placeholder: 'ZIP code',
          controller: zip,
          keyboardType: .number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
        ),
      ],
      actions: [
        ..._actions(const [('Cancel', .cancel)]),
        const MorphAlertAction(title: 'Save'),
      ],
    );
    if (chosen?.title == 'Save') _said('Ships to ${name.text}, ${zip.text}');
    name.dispose();
    zip.dispose();
  }

  Future<void> _sheet(
    BuildContext anchor, {
    bool anchored = true,
    Rect? anchorRect,
  }) async {
    await showMorphActionSheet(
      context,
      anchor: anchored && anchorRect == null ? anchor : null,
      anchorRect: anchorRect,
      title: _sheetTitle ? 'Share photo' : null,
      message: _messages ? 'Choose where it goes.' : null,
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
    child: MorphGlassButton(
      onPressed: GalleryGlassScope.enabled(context, onTap),
      child: Text(label),
    ),
  );

  Widget _pointSource(BuildContext context) {
    final enabled = !GalleryGlassScope.of(context, .disabled).disabled;
    return GestureDetector(
      behavior: .opaque,
      onTapUp: enabled
          ? (TapUpDetails d) => _sheet(
              context,
              anchorRect: Rect.fromCenter(
                center: d.globalPosition,
                width: 2,
                height: 2,
              ),
            )
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: galleryCardColor(context),
          borderRadius: const .all(.circular(MorphListMetrics.cornerRadius)),
        ),
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              'Tap anywhere here: an action sheet from that point',
              textAlign: .center,
              style: TextStyle(color: gallerySecondaryColor(context)),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Content'),
      children: [
        GalleryToggle(
          label: 'Messages',
          value: _messages,
          onChanged: (bool v) => setState(() => _messages = v),
        ),
        GalleryToggle(
          label: 'Action sheet title',
          value: _sheetTitle,
          onChanged: (bool v) => setState(() => _sheetTitle = v),
        ),
      ],
    ),
  ];

  Widget _sheetButton(String label, {bool anchored = true}) => Builder(
    builder: (BuildContext anchor) =>
        _button(label, () => _sheet(anchor, anchored: anchored)),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GalleryPage(
          title: 'Alerts',
          options: _options,
          slivers: [
            SliverPadding(
              padding: const .fromLTRB(20, 20, 20, 120),
              sliver: SliverList.list(
                children: [
                  Text(
                    _last,
                    style: TextStyle(color: gallerySecondaryColor(context)),
                  ),
                  const SizedBox(height: 16),
                  MorphGlassContainer(
                    solidBackdrop: MorphListAppearance.resolve(
                      context,
                      null,
                    ).backgroundColor,
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        for (final (label, name, field) in const [
                          ('Two buttons in a row', 'two', false),
                          (
                            'Three buttons, destructive, cancel last',
                            'three',
                            false,
                          ),
                          ('A preferred action', 'preferred', false),
                          ('A text field', 'field', true),
                          ('Disabled actions', 'disabled', false),
                          (
                            'A disabled preferred action',
                            'disabledPreferred',
                            false,
                          ),
                        ])
                          Padding(
                            padding: const .only(bottom: 12),
                            child: _button(
                              label,
                              () => _alert(name, field: field),
                            ),
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
                  ),
                  const GalleryCaption('Text fields'),
                  MorphGlassContainer(
                    solidBackdrop: MorphListAppearance.resolve(
                      context,
                      null,
                    ).backgroundColor,
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        for (final (label, show) in [
                          ('OK waits for text', _waitsForText),
                          ('A password field', _password),
                          ('Capitalized words, digits only', _formatted),
                        ])
                          Padding(
                            padding: const .only(bottom: 12),
                            child: _button(label, show),
                          ),
                      ],
                    ),
                  ),
                  const GalleryCaption('Action sheet from a rect'),
                  Builder(builder: _pointSource),
                ],
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
    );
  }
}
