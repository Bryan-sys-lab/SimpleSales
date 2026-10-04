import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/excel_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

/// First-run walkthrough. Shown once per shop workspace, after local account
/// creation and before the PIN lock screen.
///
/// Every step is skippable and works with no internet: nothing here calls the
/// backend. Google Sheets import is intentionally NOT offered here because it
/// requires a Google account connection that is set up later in Settings;
/// offering it on a fresh install would always fail.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingScreen({super.key, this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _lastStep = 3;

  int _step = 0;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _isFirst => _step == 0;
  bool get _isLast => _step == _lastStep;

  Future<void> _importExcel() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ExcelService().importInventory();
      if (!mounted) return;
      final refused = result.refusedBarcodes;
      setState(() {
        _messageIsError = result.products == 0;
        _message = result.products == 0
            ? 'No products were found in that workbook.'
            : refused.isEmpty
                // Refused barcodes are named by product, because "duplicate
                // barcode" tells the owner nothing about which row to fix.
                ? 'Imported ${result.products} products.'
                : 'Imported ${result.products} products. '
                    '${refused.length} barcode(s) were already on another '
                    'product and were left alone.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message =
            'That workbook has invalid inventory data. Nothing was imported.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'That file could not be read. Check it and try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'onboarding_completed_${await WorkspaceService.activeWorkspaceKey()}',
      true,
    );
    if (!mounted) return;
    widget.onComplete?.call();
    context.read<AppState>().refresh();
  }

  void _next() => _isLast ? _finish() : setState(() => _step++);

  void _back() => setState(() => _step--);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                _ProgressHeader(step: _step, total: _lastStep + 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: _buildStep(),
                  ),
                ),
                _Footer(
                  isFirst: _isFirst,
                  isLast: _isLast,
                  busy: _busy,
                  onBack: _back,
                  onNext: _next,
                  onSkip: _finish,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
        0 => const _InfoStep(
            icon: Icons.storefront_outlined,
            title: 'Welcome to Duka POS',
            body:
                'Duka POS keeps selling when the internet does not. Sales, stock, staff, and reports are stored on this phone first, so your till keeps working with no signal.',
          ),
        1 => const _InfoStep(
            icon: Icons.verified_user_outlined,
            title: 'Your account and your shop',
            body:
                'The email you entered identifies this shop to the online services. Your 4-digit PIN is what unlocks the till on this device — it never leaves the phone.\n\nM-Pesa and analytics need an internet connection the first time. Until then, cash sales work exactly the same, and you can connect later from Settings.',
          ),
        2 => _inventoryStep(),
        _ => const _InfoStep(
            icon: Icons.check_circle_outline,
            title: 'You are ready',
            body:
                'Start selling straight away. You can import more inventory, add managers and cashiers, and connect optional online services from Settings at any time.',
          ),
      };

  Widget _inventoryStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoStep(
            icon: Icons.inventory_2_outlined,
            title: 'Bring in your inventory',
            body:
                'Import an Excel workbook to get set up quickly, or skip this and add products one at a time. You can also connect a Google Sheet later in Settings.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _importExcel,
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Import Excel workbook'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _messageIsError
                      ? Theme.of(context).colorScheme.error
                      : DukaColors.success,
                ),
              ),
            ),
          ],
        ],
      );
}

class _ProgressHeader extends StatelessWidget {
  final int step;
  final int total;

  const _ProgressHeader({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${step + 1} of $total',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Row(
          children: List.generate(
            total,
            (index) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: index <= step
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Text(body, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Footer({
    required this.isFirst,
    required this.isLast,
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          if (!isFirst)
            TextButton.icon(
              onPressed: busy ? null : onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            )
          else
            TextButton(
              onPressed: busy ? null : onSkip,
              child: const Text('Skip'),
            ),
          const Spacer(),
          FilledButton(
            onPressed: busy ? null : onNext,
            child: Text(isLast ? 'Start selling' : 'Continue'),
          ),
        ],
      ),
    );
  }
}
