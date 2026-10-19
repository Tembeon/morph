import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/channel.dart';
import 'package:morph/src/motion/flex_spec.dart';
import 'package:morph/src/motion/spring_state.dart';

/// The open menu's driftY channel returning from a lift, as an iPhone 16
/// Pro (iOS 27.0.1) published it every 33.339 ms: progress toward the new
/// target and velocity, both per unit of the target change, starting at
/// the update that took the change. Our measurement of UIKit's channel
/// (read from UIKit, notes private).
const _release = [
  (0.0, 1.7546),
  (0.10227, 4.1772),
  (0.26584, 5.4605),
  (0.45597, 5.8095),
  (0.64548, 5.4639),
  (0.81525, 4.6638),
  (0.95380, 3.6244),
  (1.05623, 2.5222),
  (1.12275, 1.4880),
  (1.15716, 0.6069),
  (1.16543, -0.0763),
];

/// The open menu's scaleX channel retargeted from rest while a finger
/// tracks, published 1/60 s and 1/30 s after the change (same device).
const _tracking = [(1 / 60, 0.4988, 29.18), (1 / 30, 0.9155, 19.91)];

void main() {
  test('an equal target is skipped, spring switch included', () {
    final channel = MorphChannel(
      1,
      spring: const MorphSpring(0.6, 0.5),
      trackingSpring: const MorphSpring(0.15, 0.5),
    );
    expect(channel.set(0, 1), isFalse);
    expect(channel.set(0, 2, tracking: true), isTrue);
    expect(channel.set(0.1, 2), isFalse);
    final reference = MorphSpringState(const MorphSpring(0.15, 0.5), 1);
    reference.retarget(0, 2);
    expect(channel.value(0.3), moreOrLessEquals(reference.value(0.3)));
  });

  test('a retarget carries the value and velocity', () {
    const spring = MorphSpring(0.4, 0.375);
    final channel = MorphChannel(0, spring: spring);
    final reference = MorphSpringState(spring, 0);
    channel.set(0, 10);
    reference.retarget(0, 10);
    channel.set(0.05, -4);
    reference.retarget(0.05, -4);
    for (final t in [0.06, 0.1, 0.4]) {
      expect(channel.value(t), moreOrLessEquals(reference.value(t)));
      expect(channel.velocity(t), moreOrLessEquals(reference.velocity(t)));
    }
  });

  test('a changed target pushes by stiffness x impulse x change', () {
    const spring = MorphSpring(0.6, 0.5);
    const tracking = MorphSpring(0.15, 0.5);
    final channel = MorphChannel(
      0,
      spring: spring,
      trackingSpring: tracking,
      retargetImpulse: 0.016,
    );
    channel.set(0, 2, tracking: true);
    expect(channel.velocity(0), moreOrLessEquals(tracking.stiffness * 0.032));
    final before = channel.velocity(0.01);
    channel.set(0.01, 1);
    expect(
      channel.velocity(0.01) - before,
      moreOrLessEquals(-spring.stiffness * 0.016),
    );
  });

  test('the menu channel returns from a lift as the device published', () {
    final channel = MorphChannel(
      -1,
      spring: MorphFlexSpec.menu.scaleSpring,
      trackingSpring: MorphFlexSpec.menu.trackingSpring,
      retargetImpulse: MorphFlexSpec.menu.retargetImpulse,
    );
    channel.set(0, 0);
    for (var i = 0; i < _release.length; i++) {
      final (progress, velocity) = _release[i];
      final t = i * 0.033339;
      expect(channel.value(t) + 1, moreOrLessEquals(progress, epsilon: 2e-3));
      expect(channel.velocity(t), moreOrLessEquals(velocity, epsilon: 0.02));
    }
  });

  test('the menu channel tracks a finger as the device published', () {
    final channel = MorphChannel(
      -1,
      spring: MorphFlexSpec.menu.scaleSpring,
      trackingSpring: MorphFlexSpec.menu.trackingSpring,
      retargetImpulse: MorphFlexSpec.menu.retargetImpulse,
    );
    channel.set(0, 0, tracking: true);
    for (final (t, progress, velocity) in _tracking) {
      expect(channel.value(t) + 1, moreOrLessEquals(progress, epsilon: 2e-3));
      expect(channel.velocity(t), moreOrLessEquals(velocity, epsilon: 0.05));
    }
  });

  test('a stepped channel advances a changed target by the retarget step', () {
    const spring = MorphSpring(0.574, 0.548);
    final pulse = MorphChannel.stepped(0, spring: spring, retargetStep: 1 / 60);
    final reference = MorphSpringState(spring, 0);
    pulse.snap(0, 0);
    pulse.step(1 / 30, 10);
    reference.retarget(0, 10);
    expect(pulse.value(1), moreOrLessEquals(reference.value(1 / 60)));
    expect(pulse.velocity(1), moreOrLessEquals(reference.velocity(1 / 60)));
    pulse.step(2 / 30, 10);
    expect(pulse.value(0), moreOrLessEquals(reference.value(1 / 60 + 1 / 30)));
    expect(pulse.holdsWithin(10, 1, 0.25), isFalse);
    expect(pulse.holdsWithin(11, 1e-9, 0.25), isFalse);
    pulse.clearPublishedVelocity();
    expect(pulse.velocity(0), 0);
  });
}
