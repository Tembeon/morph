import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/motion/motion.dart';
import 'package:morph/src/motion/spring.dart';
import 'package:morph/src/motion/channel.dart';
import 'package:morph/src/motion/flex_interaction.dart';
import 'package:morph/src/motion/flex_spec.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph/src/widgets/menu_morph_spec.dart';
import 'package:morph/src/motion/spring_state.dart';
import 'package:morph/src/motion/timeline.dart';
import 'package:morph/src/widgets/glass_glow.dart';

/// The tuning of a glass button's menu, as measured on iOS 27.
///
/// The springs, delays and metrics are fitted to frame-by-frame
/// recordings of a `UIButton` with a glass configuration whose menu is its
/// primary action. Lengths are logical pixels, times seconds.
class MorphMenuTuning {
  /// Creates a tuning from explicit values.
  const MorphMenuTuning({
    this.morph = MorphMenuMorphSpec.standard,
    this.menuWidth = defaultMenuWidth,
    this.rowHeight = 42,
    this.verticalPadding = 10,
    this.cornerRadius = 32,
    this.openingRadius = 195.4,
    this.radiusDelay = 0.098,
    this.sourceEndScale = 0.25,
    this.sourceTravel = 0.25,
    this.crossfadeBlur = 4,
    this.fadeLead = 0.015,
    this.lookFadeStart = 0.07,
    this.lookFadeEnd = 0.42,
    this.lookStretch = 2.5,
    this.contentFadeStart = 0,
    this.contentFadeEnd = 1,
    this.contentCloseFadeEnd = 0.53,
    this.contentKickScale = 1.45,
    this.contentBlur = 8,
    this.contentKickBlur = 6,
    this.tapOpenDelay = 0.089,
    this.holdDuration = 0.22,
    this.tapSlop = 70,
    this.dismissDelay = 0.059,
    this.earlyCloseDelay = 0.016,
    this.actionDelay = 0.016,
    this.pressDelay = 0.015,
    this.sourceRelax = 0.05,
    this.openKickSpring = const MorphSpring(0.2048, 0.651),
    this.openKickGain = 4.229,
    this.closeKickSpring = const MorphSpring(0.3396, 0.8425),
    this.closeKickImpulse = 1450,
    this.closeKickDelay = 0.012,
    this.closeKickReach = 31.7,
    this.sourceKickSpring = const MorphSpring(0.3102, 0.6335),
    this.sourceKickGain = 2.02,
    this.edgeMargin = defaultEdgeMargin,
    this.glowDiameter = 160,
    this.glowRiseLag = 0.03,
    this.glowMinimumLit = 0.1,
    this.highlightInset = 10,
    this.flex = MorphFlexSpec.menu,
    this.flexInBoundsPoints = 40,
    this.flexPulseSpring = const MorphSpring(0.574, 0.548),
    this.flexPulseRate = 30,
    this.flexPulseRetargetStep = 1 / 60,
    this.flexDelay = 0.023,
    this.fusionRadius = 20,
    this.fusionCloseAmplitude = 20.95,
    this.fusionOpenRise = 0.0161,
    this.fusionCloseRise = 0.0213,
    this.fusionOpenHold = 0.199,
    this.fusionCloseHold = 0.057,
    this.fusionSpring = const MorphSpring(0.4286, 1),
    this.fusionCutoff = 0.2,
    this.metrics = MorphMenuMetrics.standard,
    this.submenuSpring = const MorphSpring(0.395, 0.86),
    this.submenuDelay = 0.076,
    this.deeperSubmenuSpring = const MorphSpring(0.405, 0.84),
    this.deeperSubmenuDelay = 0.04,
    this.backSpring = const MorphSpring(0.4, 1),
    this.backDelay = 0.022,
    this.hoverOpenDelay = 0.525,
    this.submenuActionDelay = 0.019,
    this.submenuCloseDelay = 0.031,
    this.keptActionDelay = 0.02,
    this.parentScale = 0.97,
    this.parentRowOpacity = 0.5,
    this.cardStartWidth = 230,
    this.cardLead = 36,
    this.cardRowsFadeIn = 0.25,
    this.cardRowsFadeOut = 0.55,
    this.cardPlatterFade = 0.3,
    this.cardHeaderBoldStart = 0.15,
    this.cardHeaderBoldEnd = 0.35,
    this.cardChevronTurn = 0.4,
    this.cardChevronBack = 0.2,
    this.cardCloseFadeEnd = 0.2,
    this.cardCloseCenter = 0.5,
    this.cardContainerSpring = const MorphSpring(0.35, 0.85),
    this.cardContainerDelay = 0,
    this.cardContainerEndWidth = 50,
    this.cardBlur = 10,
    this.cardDisplacement = 0,
    this.cardTransmissionGamma = 1.14,
    this.cardGone = 0.007,
    this.growSpring = const MorphSpring(0.565, 0.84),
    this.growDelay = 0.045,
    this.shrinkSpring = const MorphSpring(0.4, 1),
    this.shrinkDelay = 0.03,
  });

  /// The menu width from the iOS 27 view tree, in points.
  static const double defaultMenuWidth = 250;

  /// The horizontal placement margin from the device menu traces.
  static const double defaultEdgeMargin = 8;

  /// The diameter of the measured round glass menu button, in points.
  static const double buttonDiameter = 48;

  /// The numerical integration step of the measured driven kicks, in seconds.
  static const double kickIntegrationStep = 0.001;

  /// The driven kick displacement considered at rest, in points.
  static const double kickRestValue = 0.01;

  /// The driven kick velocity considered at rest, in points per second.
  static const double kickRestVelocity = 0.1;

  /// The remaining idle span above which kick integration skips ahead.
  ///
  /// This numerical optimization threshold is not a measured motion value.
  static const double kickSkipSpan = 1;

  /// The largest move, in points, of a menu edge that the flex pulse
  /// channel may still make once it stops stepping while a finger rests.
  ///
  /// A NEAR trade, not a measured value (0.75 px on a 3x screen at most,
  /// awaiting approval by eye; the bound is the channel's largest possible
  /// remaining swing, the swing itself is smaller): the channel
  /// ([MorphMenuTuning.flexPulseSpring]) stops stepping once what is left
  /// of it cannot move an edge by more than this, and the shape keeps that
  /// remainder until the finger moves or lifts. Without it a 4 pt slide on
  /// a row keeps the menu drawing a frame per channel step through about
  /// 0.7 s of sub-pixel ringing (the perf_counts menu-held scene: 238
  /// frames at 0.01 pt, 224 at this value, 226 for the fitted model's
  /// sway at the same rest).
  static const double flexPulseRest = 0.25;

  /// The largest move, in points, of a menu edge that the flex's return
  /// may still make when it counts as at rest.
  ///
  /// A NEAR trade, not a measured value (0.03 px on a 3x screen,
  /// invisible): the return on the flex spec's scale spring stops driving
  /// frames below it.
  static const double flexReturnRest = 0.01;

  /// The row glyph size from the iOS 27 menu view tree, in points.
  static const double rowIconSize = 20;

  /// The context menu edge margin; an engineering default, not measured.
  static const double contextMargin = 12;

  /// The gap below a row title, from the 60-point subtitle row view tree.
  static const double subtitleGap = 2.67;

  /// The checkmark bounds from the iOS 27 menu view tree.
  static const Size checkSize = Size(13.33, 12.33);

  /// The mixed-state dash bounds from the iOS 27 menu view tree.
  static const Size mixedSize = Size(12.67, 3.67);

  /// The submenu chevron bounds from the iOS 27 menu view tree.
  static const Size chevronSize = Size(9.33, 12.67);

  /// The selection glyph slot; a layout default, not measured.
  static const double markSlot = 16;

  /// The row image slot; a layout default, not measured.
  static const double imageSlot = 30;

  /// The cell highlight radius; a rendering default, not measured.
  static const double cellHighlightRadius = 12;

  /// The submenu shadow blur; a rendering default, not measured.
  static const double shadowBlur = 6;

  /// The submenu shadow clip extent; a rendering default, not measured.
  static const double shadowReach = 40;

  /// The submenu rim stroke width; a rendering default, not measured.
  static const double cardRimWidth = 2;

  /// The ellipsis glyph box; a rendering default, not measured.
  static const double ellipsisSize = 24;

  /// The ellipsis dot pitch; a rendering default, not measured.
  static const double ellipsisPitch = 7;

  /// The ellipsis dot radius; a rendering default, not measured.
  static const double ellipsisRadius = 2.2;

  /// The smallest painted blur; a rendering default, not measured.
  static const double blurThreshold = 0.05;

  /// The menu scroll indicator width; a rendering default, not measured.
  static const double scrollThickness = 3;

  /// The menu scroll indicator edge inset; a rendering default, not measured.
  static const double scrollInset = 4;

  /// The layout of the inside of the menu.
  final MorphMenuMetrics metrics;

  /// The spring a submenu card grows out of its row on, over the root
  /// menu: one spring for every property (iPhone 16 Pro, iOS 27.0.1,
  /// `_UIContextMenuListView` frames; 0.37 pt rms on the card height).
  final MorphSpring submenuSpring;

  /// Seconds between the release on a submenu row of the root menu and
  /// the start of its card.
  final double submenuDelay;

  /// The spring of a card opened from another card.
  final MorphSpring deeperSubmenuSpring;

  /// Seconds between the release on a submenu row of a card and the
  /// start of the next card.
  final double deeperSubmenuDelay;

  /// The spring a card shrinks back into its row on, critically damped.
  final MorphSpring backSpring;

  /// Seconds between the release on a card's header and the start of the
  /// way back.
  final double backDelay;

  /// Seconds a held finger rests on a submenu row before its card opens
  /// (0.523 and 0.527 s in two device runs).
  final double hoverOpenDelay;

  /// Seconds between the release on a row of a card and its action.
  final double submenuActionDelay;

  /// Seconds between the release on a row of a card and the start of the
  /// whole menu's close: the menu glass of mm-sub-select replays the close
  /// spring at 0.19 pt RMS from 0.031 s after the lift, together with
  /// the container; a release on a root row closes after [dismissDelay].
  final double submenuCloseDelay;

  /// Seconds between the release on a row that keeps the menu open and
  /// its action.
  final double keptActionDelay;

  /// The scale of every card under an open card, per card above it,
  /// about the top center of the menu, including its glass platter
  /// (device list widths: 250, 242.5, 235.225 pt).
  final double parentScale;

  /// The opacity of the rows of a card under an open card.
  final double parentRowOpacity;

  /// The width a card starts at, centered on its row.
  final double cardStartWidth;

  /// How far above its row's center an open card's top sits: the header
  /// centers 5 pt above the row.
  final double cardLead;

  /// The card progress at which a growing card's rows are fully shown:
  /// on the device film the rows read at full contrast while the card is
  /// still small, clipped by its edges rather than faded.
  final double cardRowsFadeIn;

  /// The fraction of its progress at the start of the way back by which
  /// a card's rows have faded out: on film they are gone while the card
  /// is still over half its size. The header is not faded: it turns back
  /// into the row it came from.
  final double cardRowsFadeOut;

  /// The card progress below which the card's platter fades, as the
  /// square root of progress over this value: on film the shrunk card
  /// still shows as a pill around its row at a quarter of its progress
  /// and fades out as it reaches the row.
  final double cardPlatterFade;

  /// The card progress at which a growing card's header title starts to
  /// turn from the row's regular weight to its bold one (film).
  final double cardHeaderBoldStart;

  /// The card progress at which a growing card's header title is bold;
  /// on the way back it is regular again within the first tenth of the
  /// progress (film: bold on one frame, regular on the next).
  final double cardHeaderBoldEnd;

  /// The card progress at which a growing card's chevron has turned from
  /// pointing at the trailing edge to pointing down (film, read by eye).
  final double cardChevronTurn;

  /// The fraction of its progress at the start of the way back at which
  /// a card's chevron points at the trailing edge again (film, read by
  /// eye).
  final double cardChevronBack;

  /// The menu progress at which the top card's rows and platter have
  /// faded out while the whole menu closes: UIKit shrinks the open card
  /// with the menu shape at full contrast and without the content blur
  /// of the root list, fading it only near the end (device film, light
  /// and dark: legible at a fifth of its size).
  final double cardCloseFadeEnd;

  /// The progress span over which opening content approaches the open
  /// card's center. Closing stacks use [cardContainerSpring] instead.
  final double cardCloseCenter;

  /// Exterior shadow fitted from native straight side/bottom profiles:
  /// sigma 16.546 pt, offset 8.109 pt, alpha 0.1188; 0.273 gray RMS.
  /// Flutter's radius-to-sigma conversion gives radius 27.792 pt.
  static const cardShadowRadius = 28.0;

  /// Vertical shadow offset from the same device profile fit.
  static const cardShadowOffset = 8.0;

  /// The closing spring of the submenu lists' container, fitted to
  /// device window bounds at 0.016 pt RMS, independently of the glass.
  final MorphSpring cardContainerSpring;

  /// The container's delay after the close starts, in seconds. The
  /// container and the menu glass start together: in mm-sub-tap the
  /// container fit starts 0.0197 s and the glass 0.0200 s after the
  /// release plus 0.04 s (container records: 9-20 ms, mean 15.1 ms).
  final double cardContainerDelay;

  /// The width the 250 pt list container shrinks to on the device.
  final double cardContainerEndWidth;

  /// The standard deviation, in points, of the blur a card puts over what
  /// lies under it: the edge of the dimmed list under a card shows
  /// through it spread over about 27 points (device screenshots).
  final double cardBlur;

  /// The unlifted card's backdrop displacement, fitted to the native dark
  /// side-edge profile. At 10 pt blur the profile fits zero displacement
  /// at 2.16 gray-level RMS; the regular 60 pt bevel gives 5.77 RMS.
  final double cardDisplacement;

  /// The unlifted card's transmission gamma, fitted to native dark face
  /// levels over the measured large dark face: 55.7 against the native 57
  /// over the root's 32, and 68.1 against 68 over two overlapping lists.
  final double cardTransmissionGamma;

  /// The progress below which a card on its way back is gone: on the
  /// device film the pill it leaves around its row disappears at once
  /// about 0.45 s into the critically damped way back.
  final double cardGone;

  /// The spring the menu grows on when its content gets taller while it
  /// is open (a row added through `updateVisibleMenu`, a deferred group
  /// answered; both fit 0.565 / 0.84 on the device).
  final MorphSpring growSpring;

  /// Seconds between a content change (the action that made it) and the
  /// start of the growth: 0.045 and about 0.03 in two device runs, about
  /// 0.07 after the touch-up that ran the action.
  final double growDelay;

  /// The spring the menu shrinks on when its content gets shorter,
  /// critically damped.
  final MorphSpring shrinkSpring;

  /// Seconds between a content change and the start of the shrink (about
  /// 0.05 after the touch-up that ran the action).
  final double shrinkDelay;

  /// The morph tuning the menu's open and close springs come from.
  final MorphMenuMorphSpec morph;

  /// The spring that opens the menu: the morph's eject spring at its
  /// speed.
  MorphSpring get openSpring => morph.atSpeed(morph.eject);

  /// The spring that closes the menu: the morph's absorb spring at its
  /// speed.
  MorphSpring get closeSpring => morph.atSpeed(morph.absorb);

  /// The width of the open menu.
  final double menuWidth;

  /// The height of one row.
  final double rowHeight;

  /// The padding above the first and below the last row.
  final double verticalPadding;

  /// The corner radius of the open menu.
  final double cornerRadius;

  /// The corner radius the opening shape starts from before it eases to
  /// [cornerRadius]; the shape stays a capsule while it is smaller than
  /// this.
  final double openingRadius;

  /// Seconds the corner radius lags behind the opening.
  final double radiusDelay;

  /// The scale the button shrinks to inside the open menu.
  final double sourceEndScale;

  /// How far the shrinking button travels toward the menu center, as a
  /// fraction of the distance.
  final double sourceTravel;

  /// The blur radius of the button's look per unit of progress.
  final double crossfadeBlur;

  /// Seconds ahead at which the fades of the button's look and of the
  /// content read the progress spring.
  ///
  /// The fades lead the shapes by this much, so they run a little ahead of
  /// the geometry in both directions: the look leaves and the content
  /// arrives early while the menu opens, and the content leaves and the
  /// look returns early while it closes.
  final double fadeLead;

  /// The progress up to which the button's look stays fully opaque.
  final double lookFadeStart;

  /// The progress at which the button's look has faded out.
  ///
  /// The look leaves early: it is gone while the menu shape is still
  /// small, and it comes back only once the closing shape is nearly the
  /// button again.
  final double lookFadeEnd;

  /// How much wider the button's look grows per unit of progress, on top
  /// of the button shape's scale; its height follows the shape alone.
  final double lookStretch;

  /// The progress at which the menu content starts to appear.
  ///
  /// The content is in the drop from the start: its opacity follows the
  /// progress, so it is half there when the drop is half grown.
  final double contentFadeStart;

  /// The progress at which the menu content is fully opaque.
  final double contentFadeEnd;

  /// The progress at which the content of a closing menu has faded out.
  ///
  /// The content leaves faster than it came: a close fades it linearly
  /// from the opacity it had to nothing at this progress, so it is gone
  /// while the shape is still more than half grown. A re-open fades it
  /// back in from where it was to full at [contentFadeEnd].
  final double contentCloseFadeEnd;

  /// How much the content swells past the menu shape's scale with the
  /// shape's kick, per unit of kick relative to the menu height.
  ///
  /// The content rides the menu shape: it is scaled with it, plus this
  /// swell, so it unfolds out of the drop instead of being revealed at
  /// its final size.
  final double contentKickScale;

  /// The blur radius of the content, in logical pixels on screen, at
  /// progress 0; it falls linearly to nothing at progress 1.
  final double contentBlur;

  /// The extra blur radius of the content per unit of the menu shape's
  /// kick relative to the menu height.
  final double contentKickBlur;

  /// Seconds between the release of a tap and the start of the opening:
  /// the mean glass open start of 17 device menu captures, each solved on
  /// the open spring from the recorded glass scale (spread 0.069 - 0.140
  /// s, median 0.085).
  final double tapOpenDelay;

  /// Seconds a held finger needs to open the menu without a release. A
  /// finger that slides beyond [tapSlop] of the source before then never
  /// opens it by holding.
  final double holdDuration;

  /// How far outside the source, in points, a release still counts as a
  /// tap on it: within it a tap opens the menu (or raises
  /// [MorphMenuTapped] when the menu opens only by holding), beyond
  /// it the release cancels and nothing opens. It is the 70 pt
  /// touch-up-inside slop of a glass `UIButton` measured in
  /// glass-button.md, the same as `MorphGlassButtonMotion.highlightSlop`.
  final double tapSlop;

  /// Seconds between a release that dismisses and the start of the
  /// closing: the mean glass close start of 13 device outside dismissals
  /// (nine plain menus, four with a submenu), spread 0.046 - 0.074 s,
  /// each replaying the close spring at 0.2 - 0.4 pt RMS.
  final double dismissDelay;

  /// Seconds between the opening and the start of the closing when the
  /// touch that closes the menu was released before the menu appeared.
  ///
  /// Measured on the device for releases from 0 to 100 ms after the tap
  /// that opened the menu: the close starts 16 ms after the opening
  /// whenever the release came, so the menu always reaches about 0.17 of
  /// its progress.
  final double earlyCloseDelay;

  /// Seconds between the release on a row and its action.
  final double actionDelay;

  /// Seconds between a touch and the start of the button's press growth.
  final double pressDelay;

  /// The time constant, in seconds, over which the closing button lets go
  /// of the scale it had when the menu opened.
  final double sourceRelax;

  /// The spring of the menu shape's kick while the menu opens.
  ///
  /// The kick is a second degree of freedom driven by the progress
  /// spring: while opening, it chases [openKickGain] times the velocity
  /// of the opening spring on this spring.
  final MorphSpring openKickSpring;

  /// The gain of the opening kick, in pixels per unit of progress
  /// velocity, for a menu 146 pixels tall; other heights scale it by
  /// [MorphMenuMotion.kickAmplitude].
  final double openKickGain;

  /// The spring the menu shape's closing kick rings on.
  final MorphSpring closeKickSpring;

  /// The velocity, in pixels per second, a close strikes the menu
  /// shape's kick with, for a menu 146 pixels tall; other heights scale
  /// it by their measured closing amplitude.
  ///
  /// The close kicks the menu shape away from the button, the same way
  /// the opening does; the kick it still carries from the opening rings
  /// out on [closeKickSpring] together with the strike.
  final double closeKickImpulse;

  /// Seconds between the start of a close and its strike on the menu
  /// shape.
  final double closeKickDelay;

  /// The kick, in pixels for a menu 146 pixels tall, past which a close
  /// no longer strikes: the strike shrinks linearly with the kick the
  /// menu shape still carries, so a close during the opening only tops
  /// it up.
  final double closeKickReach;

  /// The spring of the button shape's kick.
  final MorphSpring sourceKickSpring;

  /// The gain of the button shape's kick while the menu closes, in
  /// pixels per unit of progress velocity, for a menu 146 pixels tall
  /// (other heights scale it by their measured amplitude);
  /// the closing progress runs backward, so the button shape is kicked
  /// toward the button's side. The button shape has no kick while the
  /// menu opens.
  final double sourceKickGain;

  /// The smallest gap a centered menu keeps from the safe area's sides;
  /// a menu that would come closer aligns with the button's edge instead.
  final double edgeMargin;

  /// The diameter of the glow under a finger on the menu: the open
  /// menu's `_UIFlexInteraction.LittleGlow` layer is a 160 pt disc drawn
  /// through a vibrant color matrix (iPhone 16 Pro,
  /// test/fixtures/ios27-device/menuglow). Its peak is [flex]'s little
  /// glow opacity (0.5, the device rows peak at 0.49 - 0.5); the menu has
  /// no wash ([flex]'s big glow opacity is 0). It follows the tab bar's
  /// law ([MorphTouchGlowMotion]): a finger dragged 50 pt doubles it at
  /// half the strength, which is how a finger sliding over the rows
  /// lights the whole menu faintly.
  final double glowDiameter;

  /// Seconds after a touch before the glow rises: fitted to eight device
  /// captures (0.011 rms on a drag over the rows, 0.025 at worst).
  final double glowRiseLag;

  /// Seconds the glow rises at least before a lift lets it fall: a tap
  /// on a row lets the rise finish (the fall starts 115 - 170 ms after the
  /// touch, 40 - 87 ms after an 83 ms lift, on seven device captures),
  /// where a long hold falls 26 ms after its lift. 0.1 is the rise
  /// spring's response; the captures' spread around it is not modelled.
  final double glowMinimumLit;

  /// The horizontal inset of the highlight pill from the menu's sides.
  final double highlightInset;

  /// The flex of the open menu under a finger: UIKit's flex interaction
  /// spec for menus, [MorphFlexSpec.menu].
  ///
  /// A finger on the open menu stretches it ([flexTargets]): its
  /// stretch threshold (6000) divides the stretch, its pulse normalization
  /// (8000), pulse points (50 across, 32 along) and drift ratio (0.7) size
  /// the pulse, its movement bounds (0.9 to 1.1) clamp both scales, and
  /// its scale spring (0.6 / 0.5) carries the menu back once the finger
  /// lifts. Read from UIKit, notes private; the numbers agree with the
  /// device's runtime reads (`tool/ios_reference/spec/menu-button.md`).
  ///
  /// The scales and drifts are four channels ([MorphChannel]): while the
  /// finger is down they chase the targets on the spec's tracking spring
  /// (0.15 / 0.5), after the lift they return on its scale spring from
  /// what shows with its velocity, and every changed target pushes them
  /// by the spec's retarget impulse (0.016 s). Read from UIKit, notes
  /// private; the input-only replays of menu_drag_out_test land at 0.09 -
  /// 0.15 pt rms while the finger is down and 0.15 - 0.17 after the lifts.
  final MorphFlexSpec flex;

  /// The points a finger moving inside the open menu adds to the stretch
  /// per menu size it travels: inside, the menu moves `40 / 6000` of the
  /// finger's travel along an axis, beyond its edge `W / 6000` (or
  /// `H / 6000`) per point further out ([flexTargets]).
  ///
  /// Read from UIKit, notes private; the replay of
  /// `ios27-device/menu/drag-out-flex.jsonl` checks it with no fitted
  /// constant (menu_drag_out_test).
  final double flexInBoundsPoints;

  /// The spring of the flex's pulse channel: it chases the finger's
  /// vertical travel, and its velocity, in points per second of the
  /// channel's own clock, sizes the pulse ([flexTargets]).
  ///
  /// Read from UIKit (response 0.574, damping 0.548, a tracking spring),
  /// notes private. How the channel steps it is [flexPulseRate] and
  /// [flexPulseRetargetStep].
  final MorphSpring flexPulseSpring;

  /// How many times a second the pulse channel steps [flexPulseSpring]
  /// while a finger is on the open menu.
  ///
  /// Observed live on iOS 27.0.1 (iPhone 16 Pro at 120 Hz, the probe's
  /// animation tap, `ios27-device/menu/drag-out-animation-tap.jsonl`): the
  /// channel publishes every fourth frame. APPROXIMATION: the rule UIKit
  /// uses to schedule the channel from touches alone is not frozen; this
  /// fixed rate, counted from the touch-down, is the observed one at the
  /// device's refresh rate and is not known for other rates or Reduce
  /// Motion.
  final double flexPulseRate;

  /// The spring time, in seconds, one channel step advances
  /// [flexPulseSpring] by when the finger moved since the previous step;
  /// a step with the finger held advances it by the time that passed.
  ///
  /// Observed live on iOS 27.0.1 with [flexPulseRate]: a retarget advances
  /// the spring by one 1/60 s step although 1/30 s passed, so while the
  /// finger moves the spring's clock runs at half the wall time and its
  /// velocity, which the pulse reads, runs twice the rate its value
  /// changes at. One step reproduces UIKit's recorded value and velocity
  /// to 0.01 pt and 0.1 pt/s on 104 of 105 retargets and all 61 held
  /// steps of the tap capture (menu-button.md). APPROXIMATION like
  /// [flexPulseRate].
  final double flexPulseRetargetStep;

  /// Seconds from a touch's time stamp to the open menu's flex answering
  /// it: UIKit delivers the touch to its gesture after about 15 ms and
  /// shows the result on the next 120 Hz frame.
  ///
  /// Measured in `ios27-device/menu/drag-out-flex.jsonl` and
  /// `drag-out-animation-tap.jsonl` (touch stamp to the flex's
  /// translation: 14.4 and 15.9 ms median; the list's frame follows one
  /// frame later).
  final double flexDelay;

  /// The stretch UIKit's open menu takes under a finger, as the scale of
  /// its width and height and the drift of its center across and of its
  /// edge facing the button along the vertical.
  ///
  /// [translation] is the finger's travel from its touch-down,
  /// [inBounds] the travel of the finger clamped into the menu's bounds,
  /// [size] the menu's size W x H at rest, [velocity] the pulse channel's
  /// velocity ([flexPulseSpring]) and [side] +1 for a menu below its
  /// button, -1 above it. Along x (y likewise with H):
  ///
  /// ```
  /// kx = (|t.x| - |it.x| + 40 |it.x| / W) / 6000   (0 when t.x is 0)
  /// sx = 1 + kx - ky, sy = 1 - kx + ky
  /// dx = sign(t.x) kx W, dy = sign(t.y) ky H
  /// p = velocity side / 8000
  /// sx *= 1 - 50 p / W, sy *= 1 + 32 p / H, dy += side 0.7 32 p
  /// sx, sy clamped to [0.9, 1.1]
  /// ```
  ///
  /// Read from UIKit, notes private. Applied to UIKit's own recorded
  /// inputs it reproduces the recorded menu frames to 0.25 pt rms over
  /// the edges (`lab/menu_flex_model.py`).
  ({double scaleX, double scaleY, double driftX, double driftY}) flexTargets({
    required Offset translation,
    required Offset inBounds,
    required Size size,
    required double velocity,
    required double side,
  }) => MorphFlexInteraction.menuTargets(
    spec: flex,
    inBoundsPoints: flexInBoundsPoints,
    translation: translation,
    inBounds: inBounds,
    size: size,
    velocity: velocity,
    side: side,
  );

  /// The largest fusion radius: the standard deviation, in pixels, of
  /// the Gaussian that blurs the distance field of the two shapes.
  ///
  /// Read from the morph container's `gaussianRadius` on the device
  /// (iOS 27.0.1, iPhone 16 Pro): the container is one SDF layer with
  /// smoothness 0, so the shapes are joined only by this blur, which
  /// rises to 20 at every open and close and falls back to 0. A blur of
  /// this standard deviation reproduces the filmed silhouettes, neck
  /// included, of a ten-row menu closing into a bottom button (fit 0.9
  /// to 1.2 times the logged radius; 1.1 pt rms in row width).
  final double fusionRadius;

  /// The amplitude of the closing fusion envelope, in pixels; the
  /// envelope peaks at 19.7 because its fall starts before its rise
  /// ends. Fitted to the logged `gaussianRadius` of two closes (0.13 pt
  /// rms).
  final double fusionCloseAmplitude;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// opens. Fitted to two logged opens (0.4 pt rms, the fit's spread
  /// 0.016 to 0.017).
  final double fusionOpenRise;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// closes. Fitted to two logged closes.
  final double fusionCloseRise;

  /// Seconds after an open at which the fusion starts to fall.
  final double fusionOpenHold;

  /// Seconds after a close at which the fusion starts to fall.
  final double fusionCloseHold;

  /// The spring the fusion falls on, critically damped: fitted free to
  /// 0.424 to 0.433 s in both directions from the device's logged
  /// Gaussian radius. This envelope fit is independent of
  /// [MorphMenuMorphSpec.atSpeed]; that method scales the progress springs.
  final MorphSpring fusionSpring;

  /// The fusion radius under which the container drops its blur: the
  /// device's logged radius jumps from 0.18 to 0.
  final double fusionCutoff;

  /// The fusion envelope [t] seconds after an open, or a close when
  /// [opening] is false, before it is limited to [fusionRadius].
  ///
  /// It rises as `1 - exp(-t / rise)` and, after the hold, falls as a
  /// critically damped spring released from rest.
  double fusionEnvelope(double t, {required bool opening}) {
    if (t <= 0) return 0;
    final rise = opening ? fusionOpenRise : fusionCloseRise;
    final hold = opening ? fusionOpenHold : fusionCloseHold;
    final amplitude = opening ? fusionRadius : fusionCloseAmplitude;
    final fall = math.max(t - hold, 0.0);
    final w = 2 * math.pi / fusionSpring.response;
    return amplitude *
        (1 - math.exp(-t / rise)) *
        (1 + w * fall) *
        math.exp(-w * fall);
  }

  /// Whether the fusion envelope started [t] seconds ago has fallen
  /// under [fusionCutoff] for good.
  bool fusionEnded(double t, {required bool opening}) =>
      t > (opening ? fusionOpenHold : fusionCloseHold) &&
      fusionEnvelope(t, opening: opening) < fusionCutoff;

  /// The height of a menu with [rows] rows.
  double menuHeight(int rows) => 2 * verticalPadding + rowHeight * rows;

  /// The glow a finger raises on the open menu ([glowDiameter]).
  MorphTouchGlowMotion touchGlow() => MorphTouchGlowMotion(
    washPeak: flex.bigGlowOpacity,
    spotPeak: flex.littleGlowOpacity,
    diameter: glowDiameter,
    riseLag: glowRiseLag,
    minimumLit: glowMinimumLit,
  );

  /// The measured iOS 27 menu.
  static const standard = MorphMenuTuning();

  /// The measured iOS 27 context menu: the menu of [standard] on the
  /// morph of [MorphMenuMorphSpec.context].
  static const context = MorphMenuTuning(morph: MorphMenuMorphSpec.context);
}

/// Where a context menu stands and what it grows out of: UIKit's context
/// menu attaches to the lifted preview of the held view and grows out of a
/// blob at the held view's center, on glass of its own.
///
/// The menu stands [gap] below the [preview] when it fits there, above it
/// otherwise (its entries reversed, as for a menu opening upward), and
/// when it fits on neither side the preview and the menu shift together
/// until the menu fits below; [MorphMenuMotion.previewShift] is that
/// shift. Across, the menu centers on the preview when that keeps
/// [MorphMenuTuning.edgeMargin] from the safe area and aligns with the
/// preview's nearer edge otherwise, as a button menu does.
class MorphMenuAttachment {
  /// Creates an attachment to the lifted [preview] of the view [held].
  const MorphMenuAttachment({
    required this.held,
    required this.preview,
    this.accessory = 0,
    this.gap = measuredGap,
    this.margin = MorphMenuTuning.contextMargin,
  });

  /// The held view's frame at rest, in the menu's coordinates; the menu
  /// grows out of its center.
  final Rect held;

  /// The lifted preview's frame before any shift, in the menu's
  /// coordinates.
  final Rect preview;

  /// The extent above the preview taken by an accessory and its gap, which
  /// shifts with the preview and must stay inside the safe area too.
  final double accessory;

  /// The space between the preview and the menu.
  final double gap;

  /// The distance the preview and the menu keep from the safe area's edges.
  final double margin;

  /// Space UIKit leaves between an open preview and its menu, in points
  /// (iPhone 16 Pro, iOS 27).
  static const double measuredGap = 16;

  /// The share of the held view a context menu grows out of.
  static const double measuredBlobScale = 0.4;

  /// The blob a context menu of [menuHeight] grows out of and retracts into
  /// for a held view of [held] size, centered on the held view: 0.4 of the
  /// held view's shorter side tall and 0.4 of its width, at most 0.4 of the
  /// menu's height, wide.
  ///
  /// Fitted to the menu morph layer at its smallest on an iPhone 16 Pro
  /// (iOS 27, `context_menu/growth.json`, within 0.3 pt): 60 x 40 -> 24 x
  /// 16, 120 x 80 -> 48 x 32, 80 x 160 -> 32 x 32 and 300 x 200 -> 83.2 x
  /// 80 under a 208-point menu (the only menu height recorded, so the
  /// width cap is the measured one for that height).
  static Size blobSize(Size held, double menuHeight) => Size(
    measuredBlobScale * math.min(held.width, menuHeight),
    measuredBlobScale * held.shortestSide,
  );

  @override
  bool operator ==(Object other) =>
      other is MorphMenuAttachment &&
      other.held == held &&
      other.preview == preview &&
      other.accessory == accessory &&
      other.gap == gap &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(held, preview, accessory, gap, margin);
}

/// One of the two shapes a menu morph is drawn from.
///
/// [rect] is the visible frame, already scaled; [localSize] is the frame
/// before the uniform [scale], which is the size content is laid out in.
class MorphMenuBlob {
  /// Creates a blob.
  const MorphMenuBlob({
    required this.rect,
    required this.radius,
    required this.scale,
    required this.localSize,
  });

  /// The visible frame.
  final Rect rect;

  /// The visible corner radius.
  final double radius;

  /// The uniform scale from [localSize] to [rect].
  final double scale;

  /// The frame before scaling.
  final Size localSize;

  /// The visible shape as a rounded rectangle.
  RRect get rrect => RRect.fromRectAndRadius(rect, Radius.circular(radius));
}

/// The progress of a menu morph: 0 is the button, 1 the menu.
///
/// [MorphMenuMotion] reads it and asks it to open and to close; it never
/// integrates the progress itself. [MorphMenuProgress.spring] is the
/// measured spring evaluated at explicit times, which makes the motion a
/// pure function of time; a widget wraps it to send the engine flight
/// that carries the menu the same way.
abstract class MorphMenuProgress {
  /// Creates a progress.
  MorphMenuProgress();

  /// The measured progress spring of [tuning], evaluated in closed form:
  /// it opens on [MorphMenuTuning.openSpring] and closes on
  /// [MorphMenuTuning.closeSpring], and a reversal carries the velocity.
  factory MorphMenuProgress.spring(MorphMenuTuning tuning) = _SpringProgress;

  /// The progress at time [t].
  double valueAt(double t);

  /// Whether the progress's remaining swing stays below [rest] from time
  /// [t] on.
  bool restsWithin(double t, double rest);

  /// Sends the progress toward 1 from time [t].
  void open(double t);

  /// Sends the progress toward 0 from time [t].
  void close(double t);
}

class _SpringProgress extends MorphMenuProgress {
  _SpringProgress(this.tuning)
    : _spring = MorphSpringState(tuning.openSpring, 0);

  final MorphMenuTuning tuning;
  final MorphSpringState _spring;

  @override
  double valueAt(double t) => _spring.value(t);

  @override
  bool restsWithin(double t, double rest) => _spring.isWithin(t, rest);

  @override
  void open(double t) => _spring.retarget(t, 1, spring: tuning.openSpring);

  @override
  void close(double t) => _spring.retarget(t, 0, spring: tuning.closeSpring);
}

enum _Phase { idle, opening, closing }

/// The stretch of the open menu: its width and height scales and the
/// drifts of its center across and of its edge facing the button.
typedef _Deformation = ({
  double scaleX,
  double scaleY,
  double driftX,
  double driftY,
});

class _Pointer {
  _Pointer({
    required this.fromButton,
    required this.position,
    required this.startedInMenu,
  });

  final bool fromButton;
  final bool startedInMenu;
  Offset position;
  bool openedByHold = false;
  bool holdForfeited = false;
  bool scrolled = false;
  bool leftButton = false;
}

/// A finger flexing the open menu, as the flex sees it
/// [MorphMenuTuning.flexDelay] after the touches.
class _FlexTouch {
  _FlexTouch(this.origin, this.start) : position = origin;

  /// Where the finger touched down.
  final Offset origin;

  /// When the flex saw the touch-down; the pulse channel steps from here.
  final double start;

  /// Where the finger is.
  Offset position;

  /// When the pulse channel steps next, or null while it rests.
  double? nextStep;
}

/// A damped spring driven by an input, integrated from samples.
class _DrivenKick {
  double value = 0;
  double velocity = 0;

  bool get isAtRest =>
      value.abs() < MorphMenuTuning.kickRestValue &&
      velocity.abs() < MorphMenuTuning.kickRestVelocity;

  void reset() {
    value = 0;
    velocity = 0;
  }

  /// Integrates from time [from] to [to] on [spring], chasing [input]
  /// (zero when null).
  void step(
    double from,
    double to,
    MorphSpring spring,
    double Function(double t)? input, {
    bool Function(double t)? inputAtRest,
  }) {
    final steps = math.max(
      1,
      ((to - from) / MorphMenuTuning.kickIntegrationStep).ceil(),
    );
    final h = (to - from) / steps;
    final k = spring.stiffness;
    final c = spring.damping;
    for (var i = 0; i < steps; i++) {
      final sample = from + i * h;
      if (to - sample > MorphMenuTuning.kickSkipSpan &&
          isAtRest &&
          (inputAtRest?.call(sample) ?? input == null)) {
        return;
      }
      final target = input == null ? 0.0 : input(from + (i + 0.5) * h);
      velocity += (k * (target - value) - c * velocity) * h;
      value += velocity * h;
    }
  }
}

/// A submenu card stacked over the menu.
class _Card {
  _Card({
    required this.layout,
    required this.source,
    required this.from,
    required this.top,
    required this.progress,
  });

  MorphMenuLayout layout;

  /// The index of the target in the card below that opened this one.
  final int source;

  /// The frame the card grows out of, in content coordinates.
  final Rect from;

  /// The top of the open card, in content coordinates.
  double top;

  final MorphSpringState progress;
  bool backing = false;

  /// The progress the card had when it started back to its row.
  double backFrom = 1;
}

/// A fade anchored on the progress at its start: [from] at [anchor],
/// [to] at [end], linear in between; every reversal starts a new one
/// from the current value, so the opacity never jumps.
class _Fade {
  double from = 1;
  double to = 1;
  double anchor = 0;
  double end = 1;

  void start({
    required double from,
    required double to,
    required double anchor,
    required double end,
  }) {
    this.from = from;
    this.to = to;
    this.anchor = anchor;
    this.end = end;
  }

  double at(double p) {
    final span = anchor - end;
    if (span.abs() < 1e-6) return to;
    final f = ((p - end) / span).clamp(0.0, 1.0);
    return to + (from - to) * f;
  }
}

/// One card of a menu as drawn at the time the motion was last advanced
/// to: the root list is card 0, each open submenu stacks one more.
class MorphMenuCard {
  /// Creates a card.
  const MorphMenuCard({
    required this.layout,
    required this.rect,
    required this.scale,
    required this.rowOpacity,
    required this.progress,
    this.contentTop = 0,
    this.rowsOpacity = 1,
    this.platterOpacity = 1,
    this.headerBold = 1,
    this.chevronTurn = 1,
    this.closeOpacity = 1,
    this.backing = false,
    this.source,
  });

  /// The content of the card.
  final MorphMenuLayout layout;

  /// The frame of the card in the menu's content coordinates, before
  /// [scale].
  final Rect rect;

  /// The scale of the card about the top center of the menu content.
  final double scale;

  /// The opacity of the card's rows; cards under an open card dim.
  final double rowOpacity;

  /// How far the card has grown out of its row, 1 for the root list.
  final double progress;

  /// The top of the card's content in the coordinates of [rect]: the
  /// content rides the row the card grew out of, so the header lies on
  /// that row while the card is small and the card hands it back to the
  /// row without a jump.
  final double contentTop;

  /// The opacity of the card's rows other than its header.
  final double rowsOpacity;

  /// The opacity of the card's platter.
  final double platterOpacity;

  /// How bold the header title is, 0 the row's weight and 1 the header's.
  final double headerBold;

  /// How far the header chevron has turned, 0 pointing at the trailing
  /// edge like the row's and 1 pointing down.
  final double chevronTurn;

  /// The opacity of the whole card while the menu closes, 1 otherwise.
  final double closeOpacity;

  /// Whether the card is on its way back into its row.
  final bool backing;

  /// The target of the card below that opened this one, null for the
  /// root list. Its header stands in for that row while the card shows.
  final int? source;
}

/// The motion of a glass button turning into its menu and back: a pure
/// function of the touches it is fed, the progress it reads and the time
/// it is advanced to.
///
/// One progress drives two shapes. The menu shape grows out of the
/// button: a square of the menu's width scaled down to half the button's
/// height that stretches to the menu's height while it scales up, rides
/// from the button's center to the menu's center and dips past it on a
/// vertical kick. The button shape shrinks to a quarter and slides a
/// quarter of the way toward the menu. The two are drawn as one union
/// without a neck. The button's glyph rides the button shape, widening as
/// it blurs out early; the menu content rides the menu shape at the
/// shape's scale, swelling a little with its kick, and fades in with the
/// progress, so the menu unfolds out of the drop.
///
/// The kicks are a second degree of freedom per shape, driven by the
/// progress spring: while the menu opens, the menu shape's kick chases
/// the velocity of the opening spring, played from the moment the menu
/// started opening, on [MorphMenuTuning.openKickSpring]; a close strikes
/// it away from the button ([MorphMenuTuning.closeKickImpulse]) and it
/// rings out on [MorphMenuTuning.closeKickSpring], and the button
/// shape's kick chases the velocity of the closing spring. Each kick is
/// integrated over every [advance], so it carries through every
/// reversal.
///
/// The content is a [MorphMenuLayout]: uniform rows for a plain
/// [itemCount], or whatever the `layout` builder lays out. A submenu
/// target opens a card that grows out of its row over the menu
/// ([MorphMenuTuning.submenuSpring]), the cards under it shrink to
/// [MorphMenuTuning.parentScale] and dim, and the menu grows to cover the
/// card; a card's header, or a touch beside it, sends it back. Content
/// that changes while the menu is open ([updateLayout]) resizes the menu
/// on [MorphMenuTuning.growSpring] or [MorphMenuTuning.shrinkSpring].
/// Content taller than [MorphMenuMetrics.maxHeight] or the safe area is
/// cut to it and scrolls by [scrollOffset].
///
/// Feed pointer events in the coordinate space of [bounds] with their
/// timestamps, call [advance] with the frame time, then read [menuBlob],
/// [buttonBlob] and the crossfade values. A tap opens on release, a hold
/// opens after [MorphMenuTuning.holdDuration]; a release outside the
/// menu closes it and a release on a target chooses it. The finger that
/// opened the menu by holding chooses only after it has left the button:
/// released on the button it leaves the menu open, as UIKit does.
///
/// What a host acts on comes out as [MorphMenuEvent]s ([drainEvents]). A
/// release that closes the menu raises [MorphMenuCloseRequested] for its
/// host to answer before the menu starts closing ([advanceToRequest]); a
/// motion advanced with [advance] closes on its own at that time.
class MorphMenuMotion
    with MorphMotionEvents<MorphMenuEvent>
    implements MorphMotion<MorphMenuEvent> {
  /// Creates the motion of the button at [button] whose menu is [layout]
  /// (uniform rows of [itemCount] when null), inside [bounds] minus the
  /// safe-area [padding].
  ///
  /// [layout] is asked for the content in the order it shows: reversed
  /// when the menu opens upward. [sourceHeight] is the height of the view
  /// the menu shape starts from; it defaults to the button's height and
  /// differs for bar buttons, whose glass platter is larger than the
  /// button. [sourceRadius] is the corner radius of the source at rest;
  /// null keeps it a capsule. [progress] defaults to
  /// [MorphMenuProgress.spring] of [tuning].
  ///
  /// With an [attachment] the menu is a context menu: it stands beside the
  /// attachment's preview and grows out of the blob at the held view's
  /// center ([MorphMenuAttachment.blobSize]) instead of out of [button],
  /// along a straight line from the blob to its frame on the progress,
  /// and no source shape is drawn ([drawsSource]). [button] is then the
  /// held view's frame, which a finger holding the menu open leaves to
  /// choose.
  MorphMenuMotion({
    required Rect button,
    this._itemCount = 0,
    required this._bounds,
    MorphMenuLayout Function({required bool reversed})? layout,
    this._padding = EdgeInsets.zero,
    double? sourceHeight,
    this._sourceRadius,
    this.tuning = MorphMenuTuning.standard,
    MorphMenuProgress? progress,
    this._attachment,
  }) : _button = button,
       _layoutFor = layout,
       _sourceHeight = sourceHeight ?? button.height,
       _progress = progress ?? MorphMenuProgress.spring(tuning) {
    _radius = MorphSpringState(tuning.openSpring, 0);
    _press = MorphFlexInteraction(
      size: button.size,
      stretches: false,
      activationDelay: tuning.pressDelay,
      timeline: _timeline,
    );
    MorphChannel channel(double value) => MorphChannel(
      value,
      spring: tuning.flex.scaleSpring,
      trackingSpring: tuning.flex.trackingSpring,
      retargetImpulse: tuning.flex.retargetImpulse,
    );
    _flexScaleX = channel(1);
    _flexScaleY = channel(1);
    _flexDriftX = channel(0);
    _flexDriftY = channel(0);
    _pulse = MorphChannel.stepped(
      0,
      spring: tuning.flexPulseSpring,
      retargetStep: tuning.flexPulseRetargetStep,
    );
    _root = _build(reversed: false);
    _rootHeight = MorphSpringState(tuning.growSpring, _visibleRoot(_root));
    _cardContainer = MorphSpringState(tuning.cardContainerSpring, 1);
    _place(1);
  }

  /// The measured behavior this motion reproduces.
  final MorphMenuTuning tuning;

  final MorphMenuProgress _progress;
  final MorphMenuLayout Function({required bool reversed})? _layoutFor;

  Rect _button;
  MorphMenuAttachment? _attachment;
  Offset _shift = Offset.zero;
  int _itemCount;
  Size _bounds;
  EdgeInsets _padding;
  double _sourceHeight;
  double? _sourceRadius;

  late final MorphSpringState _radius;
  late final MorphFlexInteraction _press;
  late final MorphChannel _flexScaleX;
  late final MorphChannel _flexScaleY;
  late final MorphChannel _flexDriftX;
  late final MorphChannel _flexDriftY;
  late final MorphChannel _pulse;
  _FlexTouch? _flexTouch;
  int _flexGeneration = 0;
  late MorphSpringState _rootHeight;
  late final MorphSpringState _cardContainer;
  bool _cardContainerActive = false;

  late MorphMenuLayout _root;
  bool _reversed = false;
  final List<_Card> _cards = [];
  final _Fade _cardFade = _Fade();
  int _resizeGeneration = 0;
  int _resizePending = -1;
  double _resizeTo = 0;
  bool _resizeGrows = false;
  int _dwellGeneration = 0;

  final _DrivenKick _menuKick = _DrivenKick();
  final _DrivenKick _buttonKick = _DrivenKick();
  MorphSpringState? _openReference;
  MorphSpringState? _closeReference;

  // A kick skips a long quiet span only while its input, the reference's
  // velocity, has died out: the rule the recorded kicks were fitted with.
  static bool Function(double t) _referenceRests(MorphSpringState spring) =>
      (double t) =>
          (spring.value(t) - spring.target).abs() < 0.01 &&
          spring.velocity(t).abs() < 0.1;
  final List<({double start, bool opening})> _fusions = [];
  final MorphMenuFusion _fusion = MorphMenuFusion();
  double _sampleTime = double.negativeInfinity;

  _Phase _phase = _Phase.idle;
  double _sourceScale = 1;
  Rect _pressed = Rect.zero;
  double _left = 0;
  double _anchor = 0;
  bool _down = true;
  double _amplitude = 1;
  double _closeAmplitude = 1;
  double _sourceAmplitude = 1;
  double _radiusFrom = 0;
  double _closeRadius = 0;
  double _closeProgress = 1;
  double _closeStart = 0;
  double _closeSource = 1;
  double _closeLive = 1;
  double _fadeFrom = 0;
  double _fadeTo = 1;
  double _fadeAnchor = 0;
  double _fadeEnd = 1;
  int _openGeneration = 0;
  bool _openPending = false;
  ({double t, Offset position})? _earlyRelease;
  _Pointer? _pointer;
  int? _highlighted;
  int _highlightCard = 0;
  late final MorphTouchGlowMotion _touchGlow = tuning.touchGlow();

  final MorphTimeline _timeline = MorphTimeline(now: 0);
  MorphMenuCloseRequested? _request;
  bool _yields = false;

  /// Whether a tap on the button opens the menu, as a menu that is the
  /// button's primary action; false opens it only by holding, and a tap
  /// released on the button, or within [MorphMenuTuning.tapSlop] of it,
  /// raises [MorphMenuTapped] instead.
  bool opensOnTap = true;

  /// Lays out the card opened by a submenu target; no card opens while
  /// it is null or returns null.
  MorphMenuLayout? Function(MorphMenuTarget target)? submenuLayout;

  /// Whether choosing a target closes the menu: null leaves it to the
  /// target ([MorphMenuTarget.keepsOpen]), true always closes, false
  /// never does (SwiftUI's `menuActionDismissBehavior`).
  bool? dismissOnSelect;

  /// How far the root list is scrolled, in points.
  ///
  /// Only content taller than the menu scrolls; the host keeps this in
  /// step with its scroll view so touches find the rows under them.
  double scrollOffset = 0;

  double get _now => _peekTime ?? _timeline.now;

  double? _peekTime;
  double? _prefetchedFrom;
  bool _prefetchField = false;

  /// The time of the latest frame on the source clock's frame grid
  /// (`MorphClock.frameTime`); the coming frames follow it at multiples
  /// of [framePeriod].
  double frameTime = 0;

  /// The period of the source clock's frame grid
  /// (`MorphClock.framePeriod`), or null while it has seen no steady
  /// frames; the motion fuses nothing ahead without it.
  double? framePeriod;

  @override
  double get time => _now;

  /// The layout frame of the button, or of the held view of a context
  /// menu.
  Rect get button => _button;

  /// Where a context menu stands, or null for a menu that grows out of its
  /// button.
  MorphMenuAttachment? get attachment => _attachment;

  /// How far a context menu moved its preview to fit the menu inside the
  /// safe area; zero for a menu without an [attachment].
  Offset get previewShift => _shift;

  /// Whether the menu draws a source shape it grows out of: the button
  /// shape, which a context menu has none of.
  bool get drawsSource => _attachment == null;

  /// The blob a context menu grows out of, centered on the held view.
  Rect get _blob {
    final size = MorphMenuAttachment.blobSize(_button.size, _menu.height);
    return Rect.fromCenter(
      center: _button.center,
      width: size.width,
      height: size.height,
    );
  }

  /// The area a finger that opened the menu by holding leaves to choose:
  /// the button, or a context menu's lifted preview.
  Rect get _holdArea {
    final attachment = _attachment;
    if (attachment == null) return _button;
    return attachment.preview.shift(_shift);
  }

  /// The number of rows of a uniform menu.
  int get itemCount => _itemCount;

  /// The bounds the menu is placed in.
  Size get bounds => _bounds;

  /// The content of the root list, in the order it shows.
  MorphMenuLayout get layout => _root;

  /// Whether the content shows in reverse order, as a menu opening upward
  /// does.
  bool get reversed => _reversed;

  /// The height of the root list's content; more than the menu's when it
  /// scrolls.
  double get contentHeight => _root.height;

  /// The height of the menu's visible root list.
  double get visibleRootHeight => _rootHeight.value(_now);

  MorphMenuLayout _build({required bool reversed}) {
    final builder = _layoutFor;
    if (builder != null) return builder(reversed: reversed);
    return MorphMenuLayout.uniform(
      _itemCount,
      width: tuning.menuWidth,
      rowHeight: tuning.rowHeight,
      inset: tuning.verticalPadding,
      reversed: reversed,
    );
  }

  double get _cap => math.max(
    tuning.rowHeight + 2 * tuning.verticalPadding,
    math.min(
      tuning.metrics.maxHeight,
      _bounds.height - _padding.top - _padding.bottom,
    ),
  );

  double _visibleRoot(MorphMenuLayout layout) => math.min(layout.height, _cap);

  /// Updates the geometry; ignored while the menu is shown.
  void relayout({
    required Rect button,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    int? itemCount,
    double? sourceHeight,
    double? sourceRadius,
    MorphMenuAttachment? attachment,
  }) {
    _revision++;
    if (_phase != _Phase.idle) return;
    _sourceRadius = sourceRadius;
    _attachment = attachment;
    _button = button;
    _bounds = bounds;
    _padding = padding;
    _itemCount = itemCount ?? _itemCount;
    _sourceHeight = sourceHeight ?? button.height;
    _press.size = button.size;
    _root = _build(reversed: _reversed);
    _rootHeight.snap(_now, _visibleRoot(_root));
    _place(_press.scale(_now));
  }

  /// Lays the content out again at time [t], as after a change of the
  /// entries while the menu is open.
  ///
  /// With [animate] the menu grows on [MorphMenuTuning.growSpring] or
  /// shrinks on [MorphMenuTuning.shrinkSpring] after their delays, the
  /// way an open UIKit menu takes `updateVisibleMenu`; otherwise the new
  /// height applies at once. A change in the same direction while a
  /// resize waits for its delay joins it: the resize takes the latest
  /// height, so content that changes every frame still resizes the menu.
  /// Open cards are laid out again from the targets that opened them; a
  /// card whose target is gone closes.
  void updateLayout(double t, {bool animate = true}) {
    _revision++;
    advance(t);
    _root = _build(reversed: _reversed);
    for (var i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final parent = i == 0 ? _root : _cards[i - 1].layout;
      final source = card.source < parent.targets.length
          ? parent.targets[card.source]
          : null;
      final layout = source == null || source.kind != .submenu
          ? null
          : submenuLayout?.call(source);
      if (layout == null) {
        _cards.removeRange(i, _cards.length);
        _setHighlight(null, 0);
        break;
      }
      card.layout = layout;
      card.top = _clampCardTop(card.top, layout.height);
    }
    if (_highlighted != null) {
      final targets = _layoutOf(_highlightCard).targets;
      if (_highlighted! >= targets.length) _setHighlight(null, 0);
    }
    final height = _visibleRoot(_root);
    if (_phase == _Phase.idle || !animate) {
      _resizeGeneration++;
      _rootHeight.snap(t, height);
      if (_phase == _Phase.idle) _place(_press.scale(t));
      return;
    }
    final unchanged = (height - _rootHeight.target).abs() < 1e-6;
    final grow = height > _rootHeight.target;
    if (_resizePending == _resizeGeneration) {
      if (unchanged) {
        _resizeGeneration++;
        return;
      }
      if (grow == _resizeGrows) {
        _resizeTo = height;
        return;
      }
    }
    if (unchanged) return;
    final generation = ++_resizeGeneration;
    _resizePending = generation;
    _resizeTo = height;
    _resizeGrows = grow;
    _timeline.at(t + (grow ? tuning.growDelay : tuning.shrinkDelay), (
      double s,
    ) {
      if (generation != _resizeGeneration) return;
      _resizePending = -1;
      _rootHeight.retarget(
        s,
        _resizeTo,
        spring: grow ? tuning.growSpring : tuning.shrinkSpring,
      );
    });
  }

  MorphMenuLayout _layoutOf(int card) =>
      card == 0 || card > _cards.length ? _root : _cards[card - 1].layout;

  /// The progress of the morph at the time the motion was last advanced
  /// to, read from its [MorphMenuProgress]: 0 is the button, 1 the menu.
  ///
  /// The opening spring overshoots, so the value briefly exceeds 1, and
  /// the closing one briefly dips below 0.
  double get progress => _progress.valueAt(_now);

  /// Whether the menu is on screen, opening, open or closing.
  bool get isPresented => _phase != _Phase.idle;

  /// Whether the menu is opening or open.
  bool get isOpen => _phase == _Phase.opening;

  /// Whether the menu is closing.
  bool get isClosing => _phase == _Phase.closing;

  /// Whether closing cards use the carrier's matched glass copy.
  /// In mm-sub-tap the card's original SDF element leaves its material
  /// group 12 ms after the logical close, at the morph's kick; the rows
  /// and the matched glass copy remain in the shrinking carrier.
  bool get cardGlassTransferred =>
      isClosing &&
      _cards.isNotEmpty &&
      _now >= _closeStart + tuning.closeKickDelay;

  /// Visibility of the matched card material during a whole-stack close.
  /// mm-sub-tap's copied key-fill layer follows the carrier spring, with
  /// opacity equal to (window width - 50) / 200 at 120 Hz.
  double get cardMaterialOpacity =>
      cardGlassTransferred ? _cardContainer.value(_now).clamp(0.0, 1.0) : 1;

  /// Whether a tap's release has scheduled the opening and the menu is
  /// not on its way yet.
  ///
  /// A touch that lands anywhere in this window belongs to the menu, as
  /// on iOS: it is held until the menu opens, and a release that came
  /// before then is applied at the opening - on a row it selects the row,
  /// outside the menu it closes the menu again
  /// [MorphMenuTuning.earlyCloseDelay] after the opening.
  bool get isOpenPending => _openPending;

  /// Whether the menu is not shown yet but a touch may open it: a finger
  /// held on the button, or a tap's opening pending.
  bool get isArming =>
      _phase == _Phase.idle &&
      (_openPending || (_pointer?.fromButton ?? false));

  /// The frame of the open menu at the time the motion was last advanced
  /// to; its height follows resizes and submenu cards.
  Rect get menuRect => _frameAt(_now);

  Rect get _menu => _frameAt(_now);

  /// The swing at which a card's progress and the card container rest.
  /// NEAR: a card lands by up to 0.001 of its travel (0.25 pt on a 250 pt
  /// menu), looser than [MorphRest.length]; resting at 0.1 pt adds five
  /// frames of captured glass to the menu-card perf scene.
  static const double _cardRest = 1e-3;

  /// The visible rest ([MorphRest], NEAR) of the progresses that grow the
  /// menu, its corners and its cards out of the button: a swing below it
  /// moves no edge of the open menu by [MorphRest.length] and changes no
  /// fade by [MorphRest.opacity].
  double get _progressRest => math.min(
    MorphRest.opacity,
    MorphRest.scale(math.max(tuning.menuWidth, _rootHeight.target)),
  );

  Rect _frameAt(double t) {
    final h = _rootHeight.value(t) + _cardsExtra(t);
    var top = _down ? _anchor : _anchor - h;
    final maxBottom = _bounds.height - _padding.bottom;
    top = math.max(_padding.top, math.min(top, maxBottom - h));
    return Rect.fromLTWH(_left, top, tuning.menuWidth, h);
  }

  double _cardsExtra(double t) {
    var reach = _rootHeight.target;
    var extra = 0.0;
    for (final card in _cards) {
      final bottom = card.top + math.min(card.layout.height, _cap);
      if (bottom > reach) {
        extra += (bottom - reach) * card.progress.value(t);
        reach = bottom;
      }
    }
    return extra;
  }

  double _headerCenter(MorphMenuLayout layout) {
    for (final element in layout.elements) {
      if (element.kind == MorphMenuPlacedKind.cardHeader) {
        return element.rect.center.dy;
      }
    }
    return 0;
  }

  double _cardFadeProgress(double t) =>
      _phase == _Phase.idle ? 1 : _progress.valueAt(t + tuning.fadeLead);

  double _clampCardTop(double top, double height) {
    final cap = math.max(_cap, _rootHeight.target);
    return math.max(0, math.min(top, cap - math.min(height, _cap)));
  }

  /// Whether a submenu card is open or opening.
  bool get hasSubmenu => _cards.any((_Card card) => !card.backing);

  double _scaleUnder(int card, double t) {
    var scale = 1.0;
    for (var k = card; k < _cards.length; k++) {
      final q = _cards[k].progress.value(t);
      scale *= 1 - (1 - tuning.parentScale) * q;
    }
    return scale;
  }

  /// The cards of the menu, the root list first.
  List<MorphMenuCard> get cards {
    final t = _now;
    final result = <MorphMenuCard>[];
    final count = _cards.length;
    for (var i = 0; i <= count; i++) {
      final scale = _scaleUnder(i, t);
      final above = i < count ? _cards[i].progress.value(t) : 0.0;
      final opacity = (1 - (1 - tuning.parentRowOpacity) * above).clamp(
        0.0,
        1.0,
      );
      if (i == 0) {
        result.add(
          MorphMenuCard(
            layout: _root,
            rect: Rect.fromLTWH(0, 0, tuning.menuWidth, _root.height),
            scale: scale,
            rowOpacity: opacity,
            progress: 1,
          ),
        );
        continue;
      }
      final card = _cards[i - 1];
      final q = card.progress.value(t);
      final to = Rect.fromLTWH(
        0,
        card.top,
        tuning.menuWidth,
        math.min(card.layout.height, _cap),
      );
      final rect = Rect.lerp(card.from, to, q)!;
      final parent = result[i - 1];
      final targets = parent.layout.targets;
      final row = card.source < targets.length
          ? parent.rect.top +
                targets[card.source].rect.center.dy -
                (i == 1 ? scrollOffset : 0)
          : card.from.center.dy;
      final ratio = scale == 0 ? 1.0 : parent.scale / scale;
      final onRow = ratio * row - _headerCenter(card.layout);
      final contentTop = onRow + (card.top - onRow) * q;
      final c = q.clamp(0.0, 1.0);
      final from = card.backFrom.clamp(1e-6, 1.0);
      result.add(
        MorphMenuCard(
          layout: card.layout,
          rect: rect,
          scale: scale,
          rowOpacity: opacity,
          progress: q,
          contentTop: contentTop - rect.top,
          rowsOpacity: card.backing
              ? _ramp(c, tuning.cardRowsFadeOut * from, from)
              : _ramp(c, 0, tuning.cardRowsFadeIn),
          platterOpacity: math.sqrt(_ramp(c, 0, tuning.cardPlatterFade)),
          headerBold: card.backing
              ? _ramp(c, 0.9 * from, from)
              : _ramp(c, tuning.cardHeaderBoldStart, tuning.cardHeaderBoldEnd),
          chevronTurn: card.backing
              ? _ramp(c, tuning.cardChevronBack * from, from)
              : _ramp(c, 0, tuning.cardChevronTurn),
          closeOpacity: i == count ? _cardFade.at(_cardFadeProgress(t)) : 1,
          backing: card.backing,
          source: card.source,
        ),
      );
    }
    return result;
  }

  /// The final frame of the menu content; for a uniform menu, of the
  /// rows.
  Rect get finalMenuRect => _menu;

  /// Whether the menu opens below the button; otherwise it opens above it
  /// and its content is reversed.
  bool get opensDown => _down;

  /// The button's frame at the scale it had when the menu opened, which
  /// the menu is aligned to.
  Rect get pressedButtonRect => _pressed;

  /// The scale of the button's press growth.
  double get pressScale => _press.scale(_now);

  /// The highlighted target of [highlightedCard] - under the finger, or
  /// the chosen one while the menu closes.
  int? get highlighted => _highlighted;

  /// Whether the held button's finger is sliding through the menu.
  bool get isSliding => _pointer?.openedByHold ?? false;

  /// The card [highlighted] belongs to, 0 for the root list.
  int get highlightedCard => _highlightCard;

  void _setHighlight(int? target, int card, {bool tracked = false}) {
    if (target == _highlighted && card == _highlightCard) return;
    final from = _targetOf(_highlightCard, _highlighted);
    _highlighted = target;
    _highlightCard = card;
    _dwellGeneration++;
    final to = _targetOf(card, target);
    if (from != null || to != null || tracked) {
      emit(MorphMenuHighlightChanged(_now, from, to, tracked: tracked));
    }
  }

  MorphMenuTarget? _targetOf(int card, int? index) {
    if (index == null) return null;
    final targets = _layoutOf(card).targets;
    return index < targets.length ? targets[index] : null;
  }

  /// The glow under a finger on the menu in the [brightness] the menu
  /// resolved, centered in the motion's coordinates, or null while it
  /// does not show.
  MorphGlassGlow? glowAt(Brightness brightness) =>
      _touchGlow.glowAt(_now, brightness);

  /// The opacity of the menu content.
  double get contentOpacity => _contentOpacityAt(_now);

  double _contentOpacityAt(double t) {
    if (_phase == _Phase.idle) {
      return _ramp(
        _progress.valueAt(t),
        tuning.contentFadeStart,
        tuning.contentFadeEnd,
      );
    }
    final span = _fadeAnchor - _fadeEnd;
    if (span.abs() < 1e-6) return _fadeTo;
    final p = _progress.valueAt(t + tuning.fadeLead);
    final f = ((p - _fadeEnd) / span).clamp(0.0, 1.0);
    return _fadeTo + (_fadeFrom - _fadeTo) * f;
  }

  void _fade(
    double t, {
    required double from,
    required bool opening,
    bool fresh = false,
  }) {
    final p = _progress.valueAt(t + tuning.fadeLead);
    _fadeFrom = from;
    _fadeTo = opening ? 1 : 0;
    if (opening) {
      _fadeAnchor = fresh ? tuning.contentFadeStart : p;
      _fadeEnd = tuning.contentFadeEnd;
    } else {
      _fadeAnchor = p;
      _fadeEnd = p > tuning.contentCloseFadeEnd + 0.05
          ? tuning.contentCloseFadeEnd
          : 0;
    }
  }

  /// The blur radius of the menu content, in logical pixels on screen.
  double get contentBlur => math.max(
    0,
    tuning.contentBlur * (1 - progress) +
        tuning.contentKickBlur * _relativeKick,
  );

  /// The scale of the menu content relative to its final size. Closing
  /// cards use their measured container; other content follows the menu
  /// shape's scale plus its kick.
  ///
  /// The content is placed by [contentRect] at this scale, times
  /// [contentStretch] along each axis. Root rows clip to their platter;
  /// each submenu clips its rows independently.
  double get contentScale {
    if (!_cardContainerActive) return _contentScale(menuBlob);
    final end = (tuning.cardContainerEndWidth / tuning.menuWidth).clamp(
      0.0,
      1.0,
    );
    return end + (1 - end) * _cardContainer.value(_now);
  }

  double _contentScale(MorphMenuBlob menu) =>
      menu.scale + tuning.contentKickScale * _relativeKick;

  /// The frame of the menu content at [contentScale]. Closing cards
  /// contract about the button's center; other content rides [menuBlob].
  ///
  /// A menu taller than it is wide keeps its first row on the shape's top
  /// edge, like a list scrolled to its start, and grows below it; a menu
  /// as wide as it is tall or wider is centered on the shape.
  ///
  /// While a finger flexes the open menu, the frame is stretched with the
  /// shape by [contentStretch].
  Rect get contentRect {
    final rect = _contentRectUnflexed;
    final stretch = _stretch;
    if (stretch == null) return rect;
    final from = stretch.from;
    final to = stretch.to;
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    return Rect.fromLTWH(
      to.left + (rect.left - from.left) * sx,
      to.top + (rect.top - from.top) * sy,
      rect.width * sx,
      rect.height * sy,
    );
  }

  Rect get _contentRectUnflexed {
    if (_cardContainerActive) {
      final frame = _menu;
      final scale = contentScale;
      final at = _button.center + (frame.topLeft - _button.center) * scale;
      return Rect.fromLTWH(
        at.dx,
        at.dy,
        frame.width * scale,
        frame.height * scale,
      );
    }
    final menu = _blobFor(_menu, flexed: false);
    final frame = _menu;
    final scale = _contentScale(menu);
    final width = frame.width * scale;
    final height = frame.height * scale;
    final shape = menu.rect;
    _Card? card;
    for (final open in _cards) {
      if (!open.backing) card = open;
    }
    if (card != null) {
      final f = ((1 - progress) / tuning.cardCloseCenter).clamp(0.0, 1.0);
      final middle = frame.height / 2;
      final focus = card.top + math.min(card.layout.height, _cap) / 2;
      final anchor = middle + (focus - middle) * f;
      return Rect.fromLTWH(
        shape.center.dx - width / 2,
        shape.center.dy - anchor * scale,
        width,
        height,
      );
    }
    if (frame.height > frame.width) {
      return Rect.fromLTWH(
        shape.center.dx - width / 2,
        shape.top,
        width,
        height,
      );
    }
    return Rect.fromCenter(center: shape.center, width: width, height: height);
  }

  /// The opacity of the button's look inside the button shape.
  double get buttonLookOpacity =>
      1 - _ramp(_leadingProgress, tuning.lookFadeStart, tuning.lookFadeEnd);

  /// The blur radius of the button's look.
  double get buttonLookBlur => tuning.crossfadeBlur * progress.clamp(0.0, 1.0);

  /// The horizontal stretch of the button's look relative to the button
  /// shape's scale.
  double get buttonLookStretch =>
      1 + tuning.lookStretch * progress.clamp(0.0, 1.0);

  double get _leadingProgress => _phase == _Phase.idle
      ? progress
      : _progress.valueAt(_now + tuning.fadeLead);

  double get _relativeKick {
    final height = _menu.height;
    return height > 0 ? menuKick / height : 0;
  }

  static double _ramp(double value, double from, double to) =>
      ((value - from) / (to - from)).clamp(0.0, 1.0);

  /// The fusion radius: the standard deviation, in pixels, of the
  /// Gaussian blur UIKit applies to the distance field of [menuBlob] and
  /// [buttonBlob] to fuse them into one silhouette; 0 when they are
  /// drawn as their plain union.
  ///
  /// Every open and every close starts its own envelope
  /// ([MorphMenuTuning.fusionEnvelope]); the radius is the largest of the
  /// envelopes still running, limited to
  /// [MorphMenuTuning.fusionRadius], so a reversal never makes it jump.
  double get fusionRadius => _fusionAt(_now);

  /// The silhouette of [rootBlob] and [buttonBlob] fused at
  /// [fusionRadius], in the motion's coordinates. Below 1 pixel it is
  /// the exact plain union of the two; null only while idle.
  MorphGlassOutline? get silhouette => silhouetteFor(withField: true);

  /// The [silhouette], with the fused field a renderer shades the body
  /// from only when [withField] is true; false gives the same edge alone,
  /// for a host whose glass only fills the body (the flat tier, or no
  /// glass painter).
  MorphGlassOutline? silhouetteFor({required bool withField}) {
    if (_phase == _Phase.idle) return null;
    if (!drawsSource) return morphGlassContainerOutline([rootBlob.rrect], 0);
    final radius = fusionRadius;
    final MorphGlassOutline outline = radius < MorphMenuFusion.minimumRadius
        ? morphGlassContainerOutline([rootBlob.rrect, buttonBlob.rrect], 0)
        : _fusion.outline(
            rootBlob.rrect,
            buttonBlob.rrect,
            radius,
            withField: withField,
          )!;
    _prefetchField |= withField;
    _prefetchSilhouette();
    return outline;
  }

  /// Hands the coming frames' fusions to [MorphMenuFusion.prefetch]: the
  /// shapes and radius at the next [MorphMenuFusion.prefetchFrames]
  /// frames' times as the motion stands, the kicks integrated up to each.
  /// A fusion that comes back after the next frame started still serves
  /// the frame after it. The fusions carry the field once any frame of
  /// the motion asked for it, and are the edge alone before.
  ///
  /// The coming frames are the nodes of the source clock's frame grid
  /// after the motion's time ([frameTime] plus multiples of
  /// [framePeriod]), so a frame on the grid asks for exactly the time it
  /// was fused for, and a silhouette read at an event's time between
  /// frames still predicts the frames.
  void _prefetchSilhouette() {
    if (!MorphMenuFusion.prefetches) return;
    final period = framePeriod;
    final t = _timeline.now;
    if (period == null || t == _prefetchedFrom) return;
    _prefetchedFrom = t;
    var ahead = frameTime + period * ((t - frameTime) / period + 1).floor();
    if (ahead <= t) ahead += period;
    for (var frame = 0; frame < MorphMenuFusion.prefetchFrames; frame++) {
      _prefetchAt(ahead + period * frame);
    }
  }

  void _prefetchAt(double ahead) {
    final menuKick = _menuKick.value;
    final menuKickVelocity = _menuKick.velocity;
    final buttonKick = _buttonKick.value;
    final buttonKickVelocity = _buttonKick.velocity;
    final sampleTime = _sampleTime;
    _sample(ahead);
    _peekTime = ahead;
    try {
      final radius = fusionRadius;
      if (radius >= MorphMenuFusion.minimumRadius) {
        _fusion.prefetch(
          rootBlob.rrect,
          buttonBlob.rrect,
          radius,
          withField: _prefetchField,
        );
      }
    } finally {
      _peekTime = null;
      _sampleTime = sampleTime;
      _menuKick.value = menuKick;
      _menuKick.velocity = menuKickVelocity;
      _buttonKick.value = buttonKick;
      _buttonKick.velocity = buttonKickVelocity;
    }
  }

  double _fusionAt(double t) {
    var radius = 0.0;
    for (final fusion in _fusions) {
      radius = math.max(
        radius,
        tuning.fusionEnvelope(t - fusion.start, opening: fusion.opening),
      );
    }
    if (radius < tuning.fusionCutoff) return 0;
    return math.min(radius, tuning.fusionRadius);
  }

  bool _fusionAtRest(double t) {
    _fusions.removeWhere(
      (({double start, bool opening}) fusion) =>
          tuning.fusionEnded(t - fusion.start, opening: fusion.opening),
    );
    if (_fusions.isNotEmpty) return false;
    _fusion.settle();
    return true;
  }

  /// The vertical kick of the menu shape, positive toward the side the
  /// menu opens to.
  double get menuKick => _menuKick.value;

  /// The vertical kick of the button shape, positive toward the side the
  /// menu opens to.
  double get buttonKick => _buttonKick.value;

  /// The menu shape: grows out of the button into the menu.
  MorphMenuBlob get menuBlob => _blobFor(_menu);

  MorphMenuBlob _blobFor(
    Rect frame, {
    double parentScale = 1,
    bool flexed = true,
  }) {
    if (_attachment != null) {
      return _attachedBlobFor(frame, parentScale: parentScale, flexed: flexed);
    }
    final p = progress;
    final w = frame.width;
    final h = frame.height;
    final s0 = 0.5 * _sourceHeight / math.max(w, h);
    final scale = s0 + (1 - s0) * p;
    final localHeight = w + (h - w) * p;
    final from = _button.center;
    final to = frame.center;
    final sign = _down ? 1.0 : -1.0;
    final flex = flexed ? _flexAt(_now) : _noFlex;
    final center = Offset(
      from.dx + (to.dx - from.dx) * p + flex.shift.dx,
      from.dy + (to.dy - from.dy) * p + sign * menuKick + flex.shift.dy,
    );
    return MorphMenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: w * scale + flex.width,
        height: localHeight * scale + flex.height,
      ),
      radius: _localRadius(p, localHeight, h) * parentScale * scale,
      scale: scale,
      localSize: Size(w, localHeight),
    );
  }

  /// A context menu's shape: a straight line on the progress from the blob
  /// at the held view's center to [frame], flexed by the finger on it, its
  /// corners from the blob's capsule to the menu's.
  MorphMenuBlob _attachedBlobFor(
    Rect frame, {
    required double parentScale,
    required bool flexed,
  }) {
    final p = progress;
    final from = _blob;
    final flex = flexed ? _flexAt(_now) : _noFlex;
    final to = Rect.fromCenter(
      center: frame.center + flex.shift,
      width: frame.width + flex.width,
      height: frame.height + flex.height,
    );
    final rect = Rect.lerp(from, to, p)!;
    final width = from.width + (frame.width - from.width) * p;
    final height = from.height + (frame.height - from.height) * p;
    final scale = frame.width > 0 ? width / frame.width : 1.0;
    final fromRadius = math.min(from.width, from.height) / 2;
    final toRadius =
        math.min(tuning.cornerRadius, frame.height / 2) * parentScale;
    final radius = fromRadius + (toRadius - fromRadius) * p.clamp(0.0, 1.0);
    return MorphMenuBlob(
      rect: rect,
      radius: math.max(
        0,
        math.min(radius, math.min(rect.width, rect.height) / 2),
      ),
      scale: scale,
      localSize: Size(frame.width, scale > 0 ? height / scale : frame.height),
    );
  }

  static const ({Offset shift, double width, double height}) _noFlex = (
    shift: Offset.zero,
    width: 0,
    height: 0,
  );

  /// The menu shape without the flex ([from]) and with it ([to]), or null
  /// while nothing flexes it. The content and the hit testing follow the
  /// one affine map that takes [from] onto [to].
  ({Rect from, Rect to})? get _stretch {
    final flex = _flexAt(_now);
    if (flex.shift == Offset.zero && flex.width == 0 && flex.height == 0) {
      return null;
    }
    final from = _blobFor(_menu, flexed: false).rect;
    if (from.width <= 0 || from.height <= 0) return null;
    return (from: from, to: menuBlob.rect);
  }

  /// How much the flex of the open menu stretches its content along each
  /// axis on top of [contentScale]: the content fills the flexed
  /// [menuBlob] as it fills the shape without the flex, the one stretch,
  /// about the same anchor and with the same shift as the shape's, so
  /// rows, icons, the highlight, headers and submenu cards ride the
  /// shape 1:1 while a finger stretches and pulses it. (1, 1)
  /// while nothing flexes the menu.
  ///
  /// The flex keeps the shape a rectangle, so the map is exact for its
  /// frame; the corners keep their radius while the content in them
  /// stretches by at most a few percent (NEAR).
  Offset get contentStretch {
    final stretch = _stretch;
    if (stretch == null) return const Offset(1, 1);
    return Offset(
      stretch.to.width / stretch.from.width,
      stretch.to.height / stretch.from.height,
    );
  }

  /// [position] mapped back through the flex: where the unflexed menu has
  /// what the flexed one shows at [position].
  Offset _unflexed(Offset position) {
    final stretch = _stretch;
    if (stretch == null) return position;
    final from = stretch.from;
    final to = stretch.to;
    return Offset(
      from.left + (position.dx - to.left) * from.width / to.width,
      from.top + (position.dy - to.top) * from.height / to.height,
    );
  }

  bool _flexAtRest(double t) {
    final frame = _menu;
    final rest = _flexTouch == null
        ? MorphMenuTuning.flexReturnRest
        : MorphMenuTuning.flexPulseRest;
    final scaleRest = rest / math.max(1.0, math.max(frame.width, frame.height));
    return _flexScaleX.isWithin(t, scaleRest) &&
        _flexScaleY.isWithin(t, scaleRest) &&
        _flexDriftX.isWithin(t, rest) &&
        _flexDriftY.isWithin(t, rest);
  }

  /// What the flex's pulse channel ([MorphMenuTuning.flexPulseSpring])
  /// last published: its value and its velocity per second of its own
  /// clock.
  @visibleForTesting
  ({double value, double velocity}) get flexPulse =>
      (value: _pulse.value(_now), velocity: _pulse.velocity(_now));

  /// [menuRect] flexed by the finger on the menu, without the morph from
  /// the button: the frame UIKit's `_UIContextMenuListView` takes.
  @visibleForTesting
  Rect get flexedMenuRect {
    final frame = _menu;
    final flex = _flexAt(_now);
    return Rect.fromCenter(
      center: frame.center + flex.shift,
      width: frame.width + flex.width,
      height: frame.height + flex.height,
    );
  }

  /// The flex of the open menu under a finger at time [t]: the shift of
  /// its center and the growth of its width and height.
  ///
  /// The menu takes the scales and drifts of [_deformationAt]: its width
  /// and height scale about the center across and about the edge facing
  /// the button along the vertical, which the vertical drift moves.
  ({Offset shift, double width, double height}) _flexAt(double t) {
    final d = _deformationAt(t);
    if (d.scaleX == 1 && d.scaleY == 1 && d.driftX == 0 && d.driftY == 0) {
      return _noFlex;
    }
    final frame = _menu;
    final side = _down ? 1.0 : -1.0;
    final grow = frame.height * (d.scaleY - 1);
    return (
      shift: Offset(d.driftX, d.driftY + side * grow / 2),
      width: frame.width * (d.scaleX - 1),
      height: grow,
    );
  }

  /// The scales and drifts of the open menu's flex at time [t]: four
  /// channels that chase the targets of the finger on it
  /// ([MorphMenuTuning.flexTargets]) on the flex spec's tracking spring
  /// while it is down and return to rest on its scale spring after it
  /// lifts, each changed target pushing them by the spec's retarget
  /// impulse ([MorphChannel]).
  _Deformation _deformationAt(double t) => (
    scaleX: _flexScaleX.value(t),
    scaleY: _flexScaleY.value(t),
    driftX: _flexDriftX.value(t),
    driftY: _flexDriftY.value(t),
  );

  _Deformation _targetsOf(_FlexTouch touch) {
    final frame = _menu;
    final at = touch.position;
    final inside = Offset(
      at.dx.clamp(frame.left, frame.right),
      at.dy.clamp(frame.top, frame.bottom),
    );
    return tuning.flexTargets(
      translation: at - touch.origin,
      inBounds: inside - touch.origin,
      size: frame.size,
      velocity: _pulse.velocity(_now),
      side: _down ? 1.0 : -1.0,
    );
  }

  /// The root list's glass shape, scaled about its top center by the
  /// submenu parents' measured 0.97 scale, independently of the vessel
  /// that contains the full stack. With no cards this is [menuBlob].
  MorphMenuBlob get rootBlob {
    if (_cards.isEmpty) return menuBlob;
    final frame = _menu;
    final parentScale = _scaleUnder(0, _now);
    final root = Rect.fromLTWH(
      frame.left + frame.width * (1 - parentScale) / 2,
      frame.top,
      frame.width * parentScale,
      visibleRootHeight * parentScale,
    );
    return _blobFor(root, parentScale: parentScale);
  }

  /// The button shape: shrinks into the menu.
  MorphMenuBlob get buttonBlob {
    final p = progress;
    final from = _sourceScaleAt(_now);
    final scale = from + (tuning.sourceEndScale - from) * p;
    final start = _button.center;
    final travel = (_menu.center - start) * (tuning.sourceTravel * p);
    final sign = _down ? 1.0 : -1.0;
    final center = start + travel + Offset(0, sign * buttonKick);
    final size = _button.size * scale;
    return MorphMenuBlob(
      rect: Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      ),
      radius: math.min(
        math.min(size.width, size.height) / 2,
        (_sourceRadius ?? double.infinity) * scale,
      ),
      scale: scale,
      localSize: _button.size,
    );
  }

  /// A count that changes whenever an input reaches the motion or a
  /// pending reaction runs: while it holds and [isStill] holds, every frame
  /// shows the same picture.
  @internal
  int get revision => _revision;
  int _revision = 0;

  /// Whether nothing moves now; pending reactions and a resting finger may
  /// still change the picture later ([revision]).
  @internal
  bool get isStill => _still;

  /// Lands the menu's height, corners and cards on their targets at the
  /// motion's time; a host calls it once the motion [isSettled], when what
  /// remains does not show (NEAR, invisible). The progress keeps its
  /// remainder, which no layout reads exactly, and so does the flex a held
  /// finger leaves.
  @override
  void settle() {
    final t = _now;
    _radius.settle(t);
    _rootHeight.settle(t);
    _cardContainer.settle(t);
    for (final card in _cards) {
      card.progress.settle(t);
    }
  }

  /// Whether nothing moves and nothing is pending.
  ///
  /// A finger resting on the menu or its button does not keep it awake once
  /// the glow under it has faded in: its next move or release wakes it. A
  /// finger scrolling the content does.
  @override
  bool get isSettled => _timeline.isEmpty && _still;

  /// The motion time of the next pending event while a finger rests and
  /// nothing else moves, or null otherwise.
  ///
  /// Until that time every frame shows the same picture, so the clock
  /// driving the motion may doze until then instead of advancing it. Only
  /// a resting finger waits long (a submenu opens after
  /// [MorphMenuTuning.hoverOpenDelay]); the reactions to a release come
  /// due within a few frames, which keep coming, so a test's
  /// `pumpAndSettle` still sees them through.
  @override
  double? get wakeTime {
    final due = _timeline.nextDue;
    return due != null && _pointer != null && _still ? due : null;
  }

  bool get _still {
    final t = _now;
    if (_pointer?.scrolled ?? false) return false;
    if (_phase == _Phase.closing) return false;
    if (!_press.isSettled(t) || !_flexAtRest(t) || !_touchGlow.isSettled(t)) {
      return false;
    }
    if (_phase == _Phase.opening) {
      final rest = _progressRest;
      return _progress.restsWithin(t, rest) &&
          _radius.isWithin(t, rest) &&
          _rootHeight.isWithin(t, MorphRest.length) &&
          (!_cardContainerActive || _cardContainer.isWithin(t, _cardRest)) &&
          _cards.every((_Card card) => card.progress.isWithin(t, _cardRest)) &&
          _menuKick.isAtRest &&
          _buttonKick.isAtRest &&
          _fusionAtRest(t);
    }
    return true;
  }

  /// The target at [position] on the top card, or null.
  ///
  /// [position] is where the target shows: the hit testing follows the
  /// content through the flex ([contentStretch]).
  int? rowAt(Offset position) => _hitAt(position).target;

  /// Whether [position] is on the menu as it shows, flexed.
  bool _onMenu(Offset position) => _menu.contains(_unflexed(position));

  ({int card, int? target, bool beside}) _hitAt(Offset shown) {
    final position = _unflexed(shown);
    final top = _topCard;
    if (_phase == _Phase.idle) return (card: top, target: null, beside: false);
    final frame = _menu;
    if (!frame.contains(position)) {
      return (card: top, target: null, beside: false);
    }
    final local = position - frame.topLeft;
    if (top > 0) {
      final card = cards[top];
      if (!card.rect.contains(local)) {
        return (card: top, target: null, beside: true);
      }
      return (
        card: top,
        target: card.layout.targetAt(local - card.rect.topLeft),
        beside: false,
      );
    }
    return (
      card: 0,
      target: _root.targetAt(local + Offset(0, scrollOffset)),
      beside: false,
    );
  }

  bool _onWidgetRow(Offset shown) {
    final position = _unflexed(shown);
    final frame = _menu;
    if (!frame.contains(position)) return false;
    final local = position - frame.topLeft;
    final top = _topCard;
    final card = cards[top];
    final at = top == 0
        ? local + Offset(0, scrollOffset)
        : local - card.rect.topLeft;
    return card.layout.elements.any(
      (MorphMenuPlaced element) =>
          element.kind == MorphMenuPlacedKind.widget &&
          element.rect.contains(at),
    );
  }

  /// The index in [cards] of the card that takes the highlight and the
  /// choice: the newest one that is not on its way back.
  @internal
  int get topCard => _topCard;

  int get _topCard {
    var top = _cards.length;
    while (top > 0 && _cards[top - 1].backing) {
      top--;
    }
    return top;
  }

  /// The visual slot, from the top of a uniform menu, of row [index];
  /// rows are reversed when the menu opens upward.
  int slotOf(int index) => _down ? index : _itemCount - 1 - index;

  /// Opens the menu at time [t].
  ///
  /// [sourceScale] is the button's scale at that moment, which sizes the
  /// frame the menu aligns to; it defaults to the current press scale.
  void open(double t, {double? sourceScale}) {
    _revision++;
    advance(t);
    _open(t, sourceScale: sourceScale);
  }

  /// Closes the menu at time [t].
  void close(double t) {
    _revision++;
    _openPending = false;
    _timeline.clear();
    _resizeGeneration++;
    _pointer = null;
    advance(t);
    _close(t);
  }

  /// Chooses target [index] of the top card at time [t] as a release on
  /// it would.
  void select(double t, int index) {
    _revision++;
    advance(t);
    if (_phase != _Phase.opening) return;
    final card = _topCard;
    if (index < 0 || index >= _layoutOf(card).targets.length) return;
    _select(t, card, index);
  }

  /// Highlights target [index] of the top card at time [t], as a finger
  /// or the keyboard would; null clears the highlight.
  void highlight(double t, int? index) {
    _revision++;
    advance(t);
    if (_phase != _Phase.opening) return;
    _setHighlight(index, _topCard);
  }

  /// Sends the top submenu card back into its row at time [t]; returns
  /// whether there was one.
  bool back(double t) {
    _revision++;
    advance(t);
    if (_phase != _Phase.opening || _topCard == 0) return false;
    _back(t);
    return true;
  }

  /// Opens the menu at time [t] under a finger that has held its source
  /// and rests at [position]: the finger then slides onto a row and
  /// chooses it on release, as after a held button's opening, and a
  /// release before it left the source (a context menu's preview) keeps
  /// the menu open.
  void holdOpen(double t, Offset position) {
    _revision++;
    advance(t);
    final pointer = _Pointer(
      fromButton: true,
      position: position,
      startedInMenu: false,
    );
    pointer.openedByHold = true;
    _pointer = pointer;
    _open(t);
  }

  /// A finger touched down at [position].
  void pointerDown(double t, Offset position) {
    _revision++;
    advance(t);
    if (_pointer != null) return;
    if (_phase == _Phase.opening) {
      final pointer = _Pointer(
        fromButton: false,
        position: position,
        startedInMenu: _onMenu(position),
      );
      _pointer = pointer;
      if (_onWidgetRow(position)) {
        pointer.scrolled = true;
        return;
      }
      _track(t, pointer, position);
      _touchGlow.pointerDown(t, position);
      _flexDown(t, position);
      return;
    }
    if (_openPending) {
      _pointer = _Pointer(
        fromButton: false,
        position: position,
        startedInMenu: false,
      );
      return;
    }
    if (!_button.contains(position)) return;
    final pointer = _Pointer(
      fromButton: true,
      position: position,
      startedInMenu: false,
    );
    _pointer = pointer;
    _press.pointerDown(t, position - _button.topLeft);
    _timeline.at(t + tuning.holdDuration, (double s) {
      if (!identical(_pointer, pointer) ||
          _phase == _Phase.opening ||
          pointer.holdForfeited) {
        return;
      }
      pointer.openedByHold = true;
      _open(s);
    });
  }

  void _track(double t, _Pointer pointer, Offset position) {
    if (pointer.scrolled) return;
    final hit = _hitAt(position);
    final moved =
        hit.target != null &&
        (hit.target != _highlighted || hit.card != _highlightCard);
    _setHighlight(hit.target, hit.card, tracked: moved);
    final target = _targetOf(hit.card, hit.target);
    if (target == null || target.kind != MorphMenuTargetKind.submenu) return;
    final generation = _dwellGeneration;
    final card = hit.card;
    final index = hit.target!;
    _timeline.at(t + tuning.hoverOpenDelay, (double s) {
      if (generation != _dwellGeneration ||
          !identical(_pointer, pointer) ||
          _phase != _Phase.opening) {
        return;
      }
      _openCard(s, card, index);
    });
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    _revision++;
    advance(t);
    final pointer = _pointer;
    if (pointer == null) return;
    final previous = pointer.position;
    pointer.position = position;
    if (pointer.fromButton && !_holdArea.contains(position)) {
      pointer.leftButton = true;
      if (!pointer.openedByHold &&
          !_button.inflate(tuning.tapSlop).contains(position)) {
        pointer.holdForfeited = true;
      }
    }
    if (_phase != _Phase.opening || pointer.scrolled) return;
    final hit = _hitAt(position);
    if (hit.target != _highlighted || hit.card != _highlightCard) {
      _track(t, pointer, position);
    }
    // A finger that held the menu open lights it once it moves (device:
    // none under a still hold).
    if (_touchGlow.isDown) {
      _touchGlow.pointerMove(t, position);
    } else {
      _touchGlow.pointerDown(t, position);
    }
    if (_flexTouch == null && !_flexPending) _flexDown(t, previous);
    _timeline.at(t + tuning.flexDelay, (double s) {
      final touch = _flexTouch;
      if (touch == null || _phase != _Phase.opening) return;
      final before = _targetsOf(touch);
      touch.position = position;
      _noteChange(touch, s, before);
      _schedulePulse(touch, s);
    });
  }

  bool _flexPending = false;

  /// Sends the targets of [touch] to the flex channels at time [t] on
  /// their tracking spring when they changed from [before].
  void _noteChange(_FlexTouch touch, double t, _Deformation before) {
    final after = _targetsOf(touch);
    if (after == before) return;
    _flexScaleX.set(t, after.scaleX, tracking: true);
    _flexScaleY.set(t, after.scaleY, tracking: true);
    _flexDriftX.set(t, after.driftX, tracking: true);
    _flexDriftY.set(t, after.driftY, tracking: true);
  }

  /// The flex starts under a finger that touched down at [position] at
  /// time [t]: UIKit resets the pulse channel without animation.
  void _flexDown(double t, Offset position) {
    final generation = ++_flexGeneration;
    _flexPending = true;
    _timeline.at(t + tuning.flexDelay, (double s) {
      if (generation != _flexGeneration) return;
      _flexPending = false;
      if (_phase != _Phase.opening) return;
      _pulse.snap(s, 0);
      _flexTouch = _FlexTouch(position, s);
    });
  }

  /// Makes sure the pulse channel steps after time [t] while the finger
  /// is down, on its grid from the touch-down.
  void _schedulePulse(_FlexTouch touch, double t) {
    if (touch.nextStep != null) return;
    final period = 1 / tuning.flexPulseRate;
    final steps = ((t - touch.start) / period + 1e-6).floor() + 1;
    final at = touch.start + steps * period;
    touch.nextStep = at;
    final generation = _flexGeneration;
    _timeline.at(at, (double s) {
      if (generation != _flexGeneration || !identical(_flexTouch, touch)) {
        return;
      }
      touch.nextStep = null;
      final target = touch.position.dy - touch.origin.dy;
      final before = _targetsOf(touch);
      _pulse.step(s, target);
      _noteChange(touch, s, before);
      final flex = tuning.flex;
      final reach =
          math.max(
            flex.interactionPulseScaleX / 2,
            flex.interactionPulseScaleY * (1 + flex.interactionPulseDriftRatio),
          ) /
          flex.interactionPulseNormalizationFactor;
      if (!_pulse.holdsWithin(target, reach, MorphMenuTuning.flexPulseRest)) {
        _schedulePulse(touch, s);
      }
    });
  }

  /// The finger on the menu started to scroll its content: it no longer
  /// chooses anything.
  void pointerScrolled(double t) {
    _revision++;
    advance(t);
    final pointer = _pointer;
    if (pointer == null || pointer.scrolled) return;
    pointer.scrolled = true;
    _setHighlight(null, _highlightCard);
    _relax(t);
  }

  /// The finger lifted at [position].
  void pointerUp(double t, Offset position) {
    _revision++;
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.position = position;
    _relax(t);
    if (pointer.fromButton) {
      _release(t);
      if (!pointer.openedByHold) {
        final inside = _button.inflate(tuning.tapSlop).contains(position);
        if (!opensOnTap) {
          if (_phase != _Phase.opening && inside) emit(MorphMenuTapped(t));
          return;
        }
        if (_phase != _Phase.opening && inside) {
          _openPending = true;
          _timeline.at(t + tuning.tapOpenDelay, _open);
        }
        return;
      }
    }
    if (_phase != _Phase.opening) {
      if (_openPending) _earlyRelease = (t: t, position: position);
      return;
    }
    if (pointer.scrolled) return;
    if (pointer.fromButton && !pointer.leftButton) {
      _setHighlight(null, _highlightCard);
      return;
    }
    final hit = _hitAt(position);
    final target = hit.target;
    if (target != null) {
      _select(t, hit.card, target);
      return;
    }
    _setHighlight(null, _highlightCard);
    if (hit.beside) {
      _timeline.at(t + tuning.backDelay, _back);
    } else if (!pointer.fromButton && !_onMenu(position)) {
      _timeline.at(t + tuning.dismissDelay, _requestClose);
    }
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    _revision++;
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    _relax(t);
    if (_phase == _Phase.opening) _setHighlight(null, _highlightCard);
    if (pointer.fromButton) _release(t);
  }

  /// Advances the motion to time [t]: runs every event due by then and
  /// samples the progress, integrating the kicks over the interval. A close
  /// requested on the way starts at its own time, unanswered.
  @override
  void advance(double t) => _advance(t);

  /// Advances the motion toward time [t] as [advance] does, but stops at a
  /// [MorphMenuCloseRequested] that comes due on the way, the last event it
  /// raised; returns whether the motion reached [t].
  ///
  /// Stopped, the motion stands at the request's time, still open and
  /// sampled no further: [admitClose] starts the close there, at the
  /// measured deadline, as if nothing had stopped. Any later advance or
  /// command goes on with the menu open, which refuses the request; it is
  /// not raised again, and a close the owner approves later is a [close] at
  /// the current time.
  bool advanceToRequest(double t) {
    _yields = true;
    try {
      return _advance(t);
    } finally {
      _yields = false;
    }
  }

  /// Starts the close [request] asked for, at its time, while the motion
  /// stands at it ([advanceToRequest]); returns false and changes nothing
  /// once the motion has moved on.
  bool admitClose(MorphMenuCloseRequested request) {
    if (!identical(request, _request)) return false;
    _request = null;
    _close(request.time);
    return true;
  }

  bool _advance(double t) {
    _request = null;
    if (t < _now) return true;
    if ((_timeline.nextDue ?? double.infinity) <= t) _revision++;
    if (!_timeline.runDue(t, until: () => _request != null)) return false;
    _sample(t);
    for (var i = _cards.length - 1; i >= 0; i--) {
      final card = _cards[i];
      if (card.backing && card.progress.value(t) < tuning.cardGone) {
        _cards.removeAt(i);
      }
    }
    if (_phase == _Phase.closing &&
        _progress.restsWithin(t, _progressRest) &&
        _menuKick.isAtRest &&
        _buttonKick.isAtRest &&
        _fusionAtRest(t)) {
      _phase = _Phase.idle;
      _highlighted = null;
      _highlightCard = 0;
      _cards.clear();
      _cardContainerActive = false;
      scrollOffset = 0;
      _menuKick.reset();
      _buttonKick.reset();
      _openReference = null;
      _closeReference = null;
    }
    return true;
  }

  /// The final frame of a menu of [size] opened from a button whose frame
  /// at its current scale is [button], inside [bounds] minus [padding].
  ///
  /// The menu opens downward with its top on the button's top when the
  /// button's center is in the upper half of the safe area, and upward with its
  /// bottom on the button's bottom otherwise. It is centered on the button
  /// when that keeps [edgeMargin] from the safe area's sides, and aligns
  /// with the button's nearer edge otherwise; the result is then clamped
  /// into the safe area.
  static ({Rect rect, bool down}) place({
    required Rect button,
    required Size size,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double edgeMargin = MorphMenuTuning.defaultEdgeMargin,
  }) {
    final down =
        button.center.dy <= (padding.top + bounds.height - padding.bottom) / 2;
    final minLeft = padding.left;
    final maxRight = bounds.width - padding.right;
    var left = button.center.dx - size.width / 2;
    if (left < minLeft + edgeMargin ||
        left + size.width > maxRight - edgeMargin) {
      left = button.center.dx < bounds.width / 2
          ? button.left
          : button.right - size.width;
    }
    left = math.max(minLeft, math.min(left, maxRight - size.width));
    var top = down ? button.top : button.bottom - size.height;
    final maxBottom = bounds.height - padding.bottom;
    top = math.max(padding.top, math.min(top, maxBottom - size.height));
    return (
      rect: Rect.fromLTWH(left, top, size.width, size.height),
      down: down,
    );
  }

  /// The final frame of a context menu of [size] attached to
  /// [attachment] inside [bounds] minus [padding], whether it stands below
  /// the preview, and how far the preview moves with it.
  ///
  /// The menu stands [MorphMenuAttachment.gap] below the preview when the
  /// preview, its accessory and the menu fit inside the safe area minus
  /// [MorphMenuAttachment.margin] that way, above it when they fit that
  /// way, and below it otherwise, the preview and the menu then shifting
  /// together until the menu fits (the top edge wins). Across, the menu
  /// centers on the preview when that keeps [edgeMargin] from the safe
  /// area and aligns with the preview's nearer edge otherwise; a preview
  /// that leaves the safe area moves back into it.
  static ({Rect rect, bool down, Offset shift}) placeAttached({
    required MorphMenuAttachment attachment,
    required Size size,
    required Size bounds,
    EdgeInsets padding = EdgeInsets.zero,
    double edgeMargin = MorphMenuTuning.defaultEdgeMargin,
  }) {
    final preview = attachment.preview;
    final gap = attachment.gap;
    final margin = attachment.margin;
    final top = padding.top + margin;
    final bottom = bounds.height - padding.bottom - margin;
    final left = padding.left + margin;
    final right = bounds.width - padding.right - margin;
    final columnTop = preview.top - attachment.accessory;
    final below = preview.bottom + gap + size.height;
    final above = columnTop - gap - size.height;
    var down = true;
    var dy = 0.0;
    if (columnTop >= top && below <= bottom) {
      down = true;
    } else if (above >= top && preview.bottom <= bottom) {
      down = false;
    } else {
      dy = math.min(0, bottom - below);
      if (columnTop + dy < top) dy = top - columnTop;
    }
    var dx = 0.0;
    if (preview.right > right) dx = right - preview.right;
    if (preview.left + dx < left) dx = left - preview.left;
    final shifted = preview.shift(Offset(dx, dy));
    var x = shifted.center.dx - size.width / 2;
    final minLeft = padding.left + edgeMargin;
    final maxRight = bounds.width - padding.right - edgeMargin;
    if (x < minLeft || x + size.width > maxRight) {
      x = shifted.center.dx < bounds.width / 2
          ? shifted.left
          : shifted.right - size.width;
    }
    x = math.max(left, math.min(x, right - size.width));
    final y = down
        ? shifted.bottom + gap
        : shifted.top - attachment.accessory - gap - size.height;
    return (
      rect: Rect.fromLTWH(x, y, size.width, size.height),
      down: down,
      shift: Offset(dx, dy),
    );
  }

  /// The opening kick's amplitude relative to a 146-pixel menu, for a
  /// menu [height] pixels tall; it scales [MorphMenuTuning.openKickGain].
  static double kickAmplitude(double height) =>
      _interpolate(_kickAmplitude, height);

  static double _interpolate(List<(double, double)> table, double height) {
    if (height <= table.first.$1) return table.first.$2;
    for (var i = 1; i < table.length; i++) {
      final (h1, a1) = table[i];
      if (height <= h1) {
        final (h0, a0) = table[i - 1];
        return a0 + (a1 - a0) * (height - h0) / (h1 - h0);
      }
    }
    return table.last.$2;
  }

  void _sample(double t) {
    final from = _sampleTime;
    if (t > from &&
        from.isFinite &&
        _phase != _Phase.idle &&
        tuning.morph.kicks) {
      final a = _amplitude;
      final open = _openReference;
      final close = _closeReference;
      final opening = _phase == _Phase.opening;
      _menuKick.step(
        from,
        t,
        opening ? tuning.openKickSpring : tuning.closeKickSpring,
        open == null || !opening
            ? null
            : (double s) => tuning.openKickGain * a * open.velocity(s),
        inputAtRest: open == null || !opening ? null : _referenceRests(open),
      );
      _buttonKick.step(
        from,
        t,
        tuning.sourceKickSpring,
        close == null
            ? null
            : (double s) =>
                  tuning.sourceKickGain * _sourceAmplitude * close.velocity(s),
        inputAtRest: close == null ? null : _referenceRests(close),
      );
    }
    if (t >= from) _sampleTime = t;
  }

  void _place(double sourceScale) {
    _sourceScale = sourceScale;
    _pressed = Rect.fromCenter(
      center: _button.center,
      width: _button.width * sourceScale,
      height: _button.height * sourceScale,
    );
    final height = _visibleRoot(_root);
    final size = Size(tuning.menuWidth, height);
    final attachment = _attachment;
    if (attachment != null) {
      final placed = placeAttached(
        attachment: attachment,
        size: size,
        bounds: _bounds,
        padding: _padding,
        edgeMargin: tuning.edgeMargin,
      );
      _left = placed.rect.left;
      _down = placed.down;
      _shift = placed.shift;
      _anchor = _down ? placed.rect.top : placed.rect.bottom;
    } else {
      final placed = place(
        button: _pressed,
        size: size,
        bounds: _bounds,
        padding: _padding,
        edgeMargin: tuning.edgeMargin,
      );
      _left = placed.rect.left;
      _down = placed.down;
      _shift = Offset.zero;
      _anchor = _down ? placed.rect.top : placed.rect.bottom;
    }
    final reversed = !_down;
    if (reversed != _reversed) {
      _reversed = reversed;
      _root = _build(reversed: reversed);
    }
    _rootHeight.snap(_now, height);
    _amplitude = kickAmplitude(size.height);
    _closeAmplitude = _interpolate(_closeKickAmplitude, size.height);
    _sourceAmplitude = _interpolate(_sourceKickAmplitude, size.height);
  }

  void _open(double t, {double? sourceScale}) {
    _openPending = false;
    if (_phase == _Phase.opening) return;
    _sample(t);
    final fresh = _phase == _Phase.idle;
    final opacity = fresh ? 0.0 : _contentOpacityAt(t);
    if (_phase == _Phase.idle) {
      _place(sourceScale ?? _press.scale(t));
      _radiusFrom = tuning.openingRadius;
    } else {
      _sourceScale = sourceScale ?? _sourceScaleAt(t);
      _radiusFrom = _closingRadius(_progress.valueAt(t));
    }
    _phase = _Phase.opening;
    if (fresh) {
      _cardContainerActive = false;
      _cardContainer.snap(t, 1);
    } else if (_cardContainerActive) {
      _cardContainer.retarget(t, 1, spring: tuning.openSpring);
    }
    if (tuning.morph.fuses && drawsSource) {
      _fusions.add((start: t, opening: true));
    }
    final reference = MorphSpringState(tuning.openSpring, 0);
    reference.retarget(t, 1);
    _openReference = reference;
    final p = _cardFadeProgress(t);
    _cardFade.start(
      from: fresh ? 1 : _cardFade.at(p),
      to: 1,
      anchor: p,
      end: 1,
    );
    _progress.open(t);
    _fade(t, from: opacity, opening: true, fresh: fresh);
    _radius.snap(t, 0);
    final generation = ++_openGeneration;
    _timeline.at(t + tuning.radiusDelay, (double s) {
      if (generation != _openGeneration) return;
      _radius.retarget(s, 1, spring: tuning.openSpring);
    });
    _takeEarlyTouch(t);
  }

  void _takeEarlyTouch(double t) {
    final pointer = _pointer;
    if (pointer != null && !pointer.fromButton) {
      _setHighlight(rowAt(pointer.position), _topCard);
      _touchGlow.pointerDown(t, pointer.position);
    }
    final release = _earlyRelease;
    _earlyRelease = null;
    if (release == null) return;
    final row = rowAt(release.position);
    final target = _targetOf(0, row);
    if (row != null &&
        target != null &&
        target.kind == MorphMenuTargetKind.action) {
      _setHighlight(row, 0);
      _timeline.at(t + tuning.actionDelay, (double s) => _activate(s, 0, row));
      _timeline.at(t + tuning.earlyCloseDelay, _requestClose);
    } else if (!_onMenu(release.position)) {
      _timeline.at(t + tuning.earlyCloseDelay, _requestClose);
    }
  }

  void _requestClose(double t) {
    if (_phase != _Phase.opening) return;
    if (!_yields) {
      _close(t);
      return;
    }
    final request = MorphMenuCloseRequested(t);
    _request = request;
    emit(request);
  }

  void _close(double t) {
    if (_phase != _Phase.opening) return;
    _sample(t);
    final opacity = _contentOpacityAt(t);
    _closeRadius = _openingRadius(t);
    _closeProgress = _progress.valueAt(t);
    _closeStart = t;
    _closeSource = _sourceScale;
    _closeLive = _press.scale(t);
    _openGeneration++;
    _resizeGeneration++;
    _phase = _Phase.closing;
    if (tuning.morph.fuses && drawsSource) {
      _fusions.add((start: t, opening: false));
    }
    _relax(t);
    final reference = MorphSpringState(tuning.closeSpring, 1);
    reference.retarget(t, 0);
    _closeReference = reference;
    final p = _cardFadeProgress(t);
    _cardFade.start(
      from: _cardFade.at(p),
      to: 0,
      anchor: p,
      end: p > tuning.cardCloseFadeEnd + 0.05 ? tuning.cardCloseFadeEnd : 0,
    );
    _progress.close(t);
    _fade(t, from: opacity, opening: false);
    final generation = _openGeneration;
    if (_cards.isNotEmpty && !_cardContainerActive) {
      _cardContainerActive = true;
      _cardContainer.snap(t, 1);
    }
    if (_cardContainerActive) {
      _timeline.at(t + tuning.cardContainerDelay, (double s) {
        if (generation != _openGeneration || _phase != _Phase.closing) return;
        _cardContainer.retarget(s, 0, spring: tuning.cardContainerSpring);
      });
    }
    if (!tuning.morph.kicks) return;
    _timeline.at(t + tuning.closeKickDelay, (double s) {
      if (generation != _openGeneration || _phase != _Phase.closing) return;
      _sample(s);
      final reach = tuning.closeKickReach * _closeAmplitude;
      final room = (1 - _menuKick.value / reach).clamp(0.0, 1.0);
      _menuKick.velocity += tuning.closeKickImpulse * _closeAmplitude * room;
    });
  }

  void _activate(double t, int card, int index) {
    final target = _targetOf(card, index);
    if (target == null) return;
    emit(MorphMenuActivated(t, target, card: card, index: index));
  }

  void _select(double t, int card, int index) {
    final target = _targetOf(card, index);
    if (target == null) return;
    switch (target.kind) {
      case MorphMenuTargetKind.submenu:
        _setHighlight(index, card);
        final delay = card == 0
            ? tuning.submenuDelay
            : tuning.deeperSubmenuDelay;
        final generation = _openGeneration;
        _timeline.at(t + delay, (double s) {
          if (generation != _openGeneration || _phase != _Phase.opening) {
            return;
          }
          _openCard(s, card, index);
        });
      case MorphMenuTargetKind.back:
        _setHighlight(null, card);
        _timeline.at(t + tuning.backDelay, _back);
      case MorphMenuTargetKind.action:
        final keep = switch (dismissOnSelect) {
          null => target.keepsOpen,
          final bool dismiss => !dismiss,
        };
        if (keep) {
          _setHighlight(null, card);
          _timeline.at(
            t + tuning.keptActionDelay,
            (double s) => _activate(s, card, index),
          );
          return;
        }
        _setHighlight(index, card);
        final delay = card == 0
            ? tuning.actionDelay
            : tuning.submenuActionDelay;
        _timeline.at(t + delay, (double s) => _activate(s, card, index));
        _timeline.at(
          t + (card == 0 ? tuning.dismissDelay : tuning.submenuCloseDelay),
          _requestClose,
        );
    }
  }

  void _openCard(double t, int card, int index) {
    if (_phase != _Phase.opening) return;
    final source = _targetOf(card, index);
    if (source == null || source.kind != MorphMenuTargetKind.submenu) return;
    while (_cards.length > card) {
      final last = _cards.last;
      if (!last.backing) break;
      if (_cards.length == card + 1 && last.source == index) {
        last.backing = false;
        last.progress.retarget(
          t,
          1,
          spring: card == 0 ? tuning.submenuSpring : tuning.deeperSubmenuSpring,
        );
        _setHighlight(null, card + 1);
        return;
      }
      _cards.removeLast();
    }
    if (_cards.length != card) return;
    final layout = submenuLayout?.call(source);
    if (layout == null) return;
    final shown = cards[card];
    final rowLocal = source.rect.center.dy - (card == 0 ? scrollOffset : 0);
    final rowCenter = shown.rect.top + rowLocal;
    final from = Rect.fromCenter(
      center: Offset(tuning.menuWidth / 2, rowCenter),
      width: tuning.cardStartWidth,
      height: source.rect.height,
    );
    final spring = card == 0
        ? tuning.submenuSpring
        : tuning.deeperSubmenuSpring;
    final progress = MorphSpringState(spring, 0);
    progress.retarget(t, 1);
    _cards.add(
      _Card(
        layout: layout,
        source: index,
        from: from,
        top: _clampCardTop(
          shown.rect.top +
              (rowLocal - tuning.cardLead) *
                  (card == 0 ? 1 : tuning.parentScale),
          layout.height,
        ),
        progress: progress,
      ),
    );
    _setHighlight(null, card + 1);
  }

  void _back(double t) {
    if (_phase != _Phase.opening) return;
    final top = _topCard;
    if (top == 0) return;
    final card = _cards[top - 1];
    card.backing = true;
    card.backFrom = card.progress.value(t);
    card.progress.retarget(t, 0, spring: tuning.backSpring);
    _setHighlight(null, top - 1);
  }

  void _release(double t) {
    _press.release(t);
  }

  void _relax(double t) {
    final generation = ++_flexGeneration;
    _flexPending = false;
    _timeline.at(t + tuning.flexDelay, (double s) {
      if (generation != _flexGeneration) return;
      _flexUp(s);
    });
    _touchGlow.pointerUp(t);
  }

  /// The finger that flexed the menu lifted at time [t]: UIKit zeroes the
  /// pulse channel's velocity and sends the flex channels to rest on the
  /// flex spec's scale spring, from where they show with their velocity.
  void _flexUp(double t) {
    final touch = _flexTouch;
    if (touch == null) return;
    _flexTouch = null;
    _pulse.clearPublishedVelocity();
    _flexScaleX.set(t, 1);
    _flexScaleY.set(t, 1);
    _flexDriftX.set(t, 0);
    _flexDriftY.set(t, 0);
  }

  double _sourceScaleAt(double t) {
    if (_phase != _Phase.closing) return _sourceScale;
    final live = _press.scale(t);
    final decay = math.exp(-(t - _closeStart) / tuning.sourceRelax);
    return live + (_closeSource - _closeLive) * decay;
  }

  double _openingRadius(double t) {
    final target = math.min(tuning.cornerRadius, _frameAt(t).height / 2);
    return _radiusFrom + (target - _radiusFrom) * _radius.value(t);
  }

  double _closingRadius(double p) {
    final half = tuning.menuWidth / 2;
    if (_closeProgress.abs() < 1e-3) return half;
    return half + (_closeRadius - half) * p / _closeProgress;
  }

  double _localRadius(double p, double localHeight, double height) {
    final raw = _phase == _Phase.closing
        ? _closingRadius(p)
        : _openingRadius(_now);
    final capped = math.min(
      raw,
      math.min(tuning.menuWidth / 2, localHeight / 2),
    );
    return math.max(0, capped);
  }
}

const List<(double, double)> _kickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (188, 1.488),
  (230, 1.628),
  (272, 1.61),
  (356, 1.563),
  (440, 1.481),
];

// The closing amplitudes were captured at 146, 230 and 440 pixels;
// below 146 the opening's amplitude stands in.
const List<(double, double)> _closeKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.644),
  (440, 1.61),
];

const List<(double, double)> _sourceKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.488),
  (440, 1.777),
];

/// What a [MorphMenuMotion] tells its host, at the motion [time] it
/// happened.
sealed class MorphMenuEvent {
  const MorphMenuEvent(this.time);

  /// The motion time of the reaction that raised the event, in seconds.
  final double time;
}

/// The highlighted target changed from [from] to [to] (null for none).
final class MorphMenuHighlightChanged extends MorphMenuEvent {
  /// Creates the event.
  const MorphMenuHighlightChanged(
    super.time,
    this.from,
    this.to, {
    required this.tracked,
  });

  /// The target highlighted before, or null.
  final MorphMenuTarget? from;

  /// The target highlighted now, or null.
  final MorphMenuTarget? to;

  /// Whether a finger moved the highlight onto another target: the moment
  /// UIKit's menu plays its selection haptic (read from UIKit, notes
  /// private). A highlight the keyboard or a hover moves, or one that
  /// clears, is not tracked.
  final bool tracked;
}

/// The action of [target] runs, before the menu starts closing.
final class MorphMenuActivated extends MorphMenuEvent {
  /// Creates the event.
  const MorphMenuActivated(
    super.time,
    this.target, {
    required this.card,
    required this.index,
  });

  /// The target whose action runs.
  final MorphMenuTarget target;

  /// The card [target] is on, 0 for the root list.
  final int card;

  /// The index of [target] on its card.
  final int index;
}

/// A tap released on the button, or within [MorphMenuTuning.tapSlop] of
/// it, does not open the menu because [MorphMenuMotion.opensOnTap] is
/// false.
final class MorphMenuTapped extends MorphMenuEvent {
  /// Creates the event.
  const MorphMenuTapped(super.time);
}

/// The menu would start closing now, at the measured reaction to a
/// release outside it, on an action or before it appeared.
///
/// Raised by [MorphMenuMotion.advanceToRequest], which stops here until
/// the host answers with [MorphMenuMotion.admitClose] or goes on, which
/// refuses it.
final class MorphMenuCloseRequested extends MorphMenuEvent {
  /// Creates the event.
  MorphMenuCloseRequested(super.time);
}
