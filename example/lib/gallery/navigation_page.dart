import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// A small mail app on the measured navigation stack: a large-title list
/// whose bar buttons morph into the detail screen's on a push, a toolbar
/// that swaps its item sets, the soft or hard scroll edge effect, and a
/// row of photos that zoom into their pages (drag a photo page down or to
/// the right to zoom it back).
class NavigationDemoPage extends StatefulWidget {
  /// Creates the page.
  const NavigationDemoPage({super.key});

  @override
  State<NavigationDemoPage> createState() => _NavigationDemoPageState();
}

class _NavigationDemoPageState extends State<NavigationDemoPage> {
  MorphScrollEdgeEffectStyle _edge = MorphScrollEdgeEffectStyle.hard;
  int _set = 0;

  void _swapSet() => setState(() => _set = (_set + 1) % 3);

  void _setEdge(MorphScrollEdgeEffectStyle edge) =>
      setState(() => _edge = edge);

  @override
  Widget build(BuildContext context) {
    final close = Navigator.of(context);
    return Material(
      type: MaterialType.transparency,
      child: _DemoScope(
        state: this,
        child: MorphScope(
          child: MorphNavigationStack(home: _Inbox(onClose: close.maybePop)),
        ),
      ),
    );
  }
}

class _DemoScope extends InheritedWidget {
  const _DemoScope({required this.state, required super.child});

  final _NavigationDemoPageState state;

  static _NavigationDemoPageState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DemoScope>()!.state;

  @override
  bool updateShouldNotify(_DemoScope oldWidget) => true;
}

const _palette = [
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF30B0C7),
  Color(0xFF007AFF),
  Color(0xFF5856D6),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
];

MorphBarButton _icon(String id, IconData icon, VoidCallback? onPressed) =>
    MorphBarButton(
      id: id,
      icon: Icon(icon),
      semanticLabel: id,
      onPressed: onPressed,
    );

class _Inbox extends StatelessWidget {
  const _Inbox({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final state = _DemoScope.of(context);
    final swap = state._swapSet;
    final sets = <(List<MorphBarButtonGroup>, List<MorphBarButtonGroup>)>[
      (
        [
          MorphBarButtonGroup([
            MorphBarButton(id: 'filter', label: 'Filter', onPressed: swap),
          ], id: 'tbL'),
        ],
        [
          MorphBarButtonGroup([
            _icon('compose', Icons.edit_square, swap),
          ], id: 'tbR'),
        ],
      ),
      (
        [
          MorphBarButtonGroup([
            _icon('trash', Icons.delete_outline, swap),
            _icon('folder', Icons.folder_outlined, swap),
          ], id: 'tbL'),
        ],
        [
          MorphBarButtonGroup([
            _icon('reply', Icons.reply, swap),
            _icon('compose', Icons.edit_square, swap),
          ], id: 'tbR'),
        ],
      ),
      (
        [
          MorphBarButtonGroup([
            _icon('trash', Icons.delete_outline, swap),
          ], id: 'tbL'),
          MorphBarButtonGroup([
            _icon('folder', Icons.folder_outlined, swap),
          ], id: 'tbM'),
        ],
        [
          MorphBarButtonGroup([
            _icon('compose', Icons.edit_square, swap),
          ], id: 'tbR'),
        ],
      ),
    ];
    final (toolbarLeading, toolbarTrailing) = sets[state._set];
    return MorphNavigationScaffold(
      title: 'Inbox',
      largeTitle: true,
      edgeEffect: state._edge,
      leading: MorphBarButtonGroup([
        MorphBarButton(id: 'close', label: 'Close', onPressed: onClose),
      ]),
      trailing: [
        MorphBarButtonGroup([
          _icon('add', Icons.add, GalleryGlassScope.enabled(context, () {})),
          _icon(
            'more',
            Icons.more_horiz,
            GalleryGlassScope.enabled(context, () {}),
          ),
        ]),
      ],
      toolbarLeading: toolbarLeading,
      toolbarTrailing: toolbarTrailing,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                const SlowMotionToggle(),
                const SizedBox(width: 12),
                Expanded(
                  child: MorphSegmentedControl(
                    segments: const ['Hard edge', 'Soft edge'],
                    selected: state._edge == MorphScrollEdgeEffectStyle.hard
                        ? 0
                        : 1,
                    onChanged: (i) => state._setEdge(
                      i == 0
                          ? MorphScrollEdgeEffectStyle.hard
                          : MorphScrollEdgeEffectStyle.soft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _Photos()),
        SliverList.builder(
          itemCount: 60,
          itemBuilder: (BuildContext context, int i) => _Row(index: i),
        ),
      ],
    );
  }
}

class _Photos extends StatelessWidget {
  const _Photos();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onTap: () => pushMorphZoom<void>(
                  context,
                  from: 'photo-$i',
                  builder: (_) => _Photo(index: i),
                ),
                child: MorphTag(
                  id: 'photo-$i',
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _palette[(i * 2 + 1) % _palette.length],
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Center(
                      child: Icon(Icons.photo, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final color = _palette[(index * 2 + 1) % _palette.length];
    return MorphNavigationScaffold(
      title: 'Photo ${index + 1}',
      backgroundColor: color,
      edgeEffect: null,
      slivers: const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Icon(Icons.photo, color: Colors.white, size: 120),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final color = _palette[index % _palette.length];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MorphNavigationRoute<void>(builder: (_) => _Detail(index: index))),
      child: Container(
        height: 72,
        color: color.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          'Message $index',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatefulWidget {
  const _Detail({required this.index});

  final int index;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final demo = _DemoScope.of(context);
    return MorphNavigationScaffold(
      title: 'Message ${widget.index}',
      edgeEffect: demo._edge,
      trailing: [
        MorphBarButtonGroup([
          _icon(
            _liked ? 'unlike' : 'like',
            _liked ? Icons.favorite : Icons.favorite_border,
            () => setState(() => _liked = !_liked),
          ),
          _icon('share', Icons.ios_share, () {}),
        ]),
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'done',
            label: 'Done',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ], prominent: true),
      ],
      toolbarLeading: [
        MorphBarButtonGroup([
          _icon(
            'up',
            Icons.keyboard_arrow_up,
            GalleryGlassScope.enabled(context, () {}),
          ),
          _icon(
            'down',
            Icons.keyboard_arrow_down,
            GalleryGlassScope.enabled(context, () {}),
          ),
        ], id: 'tbL'),
      ],
      toolbarTrailing: [
        MorphBarButtonGroup([_icon('reply', Icons.reply, () {})], id: 'tbR'),
      ],
      slivers: [
        SliverList.builder(
          itemCount: 40,
          itemBuilder: (BuildContext context, int i) => Container(
            height: 44,
            color: _palette[(i * 3 + widget.index) % _palette.length],
          ),
        ),
      ],
    );
  }
}
