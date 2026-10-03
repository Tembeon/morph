/// The widget layer: controls that move like iOS Liquid Glass, measured
/// from UIKit and reproduced, plus the recipes that put the morph engine
/// to work - a held surface becoming its own context menu.
///
/// Every motion value here is read from UIKit's tuning on iOS 27 or
/// fitted to frame-by-frame recordings of the real controls, and each
/// control is checked against those recordings: the selection lens of
/// [MorphSegmentedControl] and [MorphTabBar], [MorphSwitch],
/// [MorphSlider], [MorphStepper], the press of [MorphGlassButton] and
/// the button that becomes its own menu, [MorphMenuButton]. The motion
/// objects behind them ([MorphLensMotion], [MorphGlassButtonMotion],
/// [MorphMenuMotion] and their kin) are pure functions of explicit time,
/// usable without the widgets.
///
/// Everything here is built strictly on `package:morph/foundation.dart`
/// and motor; the engine never depends on this layer. There is no glass
/// shader here: the layer reproduces how the platform's surfaces move.
/// The controls draw flat fills by default; a [MorphGlassPainter]
/// installed with [MorphGlass] renders their surfaces instead, so an app
/// can bring its own refraction. Their looks resolve from a `style`
/// argument, then [MorphWidgetsTheme], then light and dark tables.
library;

export 'foundation.dart';
export 'src/widgets/activity_indicator.dart'
    show
        MorphActivityIndicator,
        MorphActivityIndicatorFrames,
        MorphActivityIndicatorSize,
        MorphActivityIndicatorStyle;
export 'src/widgets/alert.dart'
    show
        MorphAlertAction,
        MorphAlertActionStyle,
        MorphAlertRoute,
        MorphAlertStyle,
        MorphAlertTextField,
        showMorphActionSheet,
        showMorphAlert;
export 'src/widgets/alert_motion.dart'
    show
        MorphAlertMotion,
        MorphAlertTuning,
        MorphPopoverArrowEdge,
        MorphPopoverMotion,
        MorphPopoverPlacement,
        MorphPopoverTuning,
        morphPlacePopover;
export 'src/widgets/bar_items.dart'
    show
        MorphBarButton,
        MorphBarButtonGroup,
        MorphBarMenuTuning,
        MorphBarMetrics,
        MorphBarStyle;
export 'src/widgets/bar_motion.dart'
    show
        MorphBarCapsuleFrame,
        MorphBarCapsuleLayout,
        MorphBarItemFrame,
        MorphBarItemLayout,
        MorphBarMotion,
        MorphBarTransitionSpec;
export 'src/widgets/date_picker.dart'
    show MorphDatePicker, MorphDatePickerMode, MorphDatePickerStyle;
export 'src/widgets/date_picker_motion.dart'
    show
        MorphDatePickerMotion,
        MorphDatePickerPlacement,
        MorphDatePickerTuning,
        morphPlaceDatePicker;
export 'src/widgets/flex_spec.dart' show MorphFlexSpec;
export 'src/widgets/glass.dart'
    show
        MorphGlass,
        MorphGlassKind,
        MorphGlassOptics,
        MorphGlassPainter,
        MorphGlassSurface;
export 'src/widgets/glass_button.dart'
    show MorphGlassButton, MorphGlassButtonMotion, MorphGlassButtonStyle;
export 'src/widgets/lens_motion.dart'
    show MorphLensMotion, MorphLensSlot, MorphLensTuning;
export 'src/widgets/menu.dart'
    show MorphMenuButton, MorphMenuItem, MorphMenuStyle;
export 'src/widgets/menu_morph_spec.dart' show MorphMenuMorphSpec;
export 'src/widgets/menu_motion.dart'
    show MorphMenuBlob, MorphMenuMotion, MorphMenuProgress, MorphMenuTuning;
export 'src/widgets/morph_context_menu.dart'
    show MorphContextMenuRegion, MorphSatellite;
export 'src/widgets/navigation_bar.dart'
    show
        MorphLargeTitle,
        MorphLargeTitleScrollPhysics,
        MorphNavigationBar,
        MorphNavigationBarMetrics;
export 'src/widgets/navigation_motion.dart'
    show MorphNavigationTitleMotion, MorphNavigationTransition;
export 'src/widgets/navigation_stack.dart'
    show
        MorphNavigationConfig,
        MorphNavigationRoute,
        MorphNavigationScaffold,
        MorphNavigationStack;
export 'src/widgets/page_control.dart'
    show
        MorphPageControl,
        MorphPageControlBackground,
        MorphPageControlMotion,
        MorphPageControlStyle,
        MorphPageControlTuning;
export 'src/widgets/progress.dart'
    show
        MorphProgressMotion,
        MorphProgressStyle,
        MorphProgressView,
        MorphProgressViewStyle;
export 'src/widgets/scroll_edge_effect.dart'
    show
        MorphScrollEdgeEffect,
        MorphScrollEdgeEffectStyle,
        MorphScrollEdgeEffectThemeData;
export 'src/widgets/search_field.dart'
    show MorphSearchField, MorphSearchFieldStyle, MorphSearchToolbar;
export 'src/widgets/search_motion.dart'
    show MorphSearchMotion, MorphSearchTuning;
export 'src/widgets/search_tab_bar.dart' show MorphSearchTabBar;
export 'src/widgets/segmented_control.dart'
    show MorphSegmentedControl, MorphSegmentedStyle;
export 'src/widgets/sheet.dart'
    show MorphSheet, MorphSheetRoute, MorphSheetStyle, presentMorphSheet;
export 'src/widgets/sheet_motion.dart'
    show MorphSheetDetent, MorphSheetMotion, MorphSheetTuning;
export 'src/widgets/slider.dart' show MorphSlider, MorphSliderStyle;
export 'src/widgets/slider_motion.dart' show MorphSliderMotion;
export 'src/widgets/small_lens.dart' show MorphSmallLens;
export 'src/widgets/stepper.dart' show MorphStepper, MorphStepperStyle;
export 'src/widgets/switch.dart' show MorphSwitch, MorphSwitchStyle;
export 'src/widgets/switch_motion.dart' show MorphSwitchMotion;
export 'src/widgets/tab_bar.dart'
    show MorphTabBar, MorphTabBarStyle, MorphTabItem;
export 'src/widgets/toolbar.dart' show MorphToolbar;
export 'src/widgets/typography.dart' show MorphTypography;
export 'src/widgets/widgets_theme.dart' show MorphWidgetsTheme;
export 'src/widgets/zoom_motion.dart' show MorphZoomMotion, MorphZoomTuning;
