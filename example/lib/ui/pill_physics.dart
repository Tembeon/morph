import 'package:motor/motor.dart';

/// The reference glide of a selection pill travelling between slots:
/// near-critically damped (~0.38 s, a whisper of bounce), so the
/// landing is precise and the squash-and-stretch - not the overshoot -
/// carries the life. Calibrated against the liquid-glass reference
/// pill; its companion springs there are a lift of ~0.40 s / bounce
/// 0.40 and a landing of ~0.39 s / bounce 0.45 that stops on its first
/// rebound through rest - adopt those numbers when a pill grows a
/// lifted state.
const Motion pillGlide = CupertinoMotion(
  duration: Duration(milliseconds: 376),
  bounce: 0.06,
);
