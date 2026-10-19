import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/knobs.dart';

/// Long-press context menus: list rows and photo tiles lift under the
/// finger, then the measured menu card grows out of them next to the
/// lifted preview; the finger may slide onto a row and choose it on
/// release, and a tap still reaches the row.
class ContextMenuPage extends StatefulWidget {
  /// Creates the page.
  const ContextMenuPage({super.key});

  @override
  State<ContextMenuPage> createState() => _ContextMenuPageState();
}

/// What the menu rows show.
enum _Rows { actions, sections }

class _ContextMenuPageState extends State<ContextMenuPage> {
  String _last = 'Hold a row or a photo';
  _Rows _rows = _Rows.actions;
  bool _accessory = true;
  MorphMenuOrder _order = MorphMenuOrder.automatic;
  bool? _dismissOnSelect;
  bool _pinned = false;
  bool _photoPreview = true;

  static const _people = [
    ('Anna', 'Lunch tomorrow?', Color(0xFF34C759)),
    ('Ben', 'The slides are ready', Color(0xFF007AFF)),
    ('Chloe', 'Photos from the trip', Color(0xFFFF9500)),
    ('Dmitri', 'Call me back', Color(0xFFAF52DE)),
  ];

  static const _photos = [
    Color(0xFFFF3B30),
    Color(0xFF30B0C7),
    Color(0xFF5856D6),
  ];

  static const _reactions = [
    ('Love', Icons.favorite),
    ('Like', Icons.thumb_up),
    ('Laugh', Icons.sentiment_very_satisfied),
    ('Emphasize', Icons.priority_high),
    ('Question', Icons.question_mark),
  ];

  void _picked(String what) => setState(() => _last = what);

  List<MorphMenuEntry> _menu(String subject) => switch (_rows) {
    _Rows.actions => [
      MorphMenuItem(
        title: 'Reply',
        icon: const Icon(Icons.reply),
        onSelected: () => _picked('Reply: $subject'),
      ),
      MorphMenuItem(
        title: 'Copy',
        icon: const Icon(Icons.copy),
        onSelected: () => _picked('Copy: $subject'),
      ),
      MorphMenuItem(
        title: _pinned ? 'Unpin' : 'Pin',
        icon: const Icon(Icons.push_pin_outlined),
        keepsMenuOpen: true,
        onSelected: () => setState(() => _pinned = !_pinned),
      ),
      MorphMenuItem(
        title: 'Delete',
        icon: const Icon(Icons.delete_outline),
        destructive: true,
        onSelected: () => _picked('Delete: $subject'),
      ),
    ],
    _Rows.sections => [
      MorphMenuSection(
        children: [
          MorphMenuItem(
            title: 'Reply',
            icon: const Icon(Icons.reply),
            onSelected: () => _picked('Reply: $subject'),
          ),
          MorphMenuItem(
            title: 'Forward',
            icon: const Icon(Icons.forward),
            onSelected: () => _picked('Forward: $subject'),
          ),
        ],
      ),
      MorphSubmenu(
        title: 'Share',
        icon: const Icon(Icons.ios_share),
        children: [
          for (final app in const ['Messages', 'Mail', 'Notes'])
            MorphMenuItem(
              title: app,
              onSelected: () => _picked('Share to $app: $subject'),
            ),
        ],
      ),
      MorphMenuItem(
        title: 'Delete',
        icon: const Icon(Icons.delete_outline),
        destructive: true,
        onSelected: () => _picked('Delete: $subject'),
      ),
    ],
  };

  MorphSatellite? _capsule(String subject) => !_accessory
      ? null
      : MorphSatellite(
          builder: (BuildContext context) => _Reactions(
            reactions: _reactions,
            onPicked: (String reaction) {
              _picked('$reaction on $subject');
              MorphContextMenuRegion.close(context);
            },
          ),
        );

  Widget _region({
    required String subject,
    required Widget child,
    bool accessory = true,
    WidgetBuilder? preview,
    Size? previewSize,
  }) => MorphContextMenuRegion(
    menu: _menu(subject),
    accessory: accessory ? _capsule(subject) : null,
    preview: preview,
    previewSize: previewSize,
    onPreviewTap: preview == null ? null : () => _picked('Opened $subject'),
    order: _order,
    dismissOnSelect: _dismissOnSelect,
    semanticLabel: subject,
    child: child,
  );

  Widget _row(BuildContext context, (String, String, Color) row) {
    final (name, text, color) = row;
    final list = MorphListAppearance.resolve(context, null);
    return Padding(
      padding: const .only(bottom: 8),
      child: _region(
        subject: name,
        child: GestureDetector(
          onTap: () => _picked('Opened $name'),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: list.cellColor,
              borderRadius: const .all(.circular(14)),
            ),
            child: Padding(
              padding: const .symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color,
                    radius: 18,
                    child: Text(
                      name.substring(0, 1),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          style: TextStyle(
                            color: list.titleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          text,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(color: list.secondaryColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _options(BuildContext context) => [
    GalleryChoice<_Rows>(
      label: 'Rows',
      options: const {_Rows.actions: 'Actions', _Rows.sections: 'Sections'},
      value: _rows,
      onChanged: (_Rows value) => setState(() => _rows = value),
    ),
    GalleryToggle(
      label: 'Reactions accessory',
      value: _accessory,
      onChanged: (bool value) => setState(() => _accessory = value),
    ),
    GalleryToggle(
      label: 'Photo preview',
      value: _photoPreview,
      onChanged: (bool value) => setState(() => _photoPreview = value),
    ),
    GalleryChoice<MorphMenuOrder>(
      label: 'Order',
      options: const {
        MorphMenuOrder.automatic: 'Automatic',
        MorphMenuOrder.priority: 'Priority',
        MorphMenuOrder.fixed: 'Fixed',
      },
      value: _order,
      onChanged: (MorphMenuOrder value) => setState(() => _order = value),
    ),
    GalleryChoice<int>(
      label: 'Dismiss',
      options: const {0: 'Per row', 1: 'Always', 2: 'Never'},
      value: switch (_dismissOnSelect) {
        null => 0,
        true => 1,
        false => 2,
      },
      onChanged: (int value) => setState(
        () => _dismissOnSelect = switch (value) {
          1 => true,
          2 => false,
          _ => null,
        },
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Context menu',
      options: _options,
      slivers: [
        SliverPadding(
          padding: const .fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              GalleryCaption(_last),
              for (final row in _people) _row(context, row),
              const GalleryCaption('Photos'),
              Row(
                children: [
                  for (var i = 0; i < _photos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _region(
                        subject: 'Photo ${i + 1}',
                        accessory: false,
                        preview: !_photoPreview
                            ? null
                            : (BuildContext context) =>
                                  _PhotoPreview(color: _photos[i], index: i),
                        previewSize: const Size(300, 225),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _photos[i],
                              borderRadius: const .all(.circular(12)),
                            ),
                            child: const Center(
                              child: Icon(Icons.photo, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A reactions capsule on glass, the accessory of a message.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.reactions, required this.onPicked});

  final List<(String, IconData)> reactions;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return MorphGlassEffect(
      shape: const StadiumBorder(),
      child: Padding(
        padding: const .symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: .min,
          children: [
            for (final (label, icon) in reactions)
              GestureDetector(
                behavior: .opaque,
                onTap: () => onPicked(label),
                child: Semantics(
                  button: true,
                  label: label,
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(child: Icon(icon, size: 22)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The large picture a photo tile previews, as a photo app's context menu
/// shows the whole picture behind its square thumbnail.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.color, required this.index});

  final Color color;
  final int index;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const .all(.circular(16)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: .min,
          children: [
            const Icon(Icons.photo, color: Colors.white, size: 48),
            Text(
              'Photo ${index + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
          ],
        ),
      ),
    );
  }
}
