import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/backend_service.dart';
import '../services/support_contact.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/simple_pos_mark.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/verification_message.dart';

/// The first-month voucher step shown immediately after the email code passes.
class SignupPaywallScreen extends StatefulWidget {
  const SignupPaywallScreen({required this.registration, super.key});

  final PendingRegistration registration;

  @override
  State<SignupPaywallScreen> createState() => _SignupPaywallScreenState();
}

class _SignupPaywallScreenState extends State<SignupPaywallScreen> {
  final TextEditingController _voucher = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _voucher.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_submitting) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String code = _voucher.text.trim();
    if (code.isEmpty) {
      setState(() => _error = l10n.signupPaywallVoucherRequired);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final PendingVerification pending =
          await BackendService.completePendingVerification(
        registration: widget.registration,
        voucherCode: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(pending);
    } on VerificationException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = verificationFailureMessage(
          AppLocalizations.of(context),
          error,
        );
      });
    } catch (error, stack) {
      debugPrint('Signup voucher verification failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.settingsIdentityLinkFailed;
      });
    }
  }

  Future<void> _openSupport(Uri uri) async {
    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _showSupportError();
    } catch (error, stack) {
      debugPrint('Could not open signup support contact: $error\n$stack');
      if (mounted) _showSupportError();
    }
  }

  void _showSupportError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).supportContactOpenFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Uri? supportUri = SupportContact.whatsappUri(
      message: l10n.signupPaywallSupportMessage,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.actionBack,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(l10n.signupPaywallTitle),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.all(spacing.xl),
              children: <Widget>[
                const SimplePosMark(size: 48),
                SizedBox(height: spacing.lg),
                Text(
                  l10n.signupPaywallHeadline,
                  style: type.headlineSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: spacing.sm),
                Text(
                  l10n.signupPaywallBody,
                  style: type.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: spacing.lg),
                Container(
                  padding: EdgeInsets.all(spacing.md),
                  decoration: BoxDecoration(
                    color: colors.accentContainer,
                    borderRadius: shapes.cardRadius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.lock_open_outlined, color: colors.accent),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: Text(
                          l10n.signupPaywallIncludedMonth,
                          style: type.bodyMedium?.copyWith(
                            color: colors.onAccentContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.xl),
                TextField(
                  controller: _voucher,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.characters,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  onSubmitted: (_) => _redeem(),
                  decoration: InputDecoration(
                    labelText: l10n.signupPaywallVoucherLabel,
                    hintText: l10n.signupPaywallVoucherHint,
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  SizedBox(height: spacing.md),
                  PersistentBanner(
                    message: _error!,
                    icon: Icons.error_outline,
                    tone: StatusTone.danger,
                  ),
                ],
                SizedBox(height: spacing.lg),
                FilledButton.icon(
                  onPressed: _submitting ? null : _redeem,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.redeem_outlined),
                  label: Text(
                    _submitting
                        ? l10n.signupPaywallActivating
                        : l10n.signupPaywallRedeem,
                  ),
                ),
                SizedBox(height: spacing.md),
                if (supportUri != null)
                  OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _openSupport(supportUri),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(l10n.signupPaywallWhatsApp),
                  ),
                SizedBox(height: spacing.md),
                Text(
                  l10n.signupPaywallVoucherNote,
                  textAlign: TextAlign.center,
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
