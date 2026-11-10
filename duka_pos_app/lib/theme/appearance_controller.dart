import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// The user's appearance preference.
///
/// [system] follows the OS brightness. [light] and [dark] override it.
enum AppearanceMode { system, light, dark }

/// The appearance preference, persisted locally and read before the first
/// frame so there is no flash of the wrong brightness.
///
/// Provided exactly once at the composition root (see `lib/main.dart`).
/// Screens read it through `AppearanceController.of(context)`.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._prefs) {
    _mode = _parseMode(_prefs.getString(_key));
  }

  static const String _key = 'appearance_mode';

  final SharedPreferences _prefs;

  /// Loads the stored preference before `runApp`, so the first frame is
  /// already correct and there is no bright-to-dark flash.
  static Future<AppearanceController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppearanceController(prefs);
  }

  AppearanceMode _mode = AppearanceMode.system;

  AppearanceMode get mode => _mode;

  /// The effective [ThemeMode] for `MaterialApp.themeMode`.
  ///
  /// `system` follows the OS. `light` and `dark` override it.
  ThemeMode get themeMode => switch (_mode) {
        AppearanceMode.system => ThemeMode.system,
        AppearanceMode.light => ThemeMode.light,
        AppearanceMode.dark => ThemeMode.dark,
      };

  /// Chooses the `AppColors` constructor for the given brightness and
  /// contrast.
  AppColors colorsFor({
    required Brightness brightness,
    required bool highContrast,
  }) {
    if (highContrast) {
      switch (brightness) {
        case Brightness.light:
          return const AppColors.highContrastLight();
        case Brightness.dark:
          return const AppColors.highContrastDark();
      }
    }
    switch (brightness) {
      case Brightness.light:
        return const AppColors.light();
      case Brightness.dark:
        return const AppColors.dark();
    }
  }

  /// Sets the appearance mode and persists it. Notifies listeners so the
  /// theme rebuilds immediately.
  Future<void> setMode(AppearanceMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _prefs.setString(_key, _modeName(mode));
    notifyListeners();
  }

  AppearanceMode _parseMode(String? value) => switch (value) {
        'light' => AppearanceMode.light,
        'dark' => AppearanceMode.dark,
        _ => AppearanceMode.system,
      };

  /// Reads the controller from the nearest provider. Asserts rather than
  /// falling back: a missing provider means the app was built wrong.
  static AppearanceController of(BuildContext context) {
    final controller = context.read<AppearanceController?>();
    assert(
      controller != null,
      'AppearanceController missing. Provide it at the composition root in '
      'lib/main.dart before MaterialApp.router.',
    );
    return controller!;
  }

  static String _modeName(AppearanceMode mode) => switch (mode) {
        AppearanceMode.system => 'system',
        AppearanceMode.light => 'light',
        AppearanceMode.dark => 'dark',
      };
}
