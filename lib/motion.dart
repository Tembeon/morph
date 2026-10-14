/// The measured motion behind the widget layer: pure motion objects,
/// the tuning constants read from UIKit on iOS 27 and the layout types
/// they place their geometry with.
///
/// Every class here is a pure function of explicit time and input, so a
/// replay, a test or a custom widget can drive it without the widgets of
/// `package:morph/widgets.dart`. An app that only uses the controls
/// needs nothing from this library; the tuning objects the widgets take
/// as parameters (`MorphMenuTuning`, `MorphBarMenuTuning`,
/// `MorphPushZoomTuning`, `MorphZoomTuning`) are exported by the widget
/// layer itself.
library;

export 'src/widgets/activity_indicator.dart' show MorphActivityIndicatorFrames;
export 'src/widgets/alert_motion.dart'
    show
        MorphAlertMotion,
        MorphAlertTuning,
        MorphPopoverArrowDirection,
        MorphPopoverMotion,
        MorphPopoverPlacement,
        MorphPopoverTuning,
        morphPlacePopover;
export 'src/widgets/bar_motion.dart'
    show
        MorphBarCapsuleFrame,
        MorphBarCapsuleLayout,
        MorphBarItemFrame,
        MorphBarItemLayout,
        MorphBarMotion,
        MorphBarTransitionSpec;
export 'src/widgets/date_picker_motion.dart'
    show
        MorphDatePickerMotion,
        MorphDatePickerPlacement,
        MorphDatePickerTuning,
        morphPlaceDatePicker;
export 'src/widgets/flex_spec.dart' show MorphFlexSpec;
export 'src/widgets/glass_button.dart' show MorphGlassButtonMotion;
export 'src/widgets/glass_glow.dart' show MorphTouchGlowMotion;
export 'src/widgets/highlight_motion.dart'
    show MorphListRowHighlightMotion, MorphSegmentHighlightMotion;
export 'src/widgets/lens_motion.dart'
    show MorphLensMotion, MorphLensSlot, MorphLensTuning;
export 'src/widgets/menu_morph_spec.dart' show MorphMenuMorphSpec;
export 'src/widgets/menu_motion.dart'
    show
        MorphMenuBlob,
        MorphMenuCard,
        MorphMenuMotion,
        MorphMenuProgress,
        MorphMenuTuning;
export 'src/widgets/navigation_motion.dart'
    show MorphNavigationTitleMotion, MorphNavigationTuning;
export 'src/widgets/page_control.dart'
    show MorphPageControlMotion, MorphPageControlTuning;
export 'src/widgets/progress.dart' show MorphProgressMotion;
export 'src/widgets/push_zoom_motion.dart'
    show MorphPushZoomMotion, MorphPushZoomTuning;
export 'src/widgets/search_motion.dart'
    show MorphSearchMotion, MorphSearchTuning;
export 'src/widgets/sheet_motion.dart'
    show MorphSheetDetent, MorphSheetMotion, MorphSheetTuning;
export 'src/widgets/slider_motion.dart' show MorphSliderMotion;
export 'src/widgets/small_lens.dart' show MorphSmallLens;
export 'src/widgets/switch_motion.dart' show MorphSwitchMotion;
export 'src/widgets/zoom_motion.dart' show MorphZoomMotion, MorphZoomTuning;
