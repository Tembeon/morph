import 'package:morph/src/spring.dart';

/// The tuning of UIKit's morph between a control and the surface it opens,
/// such as a button turning into its menu.
///
/// The defaults are the `liquidMorph` tuning read live from iOS 27, the
/// set a glass button's menu uses. Geometry (position, size, transform)
/// and content travel on slightly underdamped springs; character comes
/// from a separate [kick] and [settle], and the opening ([eject]) and
/// closing ([absorb]) of the main shape use their own springs. Only
/// [eject], [absorb] and [speed] drive the menu implementation. All other
/// fields preserve UIKit's reference settings; changing them does not
/// change the menu. UIKit
/// divides time by [speed], so the effective response of every spring is
/// its response times [speed].
class MorphMenuMorphSpec {
  /// Creates a morph spec from explicit values.
  const MorphMenuMorphSpec({
    this.position = const MorphSpring(0.3, 0.8),
    this.size = const MorphSpring(0.3, 0.8),
    this.transform = const MorphSpring(0.3, 0.8),
    this.content = const MorphSpring(0.3, 0.8),
    this.kick = const MorphSpring(0.35, 0.8),
    this.settle = const MorphSpring(0.5, 0.8),
    this.eject = const MorphSpring(0.5, 0.75),
    this.absorb = const MorphSpring(0.7, 0.8),
    this.blurIn = const MorphSpring(0.3, 1),
    this.blurOut = const MorphSpring(0.45, 0.8),
    this.blurOutMinScale = 1.2,
    this.blurOutMaxScale = 1.65,
    this.secondStepDelay = 0.03,
    this.growingIntermediateShapeRatio = 0.25,
    this.shrinkingIntermediateShapeRatio = 0.9,
    this.genieScale = 0.4,
    this.speed = 0.7,
  });

  /// The spring of the surface's position.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring position;

  /// The spring of the surface's width and height.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring size;

  /// The spring of the surface's transform.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring transform;

  /// The spring of the content crossfade.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring content;

  /// The spring of the impact kick.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring kick;

  /// The spring that settles the surface after the kick.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring settle;

  /// The spring of the main shape while it opens.
  final MorphSpring eject;

  /// The spring of the main shape while it closes.
  final MorphSpring absorb;

  /// The spring that brings blurred content into focus.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring blurIn;

  /// The spring that blurs content away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final MorphSpring blurOut;

  /// The smallest scale of content blurring away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double blurOutMinScale;

  /// The largest scale of content blurring away.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double blurOutMaxScale;

  /// The delay, in seconds, before the second step of the morph starts.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double secondStepDelay;

  /// Where the intermediate shape sits while the surface grows, as a ratio.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double growingIntermediateShapeRatio;

  /// Where the intermediate shape sits while the surface shrinks, as a
  /// ratio.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double shrinkingIntermediateShapeRatio;

  /// The scale of the genie distortion.
  ///
  /// Reference-only UIKit setting; unused by the menu motion.
  final double genieScale;

  /// The speed multiplier UIKit applies to the morph.
  final double speed;

  /// [spring] as it runs at [speed]: its response times [speed], its
  /// damping ratio unchanged.
  MorphSpring atSpeed(MorphSpring spring) =>
      MorphSpring(spring.response * speed, spring.dampingRatio);

  /// UIKit's `liquidMorph` tuning.
  static const standard = MorphMenuMorphSpec();
}
