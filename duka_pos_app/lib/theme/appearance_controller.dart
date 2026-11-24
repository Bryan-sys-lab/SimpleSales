import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// The user's appearance preference.
///
/// [system] follows the OS brightness. [light] and [dark] override it.
enum AppearanceMode { system, light, dark }

/// The appearance preference, persisted locally and applied when preferences
/// become available.
///
/// Provided exactly once at the composition root (see `lib/main.dart`).
/// Screens read it through `AppearanceController.of(context)`.
class AppearanceController extends ChangeNotifier {
  AppearanceController([SharedPreferences? prefs]) : _prefs = prefs {
    _mode = _parseMode(_prefs?.getString(_key));
  }

  static const String _key = 'appearance_mode';

  SharedPreferences? _prefs;
  int _changeGeneration = 0;

  /// Loads the stored preference for callers that need a hydrated controller
  /// before constructing the app.
  static Future<AppearanceController> load() async {
    final controller = AppearanceController();
    await controller.loadPreference();
    return controller;
  }

  /// Hydrates the saved preference without requiring it to block the first
  /// frame. A user choice made while preferences are loading takes precedence.
  Future<void> loadPreference() async {
    final int generation = _changeGeneration;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    if (generation != _changeGeneration) return;
    final AppearanceMode mode = _parseMode(prefs.getString(_key));
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
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
    if (_mode == mode && _prefs != null) return;
    _mode = mode;
    _changeGeneration++;
    final SharedPreferences prefs =
        _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(_key, _modeName(mode));
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
