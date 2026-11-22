import 'package:material_ui/material_ui.dart';

import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../theme/app_spacing.dart';

Future<void> showStaffPinChangeDialog(BuildContext context, AppState state) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  bool saving = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> submit() async {
          if (state.currentStaffId == null || current.text.length != 4 || next.text.length != 4 || confirm.text != next.text) {
            setState(() => error = 'Enter four digits and make the new PINs match.');
            return;
          }
          setState(() { saving = true; error = null; });
          try {
            await BackendService.changeStaffPin(staffId: state.currentStaffId!, currentPin: current.text, newPin: next.text);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (_) {
            if (dialogContext.mounted) setState(() { saving = false; error = 'PIN change failed. Check your current PIN and connection.'; });
          }
        }
        Widget field(String label, TextEditingController controller) => Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.of(context).md),
          child: TextField(controller: controller, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, decoration: InputDecoration(labelText: label, counterText: '')),
        );
        return AlertDialog(
          title: const Text('Change my PIN'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Text('Only you can change this PIN. Keep it private.'),
            SizedBox(height: AppSpacing.of(context).lg),
            field('Current PIN', current), field('New PIN', next), field('Confirm new PIN', confirm),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
          actions: <Widget>[
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: saving ? null : submit, child: Text(saving ? 'Saving…' : 'Save PIN')),
          ],
        );
      },
    ),
  );
  current.dispose(); next.dispose(); confirm.dispose();
}
