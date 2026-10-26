import 'package:duka_pos/screens/sync_center_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('cashiers cannot open Sync Center', (tester) async {
    await tester.pumpApp(home: const SyncCenterScreen());
    await tester.pump();

    expect(find.text('Only a manager can view Sync Center.'), findsOneWidget);
  });
}
