import 'package:flutter/widgets.dart';
import 'package:morph/morph.dart';

/// Public-API consumer examples for Sonatide; run with -t lib/consumer_api.dart.
void main() => runApp(
  WidgetsApp(
    color: const Color(0xFF007AFF),
    builder: (context, child) => MorphTheme(
      data: const MorphThemeData(
        glass: MorphGlassRenderer.adaptive(),
        fontFamily: 'SourceCodePro',
      ),
      child: child!,
    ),
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    ),
    home: const ConsumerApiExamples(),
  ),
);

/// Reactions, a color selector, app touch targets and menus over a custom shell.
class ConsumerApiExamples extends StatefulWidget {
  /// Creates the consumer example.
  const ConsumerApiExamples({super.key});

  @override
  State<ConsumerApiExamples> createState() => _ConsumerApiExamplesState();
}

class _ConsumerApiExamplesState extends State<ConsumerApiExamples> {
  final _choice = MorphMenuPresentationController();
  final _contextMenu = MorphMenuPresentationController();
  final _hint = OverlayPortalController();
  final _glyph = GlobalKey();
  int? _reaction;
  int _vibe = 1;
  int? _preview;
  int _tab = 0;
  String _sort = 'Recent';
  bool _archived = false;
  static const _colors = [
    Color(0xFF427AFF),
    Color(0xFF8B5CF6),
    Color(0xFFFF7295),
  ];
  static const _vibes = [
    'Calm / Спокойно',
    'Dream / Мечтательно',
    'Joy / Радостно',
  ];

  @override
  void dispose() {
    _choice.dispose();
    _contextMenu.dispose();
    super.dispose();
  }

  Widget _replica(
    BuildContext context, {
    required bool selected,
    required bool minimized,
  }) => Text(
    selected ? '♫' : '♪',
    style: TextStyle(color: IconTheme.of(context).color),
  );

  @override
  Widget build(BuildContext context) => MorphPresentationBoundary(
    child: Stack(
      children: [
        Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (context, animation, secondaryAnimation) => ColoredBox(
              color: const Color(0xFFF2F2F7),
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 17, color: Color(0xFF111111)),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 64, 24, 140),
                  children: [
                    const Text('ReactionPanel'),
                    MorphSegmentedControl(
                      segments: [
                        for (final reaction in ['♡', '♫', '☆'])
                          MorphSegment.custom(
                            semanticLabel: reaction,
                            child: Text(reaction),
                            builder: (context, state, child) => Opacity(
                              opacity: state.active || state.selected ? 1 : 0.6,
                              child: child,
                            ),
                          ),
                      ],
                      selectedIndex: _reaction,
                      onChanged: null,
                      onActivated: (index) => setState(
                        () => _reaction = _reaction == index ? null : index,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(_vibes[_preview ?? _vibe]),
                    MorphSegmentedControl(
                      segments: [
                        for (final vibe in _vibes)
                          MorphSegment.custom(
                            semanticLabel: vibe,
                            child: const SizedBox(),
                          ),
                      ],
                      selectedIndex: _vibe,
                      onChanged: (index) => setState(() => _vibe = index),
                      onPreviewChanged: (index) =>
                          setState(() => _preview = index),
                      track: const DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: StadiumBorder(),
                          gradient: LinearGradient(colors: _colors),
                        ),
                      ),
                      lensColorAt: (position) {
                        final before = position.floor().clamp(
                          0,
                          _colors.length - 1,
                        );
                        final after = (before + 1).clamp(0, _colors.length - 1);
                        return Color.lerp(
                          _colors[before],
                          _colors[after],
                          position - before,
                        )!;
                      },
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: MorphTouchTarget(
                        semanticLabel: 'Like',
                        onTap: () => setState(
                          () => _reaction = _reaction == 0 ? null : 0,
                        ),
                        child: const MorphTouchFeedback(
                          shape: BeveledRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          child: SizedBox(
                            width: 40,
                            height: 32,
                            child: Center(child: Text('♡')),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    MorphMenuSource(
                      controller: _choice,
                      semanticLabel: 'Sort',
                      menuBuilder: (context) => [
                        for (final sort in ['Recent', 'Name'])
                          MorphMenuItem(
                            title: sort,
                            subtitle: sort == 'Recent'
                                ? 'Newest first'
                                : 'Alphabetically',
                            state: _sort == sort ? .on : .off,
                            onSelected: () => setState(() => _sort = sort),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Sort: $_sort'),
                      ),
                    ),
                    if (!_archived)
                      MorphContextMenuRegion(
                        controller: _contextMenu,
                        menuBuilder: (context) => [
                          MorphMenuItem(
                            title: 'Archive',
                            onSelected: () => setState(() => _archived = true),
                          ),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Hold to archive'),
                        ),
                      ),
                    MorphTouchTarget(
                      semanticLabel: 'Open context menu',
                      onTap: _archived ? null : _contextMenu.open,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Open menu'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 21,
          child: Center(
            child: MorphTabBar(
              items: [
                MorphTabItem.custom(
                  label: 'Inbox / Письма',
                  semanticValue: '3 unread messages',
                  badge: const MorphBadge.count(3),
                  glyph: OverlayPortal(
                    key: _glyph,
                    controller: _hint,
                    overlayChildBuilder: (context) => const Positioned(
                      bottom: 100,
                      left: 24,
                      child: Text('⌘1'),
                    ),
                    child: const Text('♪'),
                  ),
                  replicaBuilder: _replica,
                ),
                const MorphTabItem(icon: IconData(0xe8b6), label: 'Search'),
              ],
              selected: _tab,
              onChanged: (index) => setState(() => _tab = index),
            ),
          ),
        ),
      ],
    ),
  );
}
