import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import 'package:morph/widgets.dart';
import 'package:morph_example/tour/device.dart';
import 'package:morph_example/ui/lab_chrome.dart';

/// One bubble of the conversation.
typedef _Message = ({int id, String text, bool mine});

/// The held-surface case: a chat where a bubble becomes its own context
/// menu. Hold it and it lifts under the finger; on the hold threshold
/// it flies to where its satellites fit - a reactions capsule appears
/// above, the actions below, both on the flight's own spring - and the
/// bubble keeps its identity the whole way (a shared element, not a
/// copy fading over a copy). The bubble travels only as far as the
/// menu needs; tapping the scrim or an action flies everything home.
///
/// The column is live. Pick a reaction and it lands on the bubble at
/// once - the hero's slot springs to the badge and the actions slide
/// down - while the capsule unfolds a note field: its slot is sized by
/// its content and springs to every change. Focus the note and the
/// keyboard rises (the phone's own, driven by the KEYBOARD toggle on
/// desktop): the column moves out from under it, the bubble travelling
/// with it.
///
/// The mockup mirrors the app that asked for it: the chat is a NESTED
/// navigator with a compose bar floating over it, so the menu must
/// choose its overlay - the tab's own (under the bar) or the phone's
/// (above it), with anchors measured in the chosen space. Deleting a
/// bubble from its own menu removes the source mid-flight: the flight
/// survives it and dissolves on its way home instead of landing on a
/// row that no longer exists. Every flight's moments are logged from
/// [MorphFlight.events] - the seam an app's haptics would use.
class HoldLesson extends StatefulWidget {
  /// Creates the chapter demo.
  const HoldLesson({super.key, required this.motion});

  /// Motion profile of the menu flights.
  final MorphMotion motion;

  @override
  State<HoldLesson> createState() => _HoldLessonState();
}

class _HoldLessonState extends State<HoldLesson>
    with SingleTickerProviderStateMixin {
  static const Color _glass = Color(0xFF2A2440);
  static const Color _accent = Color(0xFF7C5CFF);
  static const Color _menu = Color(0xFF262038);
  static const Color _danger = Color(0xFFFF7A83);

  /// The software keyboard's height when shown, in px.
  static const double _keyboardHeight = 240;

  static const List<(IconData, String)> _actions = <(IconData, String)>[
    (Icons.reply_rounded, 'Reply'),
    (Icons.copy_rounded, 'Copy'),
    (Icons.push_pin_outlined, 'Pin'),
    (Icons.delete_outline_rounded, 'Delete'),
  ];

  static const List<IconData> _reactions = <IconData>[
    Icons.favorite_rounded,
    Icons.thumb_up_rounded,
    Icons.local_fire_department_rounded,
    Icons.sentiment_very_satisfied_rounded,
    Icons.sentiment_dissatisfied_rounded,
  ];

  List<_Message> _messages = <_Message>[
    (id: 1, text: 'Hey! Did you get the tickets?', mine: false),
    (id: 2, text: 'Yes, two for Friday', mine: true),
    (id: 3, text: 'Amazing. Which row?', mine: false),
    (id: 4, text: 'Front, but on the side', mine: true),
    (id: 5, text: 'Perfect, I will bring the flags', mine: false),
    (id: 6, text: 'Hold this bubble', mine: true),
    (id: 7, text: 'Long-press me too', mine: false),
    (id: 8, text: 'See you at seven?', mine: false),
    (id: 9, text: 'Seven it is. The last bubble sits by the bar', mine: true),
  ];
  final Map<int, IconData> _reacted = <int, IconData>{};

  bool _appOverlay = true;
  bool _keyboard = false;
  double _holdMs = 500;
  bool _lifts = true;
  String _lastAction = 'nothing yet';
  final List<MorphFlightEvent> _events = <MorphFlightEvent>[];
  StreamSubscription<MorphFlightEvent>? _watching;

  /// The phone's keyboard: an inset that rises and falls like the real
  /// one, so everything reading MediaQuery.viewInsets sees a keyboard.
  late final SingleMotionController _keyboardInset = SingleMotionController(
    motion: const CupertinoMotion.smooth(duration: Duration(milliseconds: 320)),
    vsync: this,
    initialValue: 0,
  );

  @override
  void dispose() {
    _watching?.cancel();
    _keyboardInset.dispose();
    super.dispose();
  }

  void _note(String action) {
    if (mounted) {
      setState(() => _lastAction = action);
    }
  }

  /// A new flight took off: follow its moments - launched, settled,
  /// closing, latched, landed - the way an app would for its haptics.
  void _watch(MorphFlight flight) {
    _watching?.cancel();
    _events.clear();
    _watching = flight.events.listen((MorphFlightEvent event) {
      if (mounted) {
        setState(() => _events.add(event));
      }
    });
  }

  void _setKeyboard(bool shown) {
    setState(() => _keyboard = shown);
    _keyboardInset.animateTo(shown ? _keyboardHeight : 0);
  }

  /// A reaction lands on the bubble at once - the hero's slot follows
  /// its content - and the capsule unfolds the note field.
  void _react(_Message message, IconData icon) {
    setState(() {
      if (_reacted[message.id] == icon) {
        _reacted.remove(message.id);
        _note('took the reaction off "${message.text}"');
      } else {
        _reacted[message.id] = icon;
        _note('reacted to "${message.text}"');
      }
    });
  }

  void _sendNote(_Message message, String note, MorphFlight flight) {
    _note(
      note.trim().isEmpty
          ? 'sent the reaction on "${message.text}"'
          : 'noted "$note" on "${message.text}"',
    );
    flight.close();
  }

  void _act(_Message message, String label, MorphFlight flight) {
    _note('${label.toLowerCase()} "${message.text}"');
    flight.close();
    if (label == 'Delete') {
      // The source leaves the tree while the menu is still flying
      // home: the flight freezes the last rect and dissolves instead
      // of landing on the bubble that took its place.
      setState(() {
        _messages = <_Message>[
          for (final _Message m in _messages)
            if (m.id != message.id) m,
        ];
      });
    }
  }

  Widget _reactionCapsule(
    BuildContext context,
    _Message message,
    MorphFlight flight,
  ) {
    final IconData? picked = _reacted[message.id];
    return Align(
      alignment: message.mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: .all(.circular(picked == null ? 22 : 18)),
          ),
          color: _glass,
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                mainAxisSize: .min,
                children: <Widget>[
                  for (final IconData icon in _reactions)
                    LabIconButton(
                      icon: icon,
                      onPressed: () => _react(message, icon),
                      tint: const Color(0x00000000),
                      size: 20,
                      padding: 6,
                      color: picked == icon
                          ? _accent
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                ],
              ),
              // The note row exists only once a reaction is picked: the
              // capsule's slot springs to it, and the keyboard the field
              // summons pushes the whole column up.
              if (picked != null)
                _NoteRow(
                  onSend: (String note) => _sendNote(message, note, flight),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context,
    _Message message,
    MorphFlight flight,
  ) {
    return Align(
      alignment: message.mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: SizedBox(
        width: 210,
        child: DecoratedBox(
          decoration: const ShapeDecoration(
            shape: RoundedRectangleBorder(borderRadius: .all(.circular(16))),
            color: _menu,
          ),
          child: Padding(
            padding: const .symmetric(vertical: 6),
            child: Column(
              mainAxisSize: .min,
              children: <Widget>[
                for (final (IconData icon, String label) in _actions)
                  GestureDetector(
                    behavior: .opaque,
                    onTap: () => _act(message, label, flight),
                    child: SizedBox(
                      height: 42,
                      child: Padding(
                        padding: const .symmetric(horizontal: 16),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              icon,
                              size: 18,
                              color: label == 'Delete'
                                  ? _danger
                                  : Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: label == 'Delete' ? _danger : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SceneScaffold(
      controls: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const PanelHint(
            'Hold a bubble: it lifts under the finger, and on the hold '
            'threshold it becomes its own menu - reactions appear above, '
            'actions below, on the flight\'s spring. The bubble travels '
            'only as far as the menu needs. Pick a reaction: it lands on '
            'the bubble at once and the capsule unfolds a note field - the '
            'column is live, the bubble stays put. The "..." glyph is the '
            'visible door into the same menu.',
          ),
          PanelSection(
            label: 'OVERLAY',
            child: LabSegmented(
              labels: const <String>['Chat tab', 'Whole app'],
              index: _appOverlay ? 1 : 0,
              onSelect: (int i) => setState(() => _appOverlay = i == 1),
            ),
          ),
          PanelHint(
            _appOverlay
                ? 'The menu renders in the phone\'s overlay, ABOVE the '
                      'compose bar: the chat is a nested navigator and the '
                      'bar floats over it. Anchors are measured in the '
                      'chosen space, so nothing drifts.'
                : 'The menu renders in the nearest overlay - the chat '
                      'tab\'s own - so it lives UNDER the floating bar. '
                      'Hold the last bubble and watch the actions hide '
                      'behind the chrome.',
          ),
          PanelSection(
            label: 'KEYBOARD',
            child: LabSegmented(
              labels: const <String>['Hidden', 'Shown'],
              index: _keyboard ? 1 : 0,
              onSelect: (int i) => _setKeyboard(i == 1),
            ),
          ),
          const PanelHint(
            'The phone\'s own keyboard: it reports the inset a real one '
            'would. An open menu moves out from under it and the bubble '
            'travels with the column; the compose bar rises too. Every '
            'target sees the keyboard as part of the space it may not '
            'cover.',
          ),
          PanelSection(
            label: 'HOLD',
            child: Column(
              children: <Widget>[
                PanelKnob(
                  label: 'hold',
                  value: _holdMs,
                  min: 150,
                  max: 900,
                  format: (double v) => '${v.round()}ms',
                  onChanged: (double v) => setState(() => _holdMs = v),
                ),
                LabSwitchTile(
                  label: 'glass lift',
                  value: _lifts,
                  onChanged: (bool v) => setState(() => _lifts = v),
                ),
              ],
            ),
          ),
          PanelSection(
            label: 'EVENTS',
            child: Text(
              _events.isEmpty
                  ? 'no flight yet'
                  : _events.map((MorphFlightEvent e) => e.name).join('  ->  '),
              style: const TextStyle(fontSize: 12, fontWeight: .w600),
            ),
          ),
          PanelSection(
            label: 'LAST ACTION',
            child: Text(
              _lastAction,
              style: const TextStyle(fontSize: 12.5, fontWeight: .w600),
            ),
          ),
        ],
      ),
      phone: PhoneFrame(
        keyboard: _keyboardInset,
        // This context sits under the PHONE's navigator, above the
        // chat's nested one: its overlay is the one that floats over
        // the compose bar.
        app: (BuildContext context) => _ChatScope(
          state: this,
          child: _ChatStage(phoneOverlay: Overlay.of(context)),
        ),
      ),
    );
  }
}

/// The note field under a picked reaction, with its send button. Its
/// own widget so the field's text survives the menu rebuilding around
/// it.
class _NoteRow extends StatefulWidget {
  const _NoteRow({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .fromLTRB(8, 2, 2, 4),
      child: SizedBox(
        width: 200,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _text,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration.collapsed(
                  hintText: 'Add a note',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                onSubmitted: widget.onSend,
              ),
            ),
            LabIconButton(
              icon: Icons.send_rounded,
              onPressed: () => widget.onSend(_text.text),
              tint: const Color(0x00000000),
              padding: 6,
              color: _HoldLessonState._accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hands the lesson state to the chat page. The page lives in a nested
/// Navigator's route - an overlay entry, an island that no ancestor
/// rebuild reaches - so the state travels as an InheritedWidget:
/// dependents inside the island rebuild when the lesson does.
class _ChatScope extends InheritedWidget {
  const _ChatScope({required this.state, required super.child});

  final _HoldLessonState state;

  static _HoldLessonState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChatScope>()!.state;

  @override
  bool updateShouldNotify(_ChatScope oldWidget) => true;
}

/// The phone's app: a nested navigator carrying the chat, and the
/// compose bar floating over it - the layering that forces the choice
/// of overlay. The bar rises with the keyboard like a real one.
class _ChatStage extends StatelessWidget {
  const _ChatStage({required this.phoneOverlay});

  final OverlayState phoneOverlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Navigator(
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  settings: settings,
                  builder: (BuildContext context) =>
                      _ChatPage(phoneOverlay: phoneOverlay),
                ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 10 + MediaQuery.viewInsetsOf(context).bottom,
          child: const _ComposeBar(),
        ),
      ],
    );
  }
}

class _ChatPage extends StatelessWidget {
  const _ChatPage({required this.phoneOverlay});

  final OverlayState phoneOverlay;

  @override
  Widget build(BuildContext context) {
    final _HoldLessonState state = _ChatScope.of(context);
    return ColoredBox(
      color: const Color(0xFF15121F),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          const Padding(
            padding: .fromLTRB(20, 10, 20, 8),
            child: Text(
              'Sam',
              style: TextStyle(fontSize: 22, fontWeight: .w800),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const .fromLTRB(12, 4, 12, 84),
              itemCount: state._messages.length,
              itemBuilder: (BuildContext context, int index) {
                final _Message message = state._messages[index];
                return _BubbleRow(
                  // Keyed by identity: deleting a bubble must not hand
                  // its region State (and its tag) to the next one.
                  key: ValueKey<int>(message.id),
                  message: message,
                  phoneOverlay: phoneOverlay,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One bubble in the conversation: the region around it is the whole
/// recipe - the hold, the lift, the flight to where the satellites fit.
/// Both satellites are sized by their content.
class _BubbleRow extends StatelessWidget {
  const _BubbleRow({
    super.key,
    required this.message,
    required this.phoneOverlay,
  });

  final _Message message;
  final OverlayState phoneOverlay;

  @override
  Widget build(BuildContext context) {
    final _HoldLessonState state = _ChatScope.of(context);
    final AlignmentDirectional side = message.mine
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    return Padding(
      padding: const .symmetric(vertical: 3),
      child: Align(
        alignment: side,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: MorphContextMenuRegion(
            alignment: side,
            width: 230,
            holdDuration: Duration(milliseconds: state._holdMs.round()),
            lifts: state._lifts,
            motion: state.widget.motion,
            overlay: state._appOverlay ? phoneOverlay : null,
            semanticLabel: 'Message menu',
            onHold: () => state._note('held "${message.text}"'),
            onOpen: state._watch,
            above: MorphSatellite(
              builder: (BuildContext context, MorphFlight flight) =>
                  state._reactionCapsule(context, message, flight),
            ),
            below: MorphSatellite(
              builder: (BuildContext context, MorphFlight flight) =>
                  state._actionCard(context, message, flight),
            ),
            child: _Bubble(
              message: message,
              reaction: state._reacted[message.id],
              onTap: () => state._note('tapped "${message.text}"'),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero: draws its own surface - the flight's vessel is transparent
/// - and carries the visible door into the menu.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.reaction,
    required this.onTap,
  });

  final _Message message;
  final IconData? reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: message.mine
              ? _HoldLessonState._accent
              : _HoldLessonState._glass,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
        ),
        child: Padding(
          padding: const .fromLTRB(14, 9, 10, 9),
          child: Row(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Flexible(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      message.text,
                      style: const TextStyle(fontSize: 13.5, height: 1.3),
                    ),
                    if (reaction != null)
                      Padding(
                        padding: const .only(top: 4),
                        child: Icon(
                          reaction,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // The visible door: the same menu the hold opens, from a
              // context inside the region's child.
              Builder(
                builder: (BuildContext context) => GestureDetector(
                  behavior: .opaque,
                  onTap: () => MorphContextMenuRegion.open(context),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating compose bar the menu must fly above.
class _ComposeBar extends StatelessWidget {
  const _ComposeBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            height: 46,
            padding: const .symmetric(horizontal: 18),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: _HoldLessonState._glass,
              shadows: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              'Message',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 46,
          height: 46,
          decoration: const ShapeDecoration(
            shape: CircleBorder(),
            color: _HoldLessonState._accent,
          ),
          child: const Icon(Icons.send_rounded, size: 18),
        ),
      ],
    );
  }
}
