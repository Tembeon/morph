import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/ui/goo_selector.dart';

/// The pages scene: a music library where every album card opens into
/// the full player. One toggle changes WHAT the player is - an overlay
/// flight or a real Navigator route - while everything else stays
/// identical, so the difference between the two is the thing you see:
/// only the route can stack another page on top (Lyrics), answer the
/// back gesture, and live as history. The cover travels either way
/// (MorphSharedElement), and the open card follows the finger 1:1 on
/// the flight's displacement channel - release past the threshold and
/// it flies home out of the hand.
class PageScene extends StatefulWidget {
  /// Creates the chapter scene.
  const PageScene({super.key, required this.motion});

  /// Motion profile of the flights.
  final MorphMotion motion;

  @override
  State<PageScene> createState() => _PageSceneState();
}

class _Album {
  const _Album(this.title, this.artist, this.colors);

  final String title;
  final String artist;
  final List<Color> colors;
}

class _PageSceneState extends State<PageScene> {
  static const List<_Album> _albums = <_Album>[
    _Album('Night Drive', 'Neon Waves', <Color>[
      Color(0xFF7C5CFF),
      Color(0xFFB84CC5),
      Color(0xFFFF7A59),
    ]),
    _Album('Glasswork', 'Cold Cities', <Color>[
      Color(0xFF4C8FC5),
      Color(0xFF4CC5B8),
    ]),
    _Album('Low Sun', 'Field Notes', <Color>[
      Color(0xFFC5A84C),
      Color(0xFFC55C4C),
    ]),
    _Album('Afterglow', 'Slow Parade', <Color>[
      Color(0xFF8FC54C),
      Color(0xFF4CC57A),
    ]),
  ];

  static const MorphSurfaceSpec _panelSpec = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(26))),
    color: Color(0xFF1C1730),
    elevation: 24,
  );

  bool _asRoute = false;

  void _open(BuildContext context, int index) {
    final _Album album = _albums[index];
    final MorphTargetSpec target = MorphTargetSpec.dialog(
      width: 306,
      height: 520,
      surface: _panelSpec,
    );
    if (_asRoute) {
      showMorphRoute<void>(
        context,
        motion: widget.motion,
        semanticLabel: album.title,
        target: target,
        builder: (BuildContext context, MorphFlight flight) =>
            _PlayerBody(album: album, index: index, flight: flight, page: true),
      );
    } else {
      showMorph(
        context,
        motion: widget.motion,
        semanticLabel: album.title,
        target: target,
        builder: (BuildContext context, MorphFlight flight) => _PlayerBody(
          album: album,
          index: index,
          flight: flight,
          page: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          PanelSection(
            label: 'OPEN AS',
            child: GooSelector(
              labels: const <String>['Overlay', 'Real route'],
              index: _asRoute ? 1 : 0,
              onSelect: (int i) => setState(() => _asRoute = i == 1),
            ),
          ),
          PanelHint(
            _asRoute
                ? 'A real page in the phone\'s Navigator: Lyrics stacks on '
                      'top, back pops it, the flight is only the '
                      'transition. At settle the live subtree reparents '
                      'from the shuttle into the route - the one '
                      'sanctioned GlobalKey move.'
                : 'An overlay flight: lighter, no Navigator involved - '
                      'and nothing can stack on it, which is exactly why '
                      'Lyrics is locked. Drag the open card down and let '
                      'go: it flies home out of the hand.',
          ),
        ],
      ),
      phone: PhoneFrame(
        app: (BuildContext context) =>
            _LibraryApp(albums: _albums, onOpen: _open),
      ),
    );
  }
}

/// The library mockup: album grid plus the mini player bar.
class _LibraryApp extends StatelessWidget {
  const _LibraryApp({required this.albums, required this.onOpen});

  final List<_Album> albums;
  final void Function(BuildContext context, int index) onOpen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            const Padding(
              padding: .fromLTRB(20, 12, 20, 12),
              child: Text(
                'Library',
                style: TextStyle(fontSize: 24, fontWeight: .w800),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const .fromLTRB(16, 0, 16, 92),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: albums.length,
                itemBuilder: (BuildContext context, int index) => _AlbumCard(
                  album: albums[index],
                  index: index,
                  onOpen: onOpen,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: _MiniBar(album: albums[0], onOpen: onOpen),
        ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.index,
    required this.onOpen,
  });

  final _Album album;
  final int index;
  final void Function(BuildContext context, int index) onOpen;

  @override
  Widget build(BuildContext context) {
    return MorphTag(
      id: 'album-$index',
      spec: const MorphSurfaceSpec(
        shape: RoundedRectangleBorder(borderRadius: .all(.circular(18))),
        color: Color(0xFF241F35),
        elevation: 3,
      ),
      child: MorphSurface(
        onTap: (BuildContext context) => onOpen(context, index),
        child: Padding(
          padding: const .all(10),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Expanded(
                child: MorphSharedElement(
                  id: 'cover-$index',
                  fade: .none,
                  child: _Cover(colors: album.colors, radius: 12, iconSize: 32),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                style: const TextStyle(fontSize: 12.5, fontWeight: .w700),
              ),
              Text(
                album.artist,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.album, required this.onOpen});

  final _Album album;
  final void Function(BuildContext context, int index) onOpen;

  @override
  Widget build(BuildContext context) {
    return MorphTag(
      id: 'album-bar',
      spec: const MorphSurfaceSpec(
        shape: StadiumBorder(),
        color: Color(0xFF241F35),
        elevation: 6,
      ),
      child: MorphSurface(
        onTap: (BuildContext context) => onOpen(context, 0),
        child: Padding(
          padding: const .fromLTRB(8, 8, 16, 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 36,
                height: 36,
                child: _Cover(colors: album.colors, radius: 18, iconSize: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      album.title,
                      style: const TextStyle(fontSize: 12, fontWeight: .w600),
                    ),
                    Text(
                      album.artist,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.pause_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full player, identical in both modes except for what the mode
/// makes possible: [page] unlocks the Lyrics push.
class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.album,
    required this.index,
    required this.flight,
    required this.page,
  });

  final _Album album;
  final int index;
  final MorphFlight flight;
  final bool page;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .translucent,
      onPanStart: (DragStartDetails details) => flight.beginDrag(),
      onPanUpdate: (DragUpdateDetails details) => flight.dragBy(details.delta),
      onPanEnd: (DragEndDetails details) =>
          flight.endDrag(details.velocity.pixelsPerSecond),
      onPanCancel: () => flight.endDrag(.zero),
      child: Padding(
        padding: const .fromLTRB(24, 24, 24, 18),
        child: Column(
          children: <Widget>[
            MorphSharedElement(
              id: 'cover-$index',
              fade: .none,
              child: _Cover(colors: album.colors, radius: 20, size: 190),
            ),
            const SizedBox(height: 18),
            MorphReveal(
              from: 0.4,
              to: 0.8,
              child: Column(
                children: <Widget>[
                  Text(
                    album.title,
                    style: const TextStyle(fontSize: 19, fontWeight: .w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${album.artist} - Midnight City',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MorphReveal(
              from: 0.5,
              to: 0.9,
              child: Column(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: .circular(3),
                    child: LinearProgressIndicator(
                      value: 0.37,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: .spaceEvenly,
                    children: <Widget>[
                      const Icon(Icons.skip_previous_rounded, size: 30),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        child: IconButton(
                          onPressed: flight.close,
                          icon: const Icon(Icons.pause_rounded, size: 26),
                        ),
                      ),
                      const Icon(Icons.skip_next_rounded, size: 30),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            MorphReveal(from: 0.55, to: 1, child: _lyricsTile(context)),
          ],
        ),
      ),
    );
  }

  Widget _lyricsTile(BuildContext context) {
    return SpringButton(
      onPressed: !page
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => _LyricsPage(album: album),
              ),
            ),
      child: Container(
        padding: const .symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: .circular(14),
          color: Colors.white.withValues(alpha: page ? 0.07 : 0.03),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              page ? Icons.lyrics_rounded : Icons.lock_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: page ? 0.85 : 0.3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                page ? 'Lyrics' : 'Lyrics - needs a real route',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: .w600,
                  color: Colors.white.withValues(alpha: page ? 0.85 : 0.35),
                ),
              ),
            ),
            if (page)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

/// A page stacked ON TOP of the morph route inside the phone - the
/// proof that the player is real history, not an overlay.
class _LyricsPage extends StatelessWidget {
  const _LyricsPage({required this.album});

  final _Album album;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15121F),
      body: Padding(
        padding: const .fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SpringButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const .all(7),
                    decoration: ShapeDecoration(
                      shape: const CircleBorder(),
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${album.title} - lyrics',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: .w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (int i = 0; i < 9; i++)
                    Padding(
                      padding: const .only(bottom: 12),
                      child: Container(
                        height: 12,
                        width: 120.0 + (i * 47) % 140,
                        decoration: BoxDecoration(
                          borderRadius: .circular(6),
                          color: Colors.white.withValues(
                            alpha: i == 3 ? 0.35 : 0.08,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              'a plain MaterialPageRoute pushed on top of the morph '
              'route - impossible above an overlay',
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The album art: a gradient stand-in so the example stays asset-free.
/// Without an explicit [size] it FILLS whatever box it is given -
/// a Container shrink-wraps its icon otherwise.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.colors,
    required this.radius,
    this.size,
    this.iconSize = 40,
  });

  final List<Color> colors;
  final double radius;
  final double? size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size ?? .infinity,
      height: size ?? .infinity,
      decoration: BoxDecoration(
        borderRadius: .circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: iconSize,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }
}
