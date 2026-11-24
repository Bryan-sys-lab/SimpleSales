import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/theme/appearance_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved appearance loads after the default controller is available',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'appearance_mode': 'dark',
    });
    final AppearanceController controller = AppearanceController();

    expect(controller.mode, AppearanceMode.system);

    await controller.loadPreference();

    expect(controller.mode, AppearanceMode.dark);
  });

  test('a choice before preference loading overrides the saved value',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'appearance_mode': 'dark',
    });
    final AppearanceController controller = AppearanceController();

    await controller.setMode(AppearanceMode.system);
    await controller.loadPreference();

    expect(controller.mode, AppearanceMode.system);
  });
}
