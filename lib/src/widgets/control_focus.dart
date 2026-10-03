import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The color of the keyboard focus ring: iOS systemBlue.
@internal
const Color morphFocusRingColor = Color(0xFF007AFF);

/// A request to move a control by [delta] steps in visual order: -1 for
/// left or down, 1 for right or up.
@internal
class MorphStepIntent extends Intent {
  /// Creates the intent.
  const MorphStepIntent(this.delta);

  /// The visual direction of the step.
  final int delta;
}

/// Makes a measured control focusable and keyboard operable.
///
/// Space and Enter call [onActivate]; the left and right arrows, and the
/// up and down arrows when [steps] is vertical too, call [onStep] with
/// the visual direction. [onHighlight] reports whether the keyboard focus
/// ring should show.
@internal
class MorphControlFocus extends StatelessWidget {
  /// Creates the wrapper.
  const MorphControlFocus({
    required this.enabled,
    required this.onHighlight,
    required this.child,
    this.onActivate,
    this.onStep,
    this.verticalSteps = false,
    super.key,
  });

  /// Whether the control can take focus.
  final bool enabled;

  /// Called when the focus ring should show or hide.
  final ValueChanged<bool> onHighlight;

  /// Called on Space or Enter.
  final VoidCallback? onActivate;

  /// Called on an arrow key with the visual direction.
  final ValueChanged<int>? onStep;

  /// Whether the up and down arrows step too.
  final bool verticalSteps;

  /// The control.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final step = onStep;
    final activate = onActivate;
    return FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: onHighlight,
      shortcuts: <ShortcutActivator, Intent>{
        if (activate != null) ...{
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
        },
        if (step != null) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              const MorphStepIntent(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              const MorphStepIntent(1),
          if (verticalSteps) ...{
            const SingleActivator(LogicalKeyboardKey.arrowDown):
                const MorphStepIntent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowUp):
                const MorphStepIntent(1),
          },
        },
      },
      actions: <Type, Action<Intent>>{
        if (activate != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent intent) {
              activate();
              return null;
            },
          ),
        if (step != null)
          MorphStepIntent: CallbackAction<MorphStepIntent>(
            onInvoke: (MorphStepIntent intent) {
              step(intent.delta);
              return null;
            },
          ),
      },
      child: child,
    );
  }
}

/// Paints the keyboard focus ring around a capsule control while
/// [visible].
@internal
class MorphFocusRing extends StatelessWidget {
  /// Creates the ring.
  const MorphFocusRing({required this.visible, required this.child, super.key});

  /// Whether the ring shows.
  final bool visible;

  /// The control.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: visible ? const MorphFocusRingPainter() : null,
      child: child,
    );
  }
}

/// Paints a capsule focus ring just outside the painted box.
@internal
class MorphFocusRingPainter extends CustomPainter {
  /// Creates the painter.
  const MorphFocusRingPainter();

  /// Paints the ring around [rect] on [canvas].
  static void paintRing(Canvas canvas, Rect rect) {
    final outer = rect.inflate(3);
    final ring = Paint();
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = 3;
    ring.color = morphFocusRingColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, Radius.circular(outer.shortestSide / 2)),
      ring,
    );
  }

  @override
  void paint(Canvas canvas, Size size) => paintRing(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(MorphFocusRingPainter oldDelegate) => false;
}

/// Dims a disabled control to [opacity] of its enabled look, as one layer
/// over the whole control; it switches in one frame, as UIKit does.
@internal
class MorphDisabled extends StatelessWidget {
  /// Creates the wrapper.
  const MorphDisabled({
    required this.enabled,
    required this.opacity,
    required this.child,
    super.key,
  });

  /// Whether the control accepts input.
  final bool enabled;

  /// The opacity of the disabled control.
  final double opacity;

  /// The control.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(opacity: enabled ? 1 : opacity, child: child);
  }
}
