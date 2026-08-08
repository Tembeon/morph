import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';

/// A realistic music player: the mini bar morphs into the full player
/// and the album art travels between them (MorphSharedElement) while
/// the controls unfold in a MorphReveal cascade. Also showcases the
/// declare-once surface flow: the bar renders its Material FROM
/// MorphTag.specOf, and the dialog reuses the same app archetype via
/// MorphTargetSpec.surface.
class PlayerExample extends StatelessWidget {
  /// Creates the chapter demo.
  const PlayerExample({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  static const MorphSurfaceSpec _bar = MorphSurfaceSpec(
    shape: StadiumBorder(),
    color: Color(0xFF241F35),
    elevation: 3,
  );
  static const MorphSurfaceSpec _panel = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(28))),
    color: Color(0xFF1C1730),
    elevation: 24,
  );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.82),
      child: MorphTag(
        id: 'gallery-player',
        spec: _bar,
        child: MorphSurface(
          onTap: (BuildContext context) => showMorph(
            context,
            target: MorphTargetSpec.dialog(
              width: 420,
              height: 540,
              surface: _panel,
            ),
            motion: motion,
            builder: (BuildContext context, MorphFlight flight) =>
                _PlayerSheet(flight: flight),
          ),
          child: const Padding(
            padding: .fromLTRB(10, 10, 22, 10),
            child: Row(
              mainAxisSize: .min,
              children: <Widget>[
                MorphSharedElement(
                  id: 'gallery-cover',
                  child: _CoverArt(size: 44, radius: 22),
                ),
                SizedBox(width: 12),
                Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      'Night Drive',
                      style: TextStyle(fontSize: 13, fontWeight: .w600),
                    ),
                    Text(
                      'Neon Waves',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
                SizedBox(width: 18),
                Icon(Icons.pause_rounded, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag-to-dismiss on the flight's displacement channel: the whole
/// dialog - surface, shadow, flying cover - follows the finger 1:1 as
/// one rigid body while the scrim thins and the card recedes slightly.
/// Releasing always springs the card home; past the commit threshold
/// the close flight plays simultaneously, so the card flies back into
/// the mini bar straight out of the hand. The sheet supplies only the
/// gesture; all mechanics live on [MorphFlight].
class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet({required this.flight});

  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final MorphSurfaceSpec spec = MorphTag.specOf(context);
    return GestureDetector(
      behavior: .translucent,
      onPanStart: (DragStartDetails details) => flight.beginDrag(),
      onPanUpdate: (DragUpdateDetails details) => flight.dragBy(details.delta),
      onPanEnd: (DragEndDetails details) =>
          flight.endDrag(details.velocity.pixelsPerSecond),
      onPanCancel: () => flight.endDrag(.zero),
      child: _sheetBody(context, spec),
    );
  }

  Widget _sheetBody(BuildContext context, MorphSurfaceSpec spec) {
    return Padding(
      padding: const .fromLTRB(32, 36, 32, 28),
      child: Column(
        children: <Widget>[
          const MorphSharedElement(
            id: 'gallery-cover',
            child: _CoverArt(size: 240, radius: 24),
          ),
          const SizedBox(height: 26),
          MorphReveal(
            from: 0.4,
            to: 0.8,
            child: Column(
              children: <Widget>[
                const Text(
                  'Night Drive',
                  style: TextStyle(fontSize: 22, fontWeight: .w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Neon Waves - Midnight City',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MorphReveal(
            from: 0.5,
            to: 0.9,
            child: Column(
              children: <Widget>[
                // A fake progress line keeps the sheet self-contained.
                ClipRRect(
                  borderRadius: .circular(3),
                  child: LinearProgressIndicator(
                    value: 0.37,
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: .spaceBetween,
                  children: <Widget>[
                    Text(
                      '1:23',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    Text(
                      '3:44',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          MorphReveal(
            from: 0.55,
            to: 1,
            child: Row(
              mainAxisAlignment: .spaceEvenly,
              children: <Widget>[
                const Icon(Icons.skip_previous_rounded, size: 34),
                Container(
                  width: 64,
                  height: 64,
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: spec.color == null
                        ? Colors.white12
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                  child: IconButton(
                    onPressed: flight.close,
                    icon: const Icon(Icons.pause_rounded, size: 30),
                  ),
                ),
                const Icon(Icons.skip_next_rounded, size: 34),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The album art: a gradient stand-in so the example stays asset-free.
/// Its two sizes are the two ends of the shared-element flight.
class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: .circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF7C5CFF),
            Color(0xFFB84CC5),
            Color(0xFFFF7A59),
          ],
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: size * 0.4,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }
}
