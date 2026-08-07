import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:morph/morph.dart';
import 'package:morph_example/tour/lessons/dialog_contents.dart';

/// The playground sandbox: the whole canvas is one builder. Pieces (box,
/// stadium, circle) are added, dragged, fused by a single liquid skin
/// and connected with bridges; each piece is also a MorphTag - double-tap
/// launches a real morph flight into a dialog or sheet. Keyframes A/B are
/// scene snapshots; playback is a spring morph of all pieces and the
/// blend from the current state (interruptions and grabbing a piece by
/// hand are free, as everywhere in the system).
const Color kSandboxSkin = Color(0xFF2A2440);

/// The shape families a sandbox piece can take.
enum SandboxShape {
  /// A rounded rectangle with an adjustable radius.
  box,

  /// A capsule; radius derives from the shorter side.
  stadium,

  /// A circle; radius derives from the width.
  circle,
}

/// One draggable, resizable piece on the sandbox canvas.
class SandboxPiece {
  /// Creates a piece.
  SandboxPiece({
    required this.id,
    required this.kind,
    required this.rect,
    this.radius = 18,
  });

  /// Identity on the canvas and for morph flights.
  final int id;

  /// The piece's shape family.
  SandboxShape kind;

  /// Current geometry on the canvas.
  Rect rect;

  /// Corner radius knob; only meaningful for [SandboxShape.box].
  double radius;

  /// For the stadium and circle the radius is derived from geometry
  /// (the SDF clamps it to half the shorter side anyway).
  double get effectiveRadius => switch (kind) {
    .box => radius,
    .stadium || .circle => math.min(rect.width, rect.height) / 2,
  };

  /// The piece outline as a ShapeBorder, optionally stroked.
  ShapeBorder borderWith([BorderSide side = .none]) => switch (kind) {
    .box => RoundedRectangleBorder(side: side, borderRadius: .circular(radius)),
    .stadium => StadiumBorder(side: side),
    .circle => CircleBorder(side: side),
  };
}

/// An explicit bridge between two pieces by id.
class SandboxLink {
  /// Creates a link between pieces [a] and [b].
  const SandboxLink(this.a, this.b);

  /// One linked piece id.
  final int a;

  /// The other linked piece id.
  final int b;

  /// Whether [id] is one of the link's ends.
  bool involves(int id) => a == id || b == id;

  /// Whether this link connects the unordered pair ([x], [y]).
  bool same(int x, int y) => (a == x && b == y) || (a == y && b == x);
}

/// Scene snapshot for a keyframe: piece geometry by id plus the blend.
class SandboxScene {
  /// Captures geometry by piece id plus the blend knob.
  const SandboxScene({required this.geoms, required this.blend});

  /// (rect, radius) per piece id.
  final Map<int, (Rect, double)> geoms;

  /// The blend value at capture time.
  final double blend;
}

/// Ready-made blend presets for the LIQUID knobs.
enum SandboxBlendMode {
  /// Crisp concave joints.
  geometric,

  /// Gooey necks.
  goo,
}

/// The sandbox model: pieces, links, liquid knobs, selection and the
/// keyframe morph player.
class SandboxController extends ChangeNotifier {
  /// Creates the controller with the initial demo pieces.
  SandboxController() {
    pieces = <SandboxPiece>[
      SandboxPiece(
        id: 1,
        kind: .box,
        rect: const .fromLTWH(60, 80, 220, 130),
        radius: 22,
      ),
      SandboxPiece(
        id: 2,
        kind: .stadium,
        rect: const .fromLTWH(250, 40, 110, 44),
      ),
      SandboxPiece(
        id: 3,
        kind: .circle,
        rect: const .fromLTWH(300, 180, 56, 56),
      ),
    ];
    _nextId = 4;
    keyA = capture();
    keyB = const SandboxScene(
      geoms: <int, (Rect, double)>{
        1: (Rect.fromLTWH(160, 56, 180, 110), 28),
        2: (Rect.fromLTWH(90, 200, 140, 48), 24),
        3: (Rect.fromLTWH(360, 120, 72, 72), 36),
      },
      blend: 42,
    );
  }

  /// The live pieces.
  late List<SandboxPiece> pieces;

  /// The explicit bridges.
  final List<SandboxLink> links = <SandboxLink>[];

  /// The skin fusion width in px.
  double blend = 18;

  /// The outline grid step in px.
  double cell = 6;

  /// The last applied preset, or null after manual knob changes.
  SandboxBlendMode? mode;

  /// The selected piece id, if any.
  int? selectedId;

  /// Whether the next piece tap completes a link.
  bool linkArming = false;

  /// Keyframe slot A.
  SandboxScene? keyA;

  /// Keyframe slot B.
  SandboxScene? keyB;
  String _lastPlayed = 'B';

  /// Canvas size; written by the stage from its LayoutBuilder, used only
  /// to clamp dragging - no notify.
  Size stageSize = const Size(600, 400);

  late int _nextId;

  Ticker? _ticker;
  Simulation? _sim;
  Map<int, (Rect, double)>? _fromGeoms;
  double _fromBlend = 0;
  SandboxScene? _target;

  /// The selected piece, if any.
  SandboxPiece? get selected {
    final int? id = selectedId;
    if (id == null) {
      return null;
    }
    for (final SandboxPiece p in pieces) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  /// Whether a keyframe morph is playing.
  bool get isMorphing => _ticker?.isActive ?? false;

  /// Creates the playback ticker from the stage's vsync.
  void attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker(_tick);
  }

  /// The ticker is created from the STAGE's mixin, but the controller
  /// outlives the stage (mode switches, teardown): the stage must hand
  /// the ticker back on dispose, or the mixin asserts on an active
  /// ticker and a remount would reuse a ticker from a dead vsync.
  void detach() {
    _stopMorph();
    _ticker?.dispose();
    _ticker = null;
  }

  // ── Pieces ──

  /// Adds a piece of [kind] near the canvas center.
  void addPiece(SandboxShape kind) {
    _stopMorph();
    final int id = _nextId++;
    // Cascade from the canvas center so new pieces do not stack on top
    // of each other.
    final Offset origin =
        stageSize.center(.zero) +
        Offset(24.0 * (id % 5) - 48, 20.0 * (id % 3) - 20);
    final Size size = switch (kind) {
      .box => const Size(150, 90),
      .stadium => const Size(120, 44),
      .circle => const Size(60, 60),
    };
    pieces.add(
      SandboxPiece(
        id: id,
        kind: kind,
        rect: .fromCenter(
          center: origin,
          width: size.width,
          height: size.height,
        ),
      ),
    );
    selectedId = id;
    linkArming = false;
    notifyListeners();
  }

  /// Removes the selected piece and its links.
  void removeSelected() {
    final int? id = selectedId;
    if (id == null || pieces.length <= 1) {
      return;
    }
    _stopMorph();
    pieces.removeWhere((SandboxPiece p) => p.id == id);
    links.removeWhere((SandboxLink l) => l.involves(id));
    selectedId = null;
    linkArming = false;
    notifyListeners();
  }

  /// Selects [id] (or clears with null); completes a link when armed.
  void select(int? id) {
    selectedId = id;
    linkArming = false;
    notifyListeners();
  }

  /// Tap on a piece: in link-arming mode, link/unlink it with the
  /// selected piece, otherwise just select it.
  void tapPiece(int id) {
    final int? from = selectedId;
    if (linkArming && from != null && from != id) {
      final int existing = links.indexWhere(
        (SandboxLink l) => l.same(from, id),
      );
      if (existing >= 0) {
        links.removeAt(existing);
      } else {
        links.add(SandboxLink(from, id));
      }
      linkArming = false;
      notifyListeners();
      return;
    }
    select(id);
  }

  /// Toggles link-arming for the selected piece.
  void armLink() {
    if (selectedId == null) {
      return;
    }
    linkArming = !linkArming;
    notifyListeners();
  }

  /// Removes an existing link.
  void removeLink(SandboxLink link) {
    links.remove(link);
    notifyListeners();
  }

  /// Resizes the selected piece around its center.
  void resizeSelected({double? width, double? height, double? radius}) {
    final SandboxPiece? p = selected;
    if (p == null) {
      return;
    }
    double w = width ?? p.rect.width;
    double h = height ?? p.rect.height;
    if (p.kind == .circle) {
      w = width ?? height ?? p.rect.width;
      h = w;
    }
    p.rect = .fromCenter(center: p.rect.center, width: w, height: h);
    if (radius != null) {
      p.radius = radius;
    }
    notifyListeners();
  }

  /// Starts dragging piece [id].
  void beginDrag(int id) {
    _stopMorph();
    selectedId = id;
    linkArming = false;
    notifyListeners();
  }

  /// Moves the dragged piece by [delta], clamped to the stage.
  void dragBy(int id, Offset delta) {
    for (final SandboxPiece p in pieces) {
      if (p.id != id) {
        continue;
      }
      final double slack = stageSize.width * 0.03;
      final Rect moved = p.rect.shift(delta);
      p.rect = .fromLTWH(
        moved.left.clamp(-slack, stageSize.width - moved.width + slack),
        moved.top.clamp(-slack, stageSize.height - moved.height + slack),
        moved.width,
        moved.height,
      );
      notifyListeners();
      return;
    }
  }

  // ── Liquid knobs ──

  /// Sets the fusion width knob.
  void setBlend(double value) {
    mode = null;
    blend = value;
    notifyListeners();
  }

  /// Sets the outline grid step knob.
  void setDetail(double value) {
    cell = value;
    notifyListeners();
  }

  /// Applies a blend preset.
  void applyMode(SandboxBlendMode next) {
    mode = next;
    blend = next == .geometric ? 14 : 48;
    notifyListeners();
  }

  // ── Keyframes ──

  /// Snapshots the current geometry and blend.
  SandboxScene capture() {
    return SandboxScene(
      geoms: <int, (Rect, double)>{
        for (final SandboxPiece p in pieces) p.id: (p.rect, p.radius),
      },
      blend: blend,
    );
  }

  /// Stores the current scene into keyframe slot 'A' or 'B'.
  void setKey(String slot) {
    if (slot == 'A') {
      keyA = capture();
    } else {
      keyB = capture();
    }
    notifyListeners();
  }

  /// Spring morph towards a keyframe from the CURRENT scene. Pieces
  /// missing from the snapshot (added later) stay put - only shared
  /// pieces morph.
  void playKey(String slot, Motion motion) {
    final SandboxScene? target = slot == 'A' ? keyA : keyB;
    final Ticker? ticker = _ticker;
    if (target == null || ticker == null) {
      return;
    }
    _lastPlayed = slot;
    ticker.stop();
    _fromGeoms = capture().geoms;
    _fromBlend = blend;
    _target = target;
    mode = null;
    _sim = motion.createSimulation(start: 0, end: 1);
    ticker.start();
    notifyListeners();
  }

  /// A and B in turn - for the autodemo and the toggle button.
  void playToggle(Motion motion) {
    playKey(_lastPlayed == 'A' ? 'B' : 'A', motion);
  }

  void _tick(Duration elapsed) {
    final Simulation? sim = _sim;
    final SandboxScene? target = _target;
    final Map<int, (Rect, double)>? from = _fromGeoms;
    if (sim == null || target == null || from == null) {
      _ticker?.stop();
      return;
    }
    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final double p = sim.x(t);
    final bool done = sim.isDone(t);
    for (final SandboxPiece piece in pieces) {
      final (Rect, double)? a = from[piece.id];
      final (Rect, double)? b = target.geoms[piece.id];
      if (a == null || b == null) {
        continue;
      }
      if (done) {
        piece
          ..rect = b.$1
          ..radius = b.$2;
      } else {
        piece
          ..rect = Rect.lerp(a.$1, b.$1, p)!
          ..radius = a.$2 + (b.$2 - a.$2) * p;
      }
    }
    blend = done ? target.blend : _fromBlend + (target.blend - _fromBlend) * p;
    if (done) {
      _stopMorph();
    }
    notifyListeners();
  }

  void _stopMorph() {
    _ticker?.stop();
    _sim = null;
    _target = null;
    _fromGeoms = null;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

/// The sandbox canvas. The skin is a MorphSkin, each piece is a
/// MorphTag: tap selects, drag moves, double-tap flies a morph (content
/// by id: note / player / composer / share sheet). Clicking empty space
/// clears the selection.
class SandboxStage extends StatefulWidget {
  /// Creates the stage bound to [controller].
  const SandboxStage({
    super.key,
    required this.controller,
    required this.motion,
    required this.bumpScale,
    required this.bumpRecoil,
  });

  /// The sandbox model this stage renders and edits.
  final SandboxController controller;

  /// Motion profile for flights launched from pieces.
  final MorphMotion motion;

  /// Landing squash knob forwarded to the skin pieces.
  final double bumpScale;

  /// Landing recoil knob forwarded to the skin pieces.
  final double bumpRecoil;

  @override
  State<SandboxStage> createState() => _SandboxStageState();
}

class _SandboxStageState extends State<SandboxStage>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  void _openFlight(BuildContext tapContext, SandboxPiece piece) {
    switch ((piece.id - 1) % 4) {
      case 0:
        showMorphDialog(
          tapContext,
          from: piece.id,
          width: 520,
          height: 340,
          motion: widget.motion,
          builder: (BuildContext context, MorphFlight flight) =>
              NoteDialogContent(flight: flight),
        );
      case 1:
        showMorphDialog(
          tapContext,
          from: piece.id,
          width: 440,
          height: 520,
          motion: widget.motion,
          builder: (BuildContext context, MorphFlight flight) =>
              PlayerDialogContent(flight: flight),
        );
      case 2:
        showMorphDialog(
          tapContext,
          from: piece.id,
          width: 480,
          height: 460,
          motion: widget.motion,
          builder: (BuildContext context, MorphFlight flight) =>
              ComposeDialogContent(flight: flight),
        );
      default:
        showMorphSheet(
          tapContext,
          from: piece.id,
          heightFactor: 0.52,
          motion: widget.motion,
          builder: (BuildContext context, MorphFlight flight) =>
              ShareSheetContent(onClose: flight.close),
        );
    }
  }

  IconData _iconFor(SandboxPiece piece) {
    return switch ((piece.id - 1) % 4) {
      0 => Icons.auto_awesome,
      1 => Icons.graphic_eq,
      2 => Icons.add_rounded,
      _ => Icons.ios_share_rounded,
    };
  }

  Widget _pieceContent(SandboxPiece piece, bool isSelected) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SandboxController controller = widget.controller;
    return GestureDetector(
      behavior: .opaque,
      onTap: () => controller.tapPiece(piece.id),
      onDoubleTap: () => _openFlight(context, piece),
      onPanStart: (DragStartDetails details) => controller.beginDrag(piece.id),
      onPanUpdate: (DragUpdateDetails details) =>
          controller.dragBy(piece.id, details.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: piece.borderWith(
              isSelected
                  ? BorderSide(
                      color: controller.linkArming
                          ? const Color(0xFF6FD0BE)
                          : scheme.primary,
                      width: 2,
                    )
                  : .none,
            ),
          ),
          child: Center(
            child: Icon(
              _iconFor(piece),
              size: math.min(24, piece.rect.shortestSide * 0.4),
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SandboxController controller = widget.controller;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        controller.stageSize = constraints.biggest;
        return GestureDetector(
          behavior: .opaque,
          onTap: () => controller.select(null),
          child: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? child) {
              return MorphSkin(
                blend: controller.blend,
                cell: controller.cell,
                color: kSandboxSkin,
                elevation: 5,
                links: <MorphLink>[
                  for (final SandboxLink link in controller.links)
                    MorphLink(from: link.a, to: link.b),
                ],
                pieces: <MorphPiece>[
                  // morphable: an auto-MorphTag by piece id; the group
                  // finds flights in MorphScope on its own - neck,
                  // bridges and landing come for free.
                  for (final SandboxPiece p in controller.pieces)
                    .morphable(
                      id: p.id,
                      rect: p.rect,
                      radius: p.effectiveRadius,
                      bumpScale: widget.bumpScale,
                      bumpRecoil: widget.bumpRecoil,
                      child: _pieceContent(p, p.id == controller.selectedId),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
