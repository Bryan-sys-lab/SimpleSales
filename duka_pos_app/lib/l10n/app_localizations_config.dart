import 'package:flutter/widgets.dart' show LocalizationsDelegate;
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'generated/app_localizations.dart';

// Use the delegates that provide the MaterialLocalizations types used by the
// material_ui and cupertino_ui packages, not Flutter's legacy Material types.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
