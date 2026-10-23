import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The strings morph's controls announce and show.
///
/// English by default; an app supplies its own through
/// [WidgetsApp.localizationsDelegates] with a delegate that loads a
/// subclass for its locales.
abstract class MorphLocalizations {
  /// Creates the strings.
  const MorphLocalizations();

  /// The screen-reader label of a dimming layer that closes what it
  /// covers.
  String get dismissLabel;

  /// The placeholder of an empty search field.
  String get searchPlaceholder;

  /// The label of a search field's clear button.
  String get clearTextLabel => 'Clear text';

  /// The label of a control that starts a search.
  String get searchLabel;

  /// The label of a control that closes a search or a sheet.
  String get closeLabel;

  /// The label of a navigation bar's back button.
  String get backLabel;

  /// The label of a spinning activity indicator.
  String get inProgressLabel;

  /// The label of a list row's detail button.
  String get moreInfoLabel;

  /// The label of a stepper's minus button.
  String get decrementLabel;

  /// The label of a stepper's plus button.
  String get incrementLabel;

  /// The nearest strings, or English.
  static MorphLocalizations of(BuildContext context) =>
      Localizations.of<MorphLocalizations>(context, MorphLocalizations) ??
      const DefaultMorphLocalizations();
}

/// morph's English strings.
class DefaultMorphLocalizations extends MorphLocalizations {
  /// Creates the English strings.
  const DefaultMorphLocalizations();

  @override
  String get dismissLabel => 'Dismiss';

  @override
  String get searchPlaceholder => 'Search';

  @override
  String get searchLabel => 'Search';

  @override
  String get closeLabel => 'Close';

  @override
  String get backLabel => 'Back';

  @override
  String get inProgressLabel => 'In progress';

  @override
  String get moreInfoLabel => 'More info';

  @override
  String get decrementLabel => 'Decrement';

  @override
  String get incrementLabel => 'Increment';

  /// Loads the English strings for every locale.
  static const LocalizationsDelegate<MorphLocalizations> delegate =
      _DefaultMorphLocalizationsDelegate();
}

class _DefaultMorphLocalizationsDelegate
    extends LocalizationsDelegate<MorphLocalizations> {
  const _DefaultMorphLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MorphLocalizations> load(Locale locale) =>
      SynchronousFuture<MorphLocalizations>(const DefaultMorphLocalizations());

  @override
  bool shouldReload(_DefaultMorphLocalizationsDelegate old) => false;
}
