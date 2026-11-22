import 'package:material_ui/material_ui.dart';

import 'primitives.dart';

abstract final class AppGradients {
  static const LinearGradient primary = LinearGradient(
    colors: <Color>[Primitives.forest, Primitives.forestLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient growth(Brightness brightness) => LinearGradient(
        colors: brightness == Brightness.light
            ? <Color>[
                Primitives.surfaceElectric,
                Primitives.surfaceElectricStrong,
              ]
            : <Color>[
                Primitives.surfaceElectricDark,
                Primitives.surfaceElectricStrongDark,
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient attention(Brightness brightness) => LinearGradient(
        colors: brightness == Brightness.light
            ? <Color>[
                Primitives.surfaceCoral,
                Primitives.surfaceCoralStrong,
              ]
            : <Color>[
                Primitives.surfaceCoralDark,
                Primitives.surfaceCoralStrongDark,
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}
