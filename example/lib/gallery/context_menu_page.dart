import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Long-press context menus: list rows and photo tiles lift under the
/// finger, then open into a card of action rows next to the lifted hero; a
/// tap still reaches the row.
class ContextMenuPage extends StatefulWidget {
  /// Creates the page.
  const ContextMenuPage({super.key});

  @override
  State<ContextMenuPage> createState() => _ContextMenuPageState();
}

class _ContextMenuPageState extends State<ContextMenuPage> {
  String _last = 'Hold a row or a photo';

  static const _rows = [
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

  static const _actions = [
    ('Reply', Icons.reply, false),
    ('Copy', Icons.copy, false),
    ('Pin', Icons.push_pin_outlined, false),
    ('Share', Icons.ios_share, false),
    ('Delete', Icons.delete_outline, true),
  ];

  MorphSatellite _menu(String subject) => MorphSatellite(
    height: _actions.length * _ContextActions.rowHeight + 20,
    builder: (BuildContext context, MorphFlight flight) => _ContextActions(
      actions: [
        for (final (title, icon, destructive) in _actions)
          (
            title: title,
            icon: icon,
            destructive: destructive,
            onTap: () {
              setState(() => _last = '$title: $subject');
              flight.close();
            },
          ),
      ],
    ),
  );

  Widget _row(BuildContext context, (String, String, Color) row) {
    final (name, text, color) = row;
    final list = MorphListAppearance.resolve(context, null);
    return Padding(
      padding: const .only(bottom: 8),
      child: MorphContextMenuRegion(
        below: _menu(name),
        semanticLabel: name,
        child: GestureDetector(
          onTap: () => setState(() => _last = 'Opened $name'),
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

  @override
  Widget build(BuildContext context) {
    return GalleryPage(
      title: 'Context menu',
      slivers: [
        SliverPadding(
          padding: const .fromLTRB(16, 0, 16, 32),
          sliver: SliverList.list(
            children: [
              GalleryCaption(_last),
              for (final row in _rows) _row(context, row),
              const GalleryCaption('Photos'),
              Row(
                children: [
                  for (var i = 0; i < _photos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: MorphContextMenuRegion(
                        alignment: AlignmentDirectional.center,
                        below: _menu('Photo ${i + 1}'),
                        semanticLabel: 'Photo ${i + 1}',
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

typedef _Action = ({
  String title,
  IconData icon,
  bool destructive,
  VoidCallback onTap,
});

/// The action rows of a context menu on one glass card.
class _ContextActions extends StatelessWidget {
  const _ContextActions({required this.actions});

  final List<_Action> actions;

  static const double rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final style = MorphMenuAppearance.resolve(context, null);
    return MorphGlassEffect(
      shape: RoundedRectangleBorder(
        borderRadius: .all(.circular(MorphMenuTuning.standard.cornerRadius)),
      ),
      child: Padding(
        padding: const .symmetric(vertical: 10),
        child: Column(
          mainAxisSize: .min,
          children: [
            for (final action in actions)
              GestureDetector(
                behavior: .opaque,
                onTap: action.onTap,
                child: SizedBox(
                  height: rowHeight,
                  child: Padding(
                    padding: const .symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action.title,
                            style: style.textStyle.copyWith(
                              color: action.destructive
                                  ? style.destructiveColor
                                  : null,
                            ),
                          ),
                        ),
                        Icon(
                          action.icon,
                          size: 20,
                          color: action.destructive
                              ? style.destructiveColor
                              : style.iconColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
