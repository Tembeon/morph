/// The widget layer: controls that move like iOS Liquid Glass, measured
/// from UIKit and reproduced, plus the recipes that put the morph engine
/// to work - a held surface becoming its own context menu.
///
/// Every motion value here is read from UIKit's tuning on iOS 27 or
/// fitted to frame-by-frame recordings of the real controls, and each
/// control is checked against those recordings: the selection lens of
/// [MorphSegmentedControl] and [MorphTabBar], [MorphSwitch],
/// [MorphSlider], [MorphStepper], the press of [MorphGlassButton] and
/// the button that becomes its own menu, [MorphMenuButton], and any
/// widget that does, [MorphMenuSource]. The motion objects behind them
/// (`MorphLensMotion`, `MorphGlassButtonMotion`, `MorphMenuMotion` and
/// their kin) are pure functions of explicit time, usable without the
/// widgets; they live in `package:morph/motion.dart` with the measured
/// tuning and layout types. A custom glass painter finds the surface
/// description it shades in `package:morph/glass_painter.dart`.
///
/// Everything here is built on `package:morph/foundation.dart`, motor and
/// the package's glass renderer; the engine never depends on this layer.
/// The controls draw flat fills by default; [MorphGlassRenderer]
/// installed with [MorphGlassScope] (or [MorphAdaptiveGlass], which picks
/// its quality tier once by the device's GPU) draws them as liquid, fake or
/// flat glass, and any other [MorphGlassPainter] can take its place. The
/// package computes every shape once - fused silhouettes included - so
/// each tier and each painter shades the same outlines. Their looks
/// resolve from an `appearance` argument, then [MorphWidgetsTheme], then
/// light and dark tables.
library;

export 'foundation.dart';
export 'src/widgets/activity_indicator.dart'
    show
        MorphActivityIndicator,
        MorphActivityIndicatorAppearance,
        MorphActivityIndicatorSize;
export 'src/widgets/alert.dart'
    show
        MorphAlertAction,
        MorphAlertActionStyle,
        MorphAlertAppearance,
        MorphAlertRoute,
        MorphAlertTextField,
        showMorphActionSheet,
        showMorphAlert;
export 'src/widgets/badge.dart' show MorphBadge;
export 'src/widgets/bar_items.dart'
    show
        MorphBarAppearance,
        MorphBarButton,
        MorphBarButtonGroup,
        MorphBarButtonStyle,
        MorphBarMenuTuning,
        MorphBarMetrics;
export 'src/widgets/date_picker.dart'
    show
        MorphDatePicker,
        MorphDatePickerAppearance,
        MorphDatePickerLocalizations,
        MorphDatePickerMode,
        MorphDatePickerStyle;
export 'src/widgets/glass.dart' show MorphGlassPainter, MorphGlassScope;
export 'src/widgets/glass_button.dart'
    show MorphGlassButton, MorphGlassButtonAppearance;
export 'src/widgets/glass_container.dart' show MorphGlassContainer;
export 'src/widgets/glass_effect.dart' show MorphGlassEffect;
export 'src/widgets/glass_inspector.dart'
    show MorphGlassCensus, MorphGlassHint, MorphGlassInspector;
export 'src/widgets/glass_renderer.dart'
    show
        MorphGlassMaterial,
        MorphGlassRenderer,
        MorphGlassStyle,
        MorphGlassTier;
export 'src/widgets/glass_tier.dart'
    show MorphAdaptiveGlass, MorphGlassDeviceClass;
export 'src/widgets/list.dart'
    show
        MorphListAccessory,
        MorphListAppearance,
        MorphListMetrics,
        MorphListRow,
        MorphListSection,
        MorphSliverListSection;
export 'src/widgets/menu.dart'
    show
        MorphMenuAppearance,
        MorphMenuButton,
        MorphMenuSource,
        MorphMenuTrigger;
export 'src/widgets/menu_entries.dart'
    show
        MorphMenuDeferred,
        MorphMenuDivider,
        MorphMenuElementSize,
        MorphMenuEntry,
        MorphMenuIconVisibility,
        MorphMenuItem,
        MorphMenuOrder,
        MorphMenuSection,
        MorphMenuState,
        MorphMenuWidget,
        MorphSubmenu;
export 'src/widgets/menu_motion.dart' show MorphMenuTuning;
export 'src/widgets/morph_context_menu.dart'
    show MorphContextMenuRegion, MorphSatellite;
export 'src/widgets/navigation_bar.dart'
    show
        MorphLargeTitle,
        MorphLargeTitleScrollPhysics,
        MorphNavigationBar,
        MorphNavigationBarMetrics;
export 'src/widgets/navigation_stack.dart'
    show
        MorphBackButtonDisplayMode,
        MorphLargeTitleDisplayMode,
        MorphNavigationBarHiding,
        MorphNavigationConfig,
        MorphNavigationPage,
        MorphNavigationRoute,
        MorphNavigationScaffold,
        MorphNavigationStack,
        pushMorphZoom;
export 'src/widgets/page_control.dart'
    show
        MorphPageControl,
        MorphPageControlAppearance,
        MorphPageControlBackgroundStyle;
export 'src/widgets/progress.dart'
    show MorphProgressView, MorphProgressViewAppearance, MorphProgressViewStyle;
export 'src/widgets/push_zoom_motion.dart' show MorphPushZoomTuning;
export 'src/widgets/scroll_edge_effect.dart'
    show
        MorphScrollEdgeEffect,
        MorphScrollEdgeEffectAppearance,
        MorphScrollEdgeEffectStyle;
export 'src/widgets/scroll_indicator.dart'
    show MorphScrollIndicator, MorphScrollIndicatorTuning;
export 'src/widgets/search_field.dart'
    show MorphSearchField, MorphSearchFieldAppearance, MorphSearchToolbar;
export 'src/widgets/search_tab_bar.dart' show MorphSearchTabBar;
export 'src/widgets/segmented_control.dart'
    show MorphSegment, MorphSegmentedControl, MorphSegmentedControlAppearance;
export 'src/widgets/sheet.dart'
    show MorphSheet, MorphSheetAppearance, MorphSheetRoute, showMorphSheet;
export 'src/widgets/sheet_motion.dart' show MorphSheetDetent;
export 'src/widgets/slider.dart' show MorphSlider, MorphSliderAppearance;
export 'src/widgets/stepper.dart' show MorphStepper, MorphStepperAppearance;
export 'src/widgets/switch.dart' show MorphSwitch, MorphSwitchAppearance;
export 'src/widgets/tab_bar.dart'
    show MorphTabBar, MorphTabBarAppearance, MorphTabItem;
export 'src/widgets/tab_bar_chrome.dart'
    show
        MorphContentScroll,
        MorphContentScrollScope,
        MorphTabAccessoryEnvironment;
export 'src/widgets/tab_bar_minimize.dart' show MorphTabBarMinimizeBehavior;
export 'src/widgets/toolbar.dart' show MorphToolbar, MorphToolbarMetrics;
export 'src/widgets/typography.dart' show MorphTypography;
export 'src/widgets/widgets_theme.dart'
    show MorphWidgetsTheme, MorphWidgetsThemeScope;
export 'src/widgets/zoom_motion.dart' show MorphZoomTuning;
