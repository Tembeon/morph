import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

const _color = Color(0xFF123456);
const _number = 123.25;
const _style = TextStyle(fontSize: 99);

final class _Case<T extends Object> {
  const _Case(this.base, this.copy, this.fields, {this.hasEquality = true});

  final T base;
  final T Function(T) copy;
  final Map<String, (Object? Function(T), Object? Function(T), Object?)> fields;
  final bool hasEquality;

  void run() {
    group('$T', () {
      test('copyWith() with no arguments returns an equal object', () {
        final copy = this.copy(base);
        for (final (read, _, _) in fields.values) {
          expect(read(copy), read(base));
        }
        if (hasEquality) {
          expect(copy, base);
          expect(copy.hashCode, base.hashCode);
        }
      });
      for (final MapEntry(key: name, value: (_, override, expected))
          in fields.entries) {
        test('copyWith($name:) takes effect', () {
          expect(override(base), expected);
        });
      }
    });
  }
}

void main() {
  final cases = <_Case<Object>>[
    _Case<MorphActivityIndicatorAppearance>(
      MorphActivityIndicatorAppearance.light,
      (a) => a.copyWith(),
      {
        'color': (
          (a) => a.color,
          (a) => a.copyWith(color: _color).color,
          _color,
        ),
      },
    ),
    _Case<MorphAlertAppearance>(
      MorphAlertAppearance.light,
      (a) => a.copyWith(),
      {
        'platterColor': (
          (a) => a.platterColor,
          (a) => a.copyWith(platterColor: _color).platterColor,
          _color,
        ),
        'dimmingColor': (
          (a) => a.dimmingColor,
          (a) => a.copyWith(dimmingColor: _color).dimmingColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'titleColor': (
          (a) => a.titleColor,
          (a) => a.copyWith(titleColor: _color).titleColor,
          _color,
        ),
        'messageColor': (
          (a) => a.messageColor,
          (a) => a.copyWith(messageColor: _color).messageColor,
          _color,
        ),
        'buttonColor': (
          (a) => a.buttonColor,
          (a) => a.copyWith(buttonColor: _color).buttonColor,
          _color,
        ),
        'labelColor': (
          (a) => a.labelColor,
          (a) => a.copyWith(labelColor: _color).labelColor,
          _color,
        ),
        'destructiveColor': (
          (a) => a.destructiveColor,
          (a) => a.copyWith(destructiveColor: _color).destructiveColor,
          _color,
        ),
        'preferredColor': (
          (a) => a.preferredColor,
          (a) => a.copyWith(preferredColor: _color).preferredColor,
          _color,
        ),
        'preferredLabelColor': (
          (a) => a.preferredLabelColor,
          (a) => a.copyWith(preferredLabelColor: _color).preferredLabelColor,
          _color,
        ),
        'placeholderColor': (
          (a) => a.placeholderColor,
          (a) => a.copyWith(placeholderColor: _color).placeholderColor,
          _color,
        ),
        'disabledLabelColor': (
          (a) => a.disabledLabelColor,
          (a) => a.copyWith(disabledLabelColor: _color).disabledLabelColor,
          _color,
        ),
      },
    ),
    _Case<MorphBarAppearance>(MorphBarAppearance.light, (a) => a.copyWith(), {
      'capsuleColor': (
        (a) => a.capsuleColor,
        (a) => a.copyWith(capsuleColor: _color).capsuleColor,
        _color,
      ),
      'rimColor': (
        (a) => a.rimColor,
        (a) => a.copyWith(rimColor: _color).rimColor,
        _color,
      ),
      'shadowColor': (
        (a) => a.shadowColor,
        (a) => a.copyWith(shadowColor: _color).shadowColor,
        _color,
      ),
      'foregroundColor': (
        (a) => a.foregroundColor,
        (a) => a.copyWith(foregroundColor: _color).foregroundColor,
        _color,
      ),
      'prominentColor': (
        (a) => a.prominentColor,
        (a) => a.copyWith(prominentColor: _color).prominentColor,
        _color,
      ),
      'prominentForegroundColor': (
        (a) => a.prominentForegroundColor,
        (a) => a
            .copyWith(prominentForegroundColor: _color)
            .prominentForegroundColor,
        _color,
      ),
      'titleColor': (
        (a) => a.titleColor,
        (a) => a.copyWith(titleColor: _color).titleColor,
        _color,
      ),
      'subtitleColor': (
        (a) => a.subtitleColor,
        (a) => a.copyWith(subtitleColor: _color).subtitleColor,
        _color,
      ),
      'disabledIconColor': (
        (a) => a.disabledIconColor,
        (a) => a.copyWith(disabledIconColor: _color).disabledIconColor,
        _color,
      ),
      'disabledLabelColor': (
        (a) => a.disabledLabelColor,
        (a) => a.copyWith(disabledLabelColor: _color).disabledLabelColor,
        _color,
      ),
      'disabledProminentColor': (
        (a) => a.disabledProminentColor,
        (a) =>
            a.copyWith(disabledProminentColor: _color).disabledProminentColor,
        _color,
      ),
    }),
    _Case<MorphDatePickerAppearance>(
      MorphDatePickerAppearance.light,
      (a) => a.copyWith(),
      {
        'labelFillColor': (
          (a) => a.labelFillColor,
          (a) => a.copyWith(labelFillColor: _color).labelFillColor,
          _color,
        ),
        'labelColor': (
          (a) => a.labelColor,
          (a) => a.copyWith(labelColor: _color).labelColor,
          _color,
        ),
        'accentColor': (
          (a) => a.accentColor,
          (a) => a.copyWith(accentColor: _color).accentColor,
          _color,
        ),
        'platterColor': (
          (a) => a.platterColor,
          (a) => a.copyWith(platterColor: _color).platterColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'titleColor': (
          (a) => a.titleColor,
          (a) => a.copyWith(titleColor: _color).titleColor,
          _color,
        ),
        'weekdayColor': (
          (a) => a.weekdayColor,
          (a) => a.copyWith(weekdayColor: _color).weekdayColor,
          _color,
        ),
        'dayColor': (
          (a) => a.dayColor,
          (a) => a.copyWith(dayColor: _color).dayColor,
          _color,
        ),
        'todayFillColor': (
          (a) => a.todayFillColor,
          (a) => a.copyWith(todayFillColor: _color).todayFillColor,
          _color,
        ),
        'selectedDayColor': (
          (a) => a.selectedDayColor,
          (a) => a.copyWith(selectedDayColor: _color).selectedDayColor,
          _color,
        ),
        'selectedDayFillColor': (
          (a) => a.selectedDayFillColor,
          (a) => a.copyWith(selectedDayFillColor: _color).selectedDayFillColor,
          _color,
        ),
        'selectedDayTextColor': (
          (a) => a.selectedDayTextColor,
          (a) => a.copyWith(selectedDayTextColor: _color).selectedDayTextColor,
          _color,
        ),
        'chevronColor': (
          (a) => a.chevronColor,
          (a) => a.copyWith(chevronColor: _color).chevronColor,
          _color,
        ),
        'wheelBandColor': (
          (a) => a.wheelBandColor,
          (a) => a.copyWith(wheelBandColor: _color).wheelBandColor,
          _color,
        ),
        'wheelColor': (
          (a) => a.wheelColor,
          (a) => a.copyWith(wheelColor: _color).wheelColor,
          _color,
        ),
        'wheelFadedOpacity': (
          (a) => a.wheelFadedOpacity,
          (a) => a.copyWith(wheelFadedOpacity: _number).wheelFadedOpacity,
          _number,
        ),
        'unavailableDayOpacity': (
          (a) => a.unavailableDayOpacity,
          (a) =>
              a.copyWith(unavailableDayOpacity: _number).unavailableDayOpacity,
          _number,
        ),
      },
    ),
    _Case<MorphGlassButtonAppearance>(
      MorphGlassButtonAppearance.light,
      (a) => a.copyWith(),
      {
        'fillColor': (
          (a) => a.fillColor,
          (a) => a.copyWith(fillColor: _color).fillColor,
          _color,
        ),
        'clearFillColor': (
          (a) => a.clearFillColor,
          (a) => a.copyWith(clearFillColor: _color).clearFillColor,
          _color,
        ),
        'rimColor': (
          (a) => a.rimColor,
          (a) => a.copyWith(rimColor: _color).rimColor,
          _color,
        ),
        'prominentColor': (
          (a) => a.prominentColor,
          (a) => a.copyWith(prominentColor: _color).prominentColor,
          _color,
        ),
        'prominentRimColor': (
          (a) => a.prominentRimColor,
          (a) => a.copyWith(prominentRimColor: _color).prominentRimColor,
          _color,
        ),
        'foregroundColor': (
          (a) => a.foregroundColor,
          (a) => a.copyWith(foregroundColor: _color).foregroundColor,
          _color,
        ),
        'prominentForegroundColor': (
          (a) => a.prominentForegroundColor,
          (a) => a
              .copyWith(prominentForegroundColor: _color)
              .prominentForegroundColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'disabledForegroundColor': (
          (a) => a.disabledForegroundColor,
          (a) => a
              .copyWith(disabledForegroundColor: _color)
              .disabledForegroundColor,
          _color,
        ),
        'disabledTintColor': (
          (a) => a.disabledTintColor,
          (a) => a.copyWith(disabledTintColor: _color).disabledTintColor,
          _color,
        ),
      },
    ),
    _Case<MorphListAppearance>(MorphListAppearance.light, (a) => a.copyWith(), {
      'backgroundColor': (
        (a) => a.backgroundColor,
        (a) => a.copyWith(backgroundColor: _color).backgroundColor,
        _color,
      ),
      'cellColor': (
        (a) => a.cellColor,
        (a) => a.copyWith(cellColor: _color).cellColor,
        _color,
      ),
      'highlightColor': (
        (a) => a.highlightColor,
        (a) => a.copyWith(highlightColor: _color).highlightColor,
        _color,
      ),
      'separatorColor': (
        (a) => a.separatorColor,
        (a) => a.copyWith(separatorColor: _color).separatorColor,
        _color,
      ),
      'titleColor': (
        (a) => a.titleColor,
        (a) => a.copyWith(titleColor: _color).titleColor,
        _color,
      ),
      'secondaryColor': (
        (a) => a.secondaryColor,
        (a) => a.copyWith(secondaryColor: _color).secondaryColor,
        _color,
      ),
      'chevronColor': (
        (a) => a.chevronColor,
        (a) => a.copyWith(chevronColor: _color).chevronColor,
        _color,
      ),
      'iconColor': (
        (a) => a.iconColor,
        (a) => a.copyWith(iconColor: _color).iconColor,
        _color,
      ),
    }),
    _Case<MorphMenuAppearance>(MorphMenuAppearance.light, (a) => a.copyWith(), {
      'glassColor': (
        (a) => a.glassColor,
        (a) => a.copyWith(glassColor: _color).glassColor,
        _color,
      ),
      'shadowColor': (
        (a) => a.shadowColor,
        (a) => a.copyWith(shadowColor: _color).shadowColor,
        _color,
      ),
      'shadowElevation': (
        (a) => a.shadowElevation,
        (a) => a.copyWith(shadowElevation: _number).shadowElevation,
        _number,
      ),
      'textStyle': (
        (a) => a.textStyle,
        (a) => a.copyWith(textStyle: _style).textStyle,
        _style,
      ),
      'iconColor': (
        (a) => a.iconColor,
        (a) => a.copyWith(iconColor: _color).iconColor,
        _color,
      ),
      'disabledIconColor': (
        (a) => a.disabledIconColor,
        (a) => a.copyWith(disabledIconColor: _color).disabledIconColor,
        _color,
      ),
      'iconSize': (
        (a) => a.iconSize,
        (a) => a.copyWith(iconSize: _number).iconSize,
        _number,
      ),
      'destructiveColor': (
        (a) => a.destructiveColor,
        (a) => a.copyWith(destructiveColor: _color).destructiveColor,
        _color,
      ),
      'highlightColor': (
        (a) => a.highlightColor,
        (a) => a.copyWith(highlightColor: _color).highlightColor,
        _color,
      ),
      'glowColor': (
        (a) => a.glowColor,
        (a) => a.copyWith(glowColor: _color).glowColor,
        _color,
      ),
      'secondaryColor': (
        (a) => a.secondaryColor,
        (a) => a.copyWith(secondaryColor: _color).secondaryColor,
        _color,
      ),
      'disabledColor': (
        (a) => a.disabledColor,
        (a) => a.copyWith(disabledColor: _color).disabledColor,
        _color,
      ),
      'separatorColor': (
        (a) => a.separatorColor,
        (a) => a.copyWith(separatorColor: _color).separatorColor,
        _color,
      ),
      'submenuColor': (
        (a) => a.submenuColor,
        (a) => a.copyWith(submenuColor: _color).submenuColor,
        _color,
      ),
      'glassTint': (
        (a) => a.glassTint,
        (a) => a.copyWith(glassTint: _color).glassTint,
        _color,
      ),
      'submenuRimColor': (
        (a) => a.submenuRimColor,
        (a) => a.copyWith(submenuRimColor: _color).submenuRimColor,
        _color,
      ),
      'submenuShadowColor': (
        (a) => a.submenuShadowColor,
        (a) => a.copyWith(submenuShadowColor: _color).submenuShadowColor,
        _color,
      ),
      'paletteSelectionColor': (
        (a) => a.paletteSelectionColor,
        (a) => a.copyWith(paletteSelectionColor: _color).paletteSelectionColor,
        _color,
      ),
    }, hasEquality: false),
    _Case<MorphPageControlAppearance>(
      MorphPageControlAppearance.light,
      (a) => a.copyWith(),
      {
        'pageIndicatorColor': (
          (a) => a.pageIndicatorColor,
          (a) => a.copyWith(pageIndicatorColor: _color).pageIndicatorColor,
          _color,
        ),
        'currentPageIndicatorColor': (
          (a) => a.currentPageIndicatorColor,
          (a) => a
              .copyWith(currentPageIndicatorColor: _color)
              .currentPageIndicatorColor,
          _color,
        ),
        'platterColor': (
          (a) => a.platterColor,
          (a) => a.copyWith(platterColor: _color).platterColor,
          _color,
        ),
        'platterIndicatorColor': (
          (a) => a.platterIndicatorColor,
          (a) =>
              a.copyWith(platterIndicatorColor: _color).platterIndicatorColor,
          _color,
        ),
      },
    ),
    _Case<MorphProgressViewAppearance>(
      MorphProgressViewAppearance.light,
      (a) => a.copyWith(),
      {
        'inactiveTrackColor': (
          (a) => a.inactiveTrackColor,
          (a) => a.copyWith(inactiveTrackColor: _color).inactiveTrackColor,
          _color,
        ),
        'activeTrackColor': (
          (a) => a.activeTrackColor,
          (a) => a.copyWith(activeTrackColor: _color).activeTrackColor,
          _color,
        ),
      },
    ),
    _Case<MorphScrollEdgeEffectAppearance>(
      MorphScrollEdgeEffectAppearance.light,
      (a) => a.copyWith(),
      {
        'backgroundColor': (
          (a) => a.backgroundColor,
          (a) => a.copyWith(backgroundColor: _color).backgroundColor,
          _color,
        ),
        'fadeOpacity': (
          (a) => a.fadeOpacity,
          (a) => a.copyWith(fadeOpacity: _number).fadeOpacity,
          _number,
        ),
        'separatorColor': (
          (a) => a.separatorColor,
          (a) => a.copyWith(separatorColor: _color).separatorColor,
          _color,
        ),
        'softBlurRadius': (
          (a) => a.softBlurRadius,
          (a) => a.copyWith(softBlurRadius: _number).softBlurRadius,
          _number,
        ),
        'hardBlurRadius': (
          (a) => a.hardBlurRadius,
          (a) => a.copyWith(hardBlurRadius: _number).hardBlurRadius,
          _number,
        ),
        'softOverhang': (
          (a) => a.softOverhang,
          (a) => a.copyWith(softOverhang: _number).softOverhang,
          _number,
        ),
        'softFadeStart': (
          (a) => a.softFadeStart,
          (a) => a.copyWith(softFadeStart: _number).softFadeStart,
          _number,
        ),
        'hardSaturation': (
          (a) => a.hardSaturation,
          (a) => a.copyWith(hardSaturation: _number).hardSaturation,
          _number,
        ),
        'hardBrightness': (
          (a) => a.hardBrightness,
          (a) => a.copyWith(hardBrightness: _number).hardBrightness,
          _number,
        ),
      },
    ),
    _Case<MorphSearchFieldAppearance>(
      MorphSearchFieldAppearance.light,
      (a) => a.copyWith(),
      {
        'capsuleColor': (
          (a) => a.capsuleColor,
          (a) => a.copyWith(capsuleColor: _color).capsuleColor,
          _color,
        ),
        'rimColor': (
          (a) => a.rimColor,
          (a) => a.copyWith(rimColor: _color).rimColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'textColor': (
          (a) => a.textColor,
          (a) => a.copyWith(textColor: _color).textColor,
          _color,
        ),
        'placeholderColor': (
          (a) => a.placeholderColor,
          (a) => a.copyWith(placeholderColor: _color).placeholderColor,
          _color,
        ),
        'restingPlaceholderColor': (
          (a) => a.restingPlaceholderColor,
          (a) => a
              .copyWith(restingPlaceholderColor: _color)
              .restingPlaceholderColor,
          _color,
        ),
        'glyphColor': (
          (a) => a.glyphColor,
          (a) => a.copyWith(glyphColor: _color).glyphColor,
          _color,
        ),
        'clearColor': (
          (a) => a.clearColor,
          (a) => a.copyWith(clearColor: _color).clearColor,
          _color,
        ),
        'clearGlyphColor': (
          (a) => a.clearGlyphColor,
          (a) => a.copyWith(clearGlyphColor: _color).clearGlyphColor,
          _color,
        ),
        'cursorColor': (
          (a) => a.cursorColor,
          (a) => a.copyWith(cursorColor: _color).cursorColor,
          _color,
        ),
        'disabledFillColor': (
          (a) => a.disabledFillColor,
          (a) => a.copyWith(disabledFillColor: _color).disabledFillColor,
          _color,
        ),
        'stackedFillColor': (
          (a) => a.stackedFillColor,
          (a) => a.copyWith(stackedFillColor: _color).stackedFillColor,
          _color,
        ),
      },
    ),
    _Case<MorphSegmentedControlAppearance>(
      MorphSegmentedControlAppearance.light,
      (a) => a.copyWith(),
      {
        'height': (
          (a) => a.height,
          (a) => a.copyWith(height: _number).height,
          _number,
        ),
        'inset': (
          (a) => a.inset,
          (a) => a.copyWith(inset: _number).inset,
          _number,
        ),
        'trackColor': (
          (a) => a.trackColor,
          (a) => a.copyWith(trackColor: _color).trackColor,
          _color,
        ),
        'lensColor': (
          (a) => a.lensColor,
          (a) => a.copyWith(lensColor: _color).lensColor,
          _color,
        ),
        'liftedLensColor': (
          (a) => a.liftedLensColor,
          (a) => a.copyWith(liftedLensColor: _color).liftedLensColor,
          _color,
        ),
        'lensBorderColor': (
          (a) => a.lensBorderColor,
          (a) => a.copyWith(lensBorderColor: _color).lensBorderColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'textStyle': (
          (a) => a.textStyle,
          (a) => a.copyWith(textStyle: _style).textStyle,
          _style,
        ),
        'selectedTextStyle': (
          (a) => a.selectedTextStyle,
          (a) => a.copyWith(selectedTextStyle: _style).selectedTextStyle,
          _style,
        ),
        'contentPadding': (
          (a) => a.contentPadding,
          (a) => a.copyWith(contentPadding: _number).contentPadding,
          _number,
        ),
        'disabledOpacity': (
          (a) => a.disabledOpacity,
          (a) => a.copyWith(disabledOpacity: _number).disabledOpacity,
          _number,
        ),
      },
    ),
    _Case<MorphSheetAppearance>(
      MorphSheetAppearance.light,
      (a) => a.copyWith(),
      {
        'dockedColor': (
          (a) => a.dockedColor,
          (a) => a.copyWith(dockedColor: _color).dockedColor,
          _color,
        ),
        'floatingColor': (
          (a) => a.floatingColor,
          (a) => a.copyWith(floatingColor: _color).floatingColor,
          _color,
        ),
        'grabberColor': (
          (a) => a.grabberColor,
          (a) => a.copyWith(grabberColor: _color).grabberColor,
          _color,
        ),
        'dimmingColor': (
          (a) => a.dimmingColor,
          (a) => a.copyWith(dimmingColor: _color).dimmingColor,
          _color,
        ),
        'textColor': (
          (a) => a.textColor,
          (a) => a.copyWith(textColor: _color).textColor,
          _color,
        ),
      },
    ),
    _Case<MorphSliderAppearance>(
      MorphSliderAppearance.light,
      (a) => a.copyWith(),
      {
        'activeTrackColor': (
          (a) => a.activeTrackColor,
          (a) => a.copyWith(activeTrackColor: _color).activeTrackColor,
          _color,
        ),
        'inactiveTrackColor': (
          (a) => a.inactiveTrackColor,
          (a) => a.copyWith(inactiveTrackColor: _color).inactiveTrackColor,
          _color,
        ),
        'thumbColor': (
          (a) => a.thumbColor,
          (a) => a.copyWith(thumbColor: _color).thumbColor,
          _color,
        ),
        'tickColor': (
          (a) => a.tickColor,
          (a) => a.copyWith(tickColor: _color).tickColor,
          _color,
        ),
        'disabledOpacity': (
          (a) => a.disabledOpacity,
          (a) => a.copyWith(disabledOpacity: _number).disabledOpacity,
          _number,
        ),
      },
    ),
    _Case<MorphStepperAppearance>(
      MorphStepperAppearance.light,
      (a) => a.copyWith(),
      {
        'backgroundColor': (
          (a) => a.backgroundColor,
          (a) => a.copyWith(backgroundColor: _color).backgroundColor,
          _color,
        ),
        'foregroundColor': (
          (a) => a.foregroundColor,
          (a) => a.copyWith(foregroundColor: _color).foregroundColor,
          _color,
        ),
        'limitForegroundColor': (
          (a) => a.limitForegroundColor,
          (a) => a.copyWith(limitForegroundColor: _color).limitForegroundColor,
          _color,
        ),
        'pressedOverlay': (
          (a) => a.pressedOverlay,
          (a) => a.copyWith(pressedOverlay: _color).pressedOverlay,
          _color,
        ),
        'pressedReplacesFill': (
          (a) => a.pressedReplacesFill,
          (a) => a
              .copyWith(pressedReplacesFill: !a.pressedReplacesFill)
              .pressedReplacesFill,
          !MorphStepperAppearance.light.pressedReplacesFill,
        ),
        'dividerColor': (
          (a) => a.dividerColor,
          (a) => a.copyWith(dividerColor: _color).dividerColor,
          _color,
        ),
        'dividerHeight': (
          (a) => a.dividerHeight,
          (a) => a.copyWith(dividerHeight: _number).dividerHeight,
          _number,
        ),
      },
    ),
    _Case<MorphSwitchAppearance>(
      MorphSwitchAppearance.light,
      (a) => a.copyWith(),
      {
        'activeTrackColor': (
          (a) => a.activeTrackColor,
          (a) => a.copyWith(activeTrackColor: _color).activeTrackColor,
          _color,
        ),
        'inactiveTrackColor': (
          (a) => a.inactiveTrackColor,
          (a) => a.copyWith(inactiveTrackColor: _color).inactiveTrackColor,
          _color,
        ),
        'thumbColor': (
          (a) => a.thumbColor,
          (a) => a.copyWith(thumbColor: _color).thumbColor,
          _color,
        ),
        'disabledOpacity': (
          (a) => a.disabledOpacity,
          (a) => a.copyWith(disabledOpacity: _number).disabledOpacity,
          _number,
        ),
      },
    ),
    _Case<MorphTabBarAppearance>(
      MorphTabBarAppearance.light,
      (a) => a.copyWith(),
      {
        'barColor': (
          (a) => a.barColor,
          (a) => a.copyWith(barColor: _color).barColor,
          _color,
        ),
        'shadowColor': (
          (a) => a.shadowColor,
          (a) => a.copyWith(shadowColor: _color).shadowColor,
          _color,
        ),
        'platterColor': (
          (a) => a.platterColor,
          (a) => a.copyWith(platterColor: _color).platterColor,
          _color,
        ),
        'liftedLensColor': (
          (a) => a.liftedLensColor,
          (a) => a.copyWith(liftedLensColor: _color).liftedLensColor,
          _color,
        ),
        'lensBorderColor': (
          (a) => a.lensBorderColor,
          (a) => a.copyWith(lensBorderColor: _color).lensBorderColor,
          _color,
        ),
        'selectedColor': (
          (a) => a.selectedColor,
          (a) => a.copyWith(selectedColor: _color).selectedColor,
          _color,
        ),
        'color': (
          (a) => a.color,
          (a) => a.copyWith(color: _color).color,
          _color,
        ),
        'blurSigma': (
          (a) => a.blurSigma,
          (a) => a.copyWith(blurSigma: _number).blurSigma,
          _number,
        ),
      },
    ),
  ];
  for (final c in cases) {
    c.run();
  }
}
