import 'package:flutter/material.dart';

import 'package:morph/widgets.dart';

/// The morph ROUTE: the destination is a real Navigator route, the
/// flight is only its transition. The route is pushed immediately - the
/// back button and further pushes behave like on any page - and at
/// settle the second latch reparents the live content subtree from the
/// shuttle into the route page (type into the field, then close: the
/// text rides the close flight home). "Stack a dialog" pushes a plain
/// Material dialog on top - impossible for an overlay-based morph.
class RouteExample extends StatelessWidget {
  /// Creates the chapter demo.
  const RouteExample({super.key, required this.motion});

  /// Motion profile of the demo springs and flights.
  final MorphMotion motion;

  static const MorphSurfaceSpec _card = MorphSurfaceSpec(
    shape: RoundedRectangleBorder(borderRadius: .all(.circular(22))),
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
    return Center(
      child: MorphTag(
        id: 'gallery-route',
        spec: _card,
        child: MorphSurface(
          onTap: (BuildContext context) => showMorphRoute<void>(
            context,
            motion: motion,
            semanticLabel: 'Note',
            target: MorphTargetSpec.dialog(
              width: 440,
              height: 380,
              surface: _panel,
            ),
            builder: (BuildContext context, MorphFlight flight) =>
                const _NotePage(),
          ),
          child: const Padding(
            padding: .symmetric(horizontal: 26, vertical: 18),
            child: Row(
              mainAxisSize: .min,
              children: <Widget>[
                Icon(Icons.route_rounded, size: 20),
                SizedBox(width: 10),
                Text(
                  'Open a note - as a real route',
                  style: TextStyle(fontSize: 13, fontWeight: .w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotePage extends StatelessWidget {
  const _NotePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .fromLTRB(28, 26, 28, 20),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const Text(
            'Quick note',
            style: TextStyle(fontSize: 20, fontWeight: .w700),
          ),
          const SizedBox(height: 14),
          MorphReveal(
            from: 0.4,
            to: 0.9,
            child: TextField(
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Type here - the text survives the '
                    'shuttle-to-route handover and rides the close '
                    'flight home',
                hintMaxLines: 4,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: .circular(14),
                  borderSide: .none,
                ),
              ),
            ),
          ),
          const Spacer(),
          MorphReveal(
            from: 0.55,
            to: 1,
            child: Row(
              mainAxisAlignment: .spaceBetween,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text('A plain dialog'),
                      content: const Text(
                        'Pushed ON TOP of the morph route - the note is '
                        'a real page in the Navigator, so anything '
                        'stacks above it.',
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.layers_rounded, size: 18),
                  label: const Text('Stack a dialog'),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
