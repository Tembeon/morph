import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// A haptic a UIKit control plays, mapped onto Flutter's [HapticFeedback]
/// (read from UIKit, notes private; the mapping is declared on
/// [MorphWidgetsTheme.haptics]).
@internal
enum MorphHaptic {
  /// UIKit's light impact generator: a switch toggled by touch, a page
  /// control jogging. [HapticFeedback.lightImpact] plays the same
  /// generator on iOS (near: UIKit tweaks the pattern per control).
  impact(HapticFeedback.lightImpact),

  /// UIKit's selection generator: a page control or a wheel moving to
  /// another item, a finger sliding onto another menu row or alert action.
  /// [HapticFeedback.selectionClick] plays the same generator on iOS
  /// (near).
  selection(HapticFeedback.selectionClick),

  /// The CoreHaptics slider end pattern, played when a dragged slider
  /// reaches either end: a light impact (approximation).
  edge(HapticFeedback.lightImpact),

  /// The CoreHaptics slider detent pattern, played when a stepped slider
  /// moves to another inner stop: a selection tick (approximation).
  detent(HapticFeedback.selectionClick),

  /// The context menu's preview tap, a full-strength discrete pattern: a
  /// heavy impact (approximation, to be felt on the device).
  preview(HapticFeedback.heavyImpact);

  const MorphHaptic(this._play);

  final Future<void> Function() _play;
}

/// Plays [haptic] unless the [MorphWidgetsTheme] above [context] turns the
/// controls' haptics off.
@internal
void morphPlayHaptic(BuildContext context, MorphHaptic haptic) {
  if (!morphHapticsOf(context)) return;
  unawaited(haptic._play());
}
