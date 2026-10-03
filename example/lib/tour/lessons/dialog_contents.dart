import 'package:material_ui/material_ui.dart';

import 'package:morph/widgets.dart';

/// Surface color of the player dialog.
const Color kPlayerColor = Color(0xFF2A2440);

/// Surface color of the share sheet.
const Color kShareColor = Color(0xFF1E3A34);

/// Surface color of the compose dialog.
const Color kComposeColor = Color(0xFF7C5CFF);

/// Surface color of the note dialog.
const Color kNoteColor = Color(0xFF41341E);

/// A short note dialog body.
class NoteDialogContent extends StatelessWidget {
  /// Creates the note dialog body.
  const NoteDialogContent({super.key, required this.flight});

  /// The enclosing flight, for closing.
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .fromLTRB(28, 22, 28, 20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Color(0xFFD8B569),
              ),
              const SizedBox(width: 10),
              const Text(
                'Quick note',
                style: TextStyle(fontSize: 18, fontWeight: .w600),
              ),
              const Spacer(),
              IconButton(
                onPressed: flight.close,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A long flight across the whole screen on one spring: the close '
            'dips just below zero, the way UIKit lands. Try all three '
            'motion profiles.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: .end,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: flight.close,
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A music player dialog body.
class PlayerDialogContent extends StatelessWidget {
  /// Creates the player dialog body.
  const PlayerDialogContent({super.key, required this.flight});

  /// The enclosing flight, for closing.
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Now playing',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: flight.close,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: .circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF7C5CFF), Color(0xFF2AB8C5)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.graphic_eq,
                      size: 72,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Column(
            children: <Widget>[
              const Text(
                'Ambient Drift',
                textAlign: .center,
                style: TextStyle(fontSize: 20, fontWeight: .w600),
              ),
              Text(
                'Ambient - night session',
                textAlign: .center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: <Widget>[
              const LinearProgressIndicator(borderRadius: .all(.circular(4))),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: .center,
                children: <Widget>[
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_previous_rounded, size: 30),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {},
                    iconSize: 34,
                    icon: const Icon(Icons.pause_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next_rounded, size: 30),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A share sheet body.
class ShareSheetContent extends StatelessWidget {
  /// Creates the share sheet body.
  const ShareSheetContent({super.key, required this.onClose});

  /// Closes the enclosing flight.
  final VoidCallback onClose;

  static const List<(IconData, String, Color)> _targets =
      <(IconData, String, Color)>[
        (Icons.chat_bubble_rounded, 'Chat', Color(0xFF7C5CFF)),
        (Icons.send_rounded, 'Telegram', Color(0xFF29B6F6)),
        (Icons.camera_alt_rounded, 'Stories', Color(0xFFEC407A)),
        (Icons.alternate_email_rounded, 'Mail', Color(0xFF66BB6A)),
        (Icons.music_note_rounded, 'Audio', Color(0xFFFFA726)),
        (Icons.image_rounded, 'Card', Color(0xFF26C6DA)),
        (Icons.qr_code_rounded, 'QR', Color(0xFFAB47BC)),
        (Icons.more_horiz_rounded, 'More', Color(0xFF78909C)),
      ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .fromLTRB(28, 20, 28, 24),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'Share track',
                style: TextStyle(fontSize: 18, fontWeight: .w600),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The sheet morphs out of the control with showMorphSheet; its '
            'content fades in on the same spring as the surface.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              childAspectRatio: 1.45,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (final (IconData icon, String label, Color color)
                    in _targets)
                  Column(
                    mainAxisSize: .min,
                    children: <Widget>[
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: color.withValues(alpha: 0.18),
                          border: Border.all(
                            color: color.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(height: 6),
                      Text(label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ],
      ),
    );
  }
}

/// A compose form body with a title field and tags.
class ComposeDialogContent extends StatelessWidget {
  /// Creates the compose dialog body.
  const ComposeDialogContent({super.key, required this.flight});

  /// The enclosing flight, for closing.
  final MorphFlight flight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const .fromLTRB(28, 24, 28, 20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              const Text(
                'New playlist',
                style: TextStyle(fontSize: 20, fontWeight: .w600),
              ),
              const SizedBox(height: 4),
              Text(
                'The form arrives with the surface: one spring drives the '
                'whole dialog.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Expanded(
            child: TextField(
              expands: true,
              maxLines: null,
              textAlignVertical: .top,
              decoration: InputDecoration(
                labelText: 'Describe the vibe',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final String tag in <String>[
                    'ambient',
                    'chill',
                    'night',
                  ])
                    Chip(label: Text(tag), visualDensity: .compact),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: .end,
                children: <Widget>[
                  TextButton(
                    onPressed: flight.close,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: flight.close,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
