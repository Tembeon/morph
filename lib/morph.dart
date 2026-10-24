/// iOS 27 Liquid Glass widgets for Flutter: the measured controls, their
/// presentations and the theme that picks their glass.
///
/// Wrap the app in a [MorphTheme] above its navigator; see the package
/// README.
library;

export 'src/presentation.dart' show MorphPresentationBoundary;
export 'src/widgets/control_state.dart'
    show MorphControlState, MorphControlBuilder;
export 'src/scope.dart' show MorphSource, MorphSourceLink;
export 'src/theme/glass.dart' show MorphGlassRenderer, MorphGlassTier;
export 'src/theme/localizations.dart'
    show DefaultMorphLocalizations, MorphLocalizations;
export 'src/theme/surface_borders.dart' show MorphSurfaceBorders;
export 'src/theme/theme.dart' show MorphAppearance, MorphThemeData;
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
        MorphAlertTextField,
        showMorphActionSheet,
        showMorphAlert;
export 'src/widgets/badge.dart' show MorphBadge;
export 'src/widgets/bar_items.dart'
    show
        MorphBarAppearance,
        MorphBarButton,
        MorphBarButtonGroup,
        MorphBarButtonStyle;
export 'src/widgets/date_picker.dart'
    show
        MorphDatePicker,
        MorphDatePickerAppearance,
        MorphDatePickerLocalizations,
        MorphDatePickerMode,
        MorphDatePickerStyle;
export 'src/widgets/glass_button.dart'
    show MorphGlassButton, MorphGlassButtonAppearance;
export 'src/widgets/glass_container.dart' show MorphGlassContainer;
export 'src/widgets/glass_effect.dart' show MorphGlassEffect;
export 'src/widgets/glass_renderer.dart' show MorphGlassStyle;
export 'src/widgets/list.dart'
    show
        MorphListAccessory,
        MorphListAppearance,
        MorphListBackground,
        MorphListRow,
        MorphListSection,
        MorphSliverListSection;
export 'src/widgets/menu.dart'
    show
        MorphMenuAppearance,
        MorphMenuButton,
        MorphMenuSource,
        MorphMenuTrigger;
export 'src/widgets/menu_presentation.dart'
    show MorphMenuPresentationController;
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
export 'src/widgets/morph_context_menu.dart'
    show MorphContextMenuRegion, MorphSatellite;
export 'src/widgets/morph_theme.dart' show MorphTheme;
export 'src/widgets/navigation_bar.dart'
    show MorphLargeTitle, MorphNavigationBar;
export 'src/widgets/navigation_stack.dart'
    show
        MorphBackButtonDisplayMode,
        MorphLargeTitleDisplayMode,
        MorphNavigationBarHiding,
        MorphNavigationConfig,
        MorphNavigationPage,
        MorphNavigationRoute,
        MorphNavigationScaffold,
        MorphNavigationStack;
export 'src/widgets/page_control.dart'
    show
        MorphPageControl,
        MorphPageControlAppearance,
        MorphPageControlBackgroundStyle;
export 'src/widgets/progress.dart'
    show MorphProgressView, MorphProgressViewAppearance, MorphProgressViewStyle;
export 'src/widgets/scroll_edge_effect.dart'
    show
        MorphScrollEdgeEffect,
        MorphScrollEdgeEffectAppearance,
        MorphScrollEdgeEffectStyle;
export 'src/widgets/scroll_indicator.dart' show MorphScrollIndicator;
export 'src/widgets/search_field.dart'
    show MorphSearchField, MorphSearchFieldAppearance, MorphSearchToolbar;
export 'src/widgets/search_stacked.dart' show MorphNavigationSearch;
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
    show
        MorphTabBar,
        MorphTabBarAppearance,
        MorphTabItem,
        MorphTabRole,
        MorphTabReplicaBuilder;
export 'src/widgets/tab_bar_chrome.dart'
    show
        MorphContentScroll,
        MorphContentScrollScope,
        MorphTabAccessoryEnvironment;
export 'src/widgets/tab_bar_minimize.dart' show MorphTabBarMinimizeBehavior;
export 'src/widgets/touch_feedback.dart'
    show MorphTouchTarget, MorphTouchFeedback;
export 'src/widgets/toolbar.dart' show MorphToolbar;
export 'src/widgets/typography.dart' show MorphTypography;
