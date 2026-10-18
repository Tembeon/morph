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
