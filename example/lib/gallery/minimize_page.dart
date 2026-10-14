import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// A tab bar that minimizes while the content scrolls, with a mini player
/// in its bottom accessory (UIKit `tabBarMinimizeBehavior`,
/// `bottomAccessory`).
///
/// Page options add the automatic behavior, which does not minimize on an
/// iPhone, and switch the bar from the [MorphContentScrollScope] around
/// the page to a [MorphContentScroll] it is handed directly.
class MinimizeTabBarPage extends StatefulWidget {
  /// Creates the page.
  const MinimizeTabBarPage({super.key});

  @override
  State<MinimizeTabBarPage> createState() => _MinimizeTabBarPageState();
}

class _MinimizeTabBarPageState extends State<MinimizeTabBarPage> {
  int _selected = 0;
  MorphTabBarMinimizeBehavior _behavior = .onScrollDown;
  bool _directScroll = false;
  final MorphContentScroll _scroll = MorphContentScroll();
  bool _accessory = true;
  bool _playing = false;
  bool _search = false;
  bool _searching = false;

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const .only(bottom: 12),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            MorphSwitch(value: value, onChanged: onChanged),
          ],
        ),
      );

  /// The behaviors of the segmented control on the page, in order.
  static const _behaviors = [
    MorphTabBarMinimizeBehavior.onScrollDown,
    MorphTabBarMinimizeBehavior.onScrollUp,
    MorphTabBarMinimizeBehavior.never,
  ];

  static const _items = [
    MorphTabItem(icon: Icons.home_rounded, label: 'Home'),
    MorphTabItem(icon: Icons.grid_view_rounded, label: 'New'),
    MorphTabItem(icon: Icons.radio_rounded, label: 'Radio'),
    MorphTabItem(icon: Icons.library_music_rounded, label: 'Library'),
  ];

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('Minimizing'),
      footer: const Text(
        'Automatic does not minimize on an iPhone. The scroll source is '
        'the MorphContentScrollScope around the page, or a '
        'MorphContentScroll fed by a listener and handed to the bar.',
      ),
      children: [
        GalleryChoice<MorphTabBarMinimizeBehavior>(
          label: 'Behavior',
          options: const {
            MorphTabBarMinimizeBehavior.automatic: 'Auto',
            MorphTabBarMinimizeBehavior.onScrollDown: 'Down',
            MorphTabBarMinimizeBehavior.onScrollUp: 'Up',
            MorphTabBarMinimizeBehavior.never: 'Never',
          },
          value: _behavior,
          onChanged: (v) => setState(() => _behavior = v),
        ),
        GalleryChoice<bool>(
          label: 'Scroll',
          options: const {false: 'Scope', true: 'Direct'},
          value: _directScroll,
          onChanged: (v) => setState(() => _directScroll = v),
        ),
      ],
    ),
  ];

  Widget _player() => _MiniPlayer(
    playing: _playing,
    onPlay: () => setState(() => _playing = !_playing),
  );

  @override
  Widget build(BuildContext context) {
    return MorphContentScrollScope(
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _directScroll ? _scroll.handle : null,
            child: GalleryPage(
              title: 'Tab bar minimize',
              options: _options,
              slivers: [
                SliverPadding(
                  padding: const .fromLTRB(16, 8, 16, 200),
                  sliver: SliverList.builder(
                    itemCount: 60,
                    itemBuilder: (BuildContext context, int i) {
                      if (i == 0) {
                        return Padding(
                          padding: const .only(bottom: 12),
                          child: MorphSegmentedControl(
                            segments: const [
                              MorphSegment('Scroll down'),
                              MorphSegment('Scroll up'),
                              MorphSegment('Never'),
                            ],
                            selectedIndex: switch (_behaviors.indexOf(
                              _behavior,
                            )) {
                              < 0 => null,
                              final i => i,
                            },
                            onChanged: (int v) =>
                                setState(() => _behavior = _behaviors[v]),
                          ),
                        );
                      }
                      if (i == 1) {
                        return _toggle(
                          'Bottom accessory',
                          _accessory,
                          (bool v) => setState(() => _accessory = v),
                        );
                      }
                      if (i == 2) {
                        return _toggle(
                          'Search tab',
                          _search,
                          (bool v) => setState(() {
                            _search = v;
                            _searching = false;
                          }),
                        );
                      }
                      return Container(
                        height: 64,
                        margin: const .only(bottom: 8),
                        decoration: BoxDecoration(
                          color: HSLColor.fromAHSL(
                            1,
                            (i * 29) % 360,
                            0.5,
                            0.6,
                          ).toColor(),
                          borderRadius: .circular(14),
                        ),
                        alignment: .centerLeft,
                        padding: const .symmetric(horizontal: 16),
                        child: Text(
                          '${_items[_selected].label} row $i',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_search)
            Positioned.fill(
              child: MorphSearchTabBar(
                items: _items.take(3).toList(),
                selected: _selected.clamp(0, 2),
                onChanged: GalleryGlassScope.enabled(
                  context,
                  (int i) => setState(() => _selected = i),
                ),
                active: _searching,
                onActiveChanged: (bool on) => setState(() => _searching = on),
                minimizeBehavior: _behavior,
                bottomAccessory: _accessory ? _player() : null,
                contentScroll: _directScroll ? _scroll : null,
              ),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 21,
              child: MorphTabBar(
                items: _items,
                selected: _selected,
                onChanged: GalleryGlassScope.enabled(
                  context,
                  (int i) => setState(() => _selected = i),
                ),
                minimizeBehavior: _behavior,
                bottomAccessory: _accessory ? _player() : null,
                contentScroll: _directScroll ? _scroll : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// A mini player that drops its secondary control inline.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.playing, required this.onPlay});

  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final inline =
        MorphTabAccessoryEnvironment.of(context) ==
        MorphTabAccessoryEnvironment.inline;
    return Padding(
      padding: const .symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.deepOrange,
              borderRadius: .circular(6),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Liquid Afternoon',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlay,
            child: Padding(
              padding: const .all(6),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
          if (!inline)
            const Padding(
              padding: .all(6),
              child: Icon(Icons.fast_forward_rounded),
            ),
        ],
      ),
    );
  }
}
