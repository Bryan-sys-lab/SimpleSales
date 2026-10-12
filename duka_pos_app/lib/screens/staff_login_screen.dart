import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/staff_credential_cache.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';

/// The username + password entry point for staff.
///
/// A staff member who knows their backend credentials can sign in here even
/// when the till is brand-new and has no local roster yet. On success the
/// account is cached locally so the same staff member can sign in again
/// offline.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final AppState appState = context.read<AppState>();
    if (appState.rememberedStaffUsername != null) {
      _usernameController.text = appState.rememberedStaffUsername!;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String username = _usernameController.text.trim();
      final String password = _passwordController.text;

      // Throttle BEFORE any sign-in attempt. The online backend has its own
      // rate limiting, but the local fallback below verifies a 4-digit PIN
      // against a local hash — a keyspace an attacker with physical access
      // walks in minutes if it is not throttled.
      final String userKey = username;
      if (await AuthService.isTillLockedOut()) {
        final Duration? remaining = await AuthService.tillLockoutRemaining();
        if (!mounted) return;
        setState(
            () => _error = 'Too many wrong PINs on this till. Try again in '
                '${remaining?.inSeconds ?? 0}s.');
        return;
      }
      if (await AuthService.isLockedOut(userKey)) {
        final Duration? remaining = await AuthService.lockoutRemaining(userKey);
        if (!mounted) return;
        setState(() => _error =
            'Too many wrong PINs. Try again in ${remaining?.inSeconds ?? 0}s.');
        return;
      }

      final Map<String, dynamic>? backendResponse =
          await BackendService.authenticateStaff(
        username: username,
        pin: password,
      );

      Staff? staff;
      if (backendResponse != null &&
          backendResponse['staff'] is Map<String, dynamic>) {
        final Map<String, dynamic> staffMap =
            backendResponse['staff'] as Map<String, dynamic>;
        staff = Staff(
          id: staffMap['id'] as int? ?? staffMap['localId'] as int?,
          name: staffMap['name'] as String? ?? username,
          username: username,
          pinHash: staffMap['pinHash'] as String? ?? '',
          role: staffMap['role'] as String? ?? 'cashier',
          remoteId: staffMap['remoteId'] as String?,
          active: staffMap['active'] as bool? ?? true,
        );
        if (staff.id != null) {
          await DatabaseHelper.instance.updateStaffPin(
            staff.id!,
            await AuthService.hashPin(password),
          );
        }
      } else {
        final List<Staff> localStaff =
            await DatabaseHelper.instance.getStaff(activeOnly: false);
        staff = localStaff.cast<Staff?>().firstWhere(
              (Staff? s) =>
                  s?.username?.toLowerCase() == username.toLowerCase(),
              orElse: () => null,
            );
        if (staff != null) {
          final bool ok = await AuthService.verifyPin(password, staff.pinHash);
          if (ok) {
            await AuthService.recordSuccess(userKey);
          } else {
            staff = null;
            await AuthService.recordFailure(userKey);
          }
        }
      }

      if (staff == null) {
        if (!mounted) return;
        setState(() {
          _error = AppLocalizations.of(context).loginWrongCredentials;
        });
        return;
      }

      if (!mounted) return;
      final int staffId =
          staff.id ?? context.read<AppState>().rememberedStaffId ?? 0;
      await StaffCredentialCache.cacheStaffCredentials(
        staffId,
        username,
        password,
      );
      if (!mounted) return;
      await context.read<AppState>().rememberStaff(staff);
      if (!mounted) return;
      context.read<AppState>().signInAsStaff(staff);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).loginNetworkError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(spacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n.staffLoginTitle,
                      textAlign: TextAlign.center,
                      style: type.headlineSmall,
                    ),
                    SizedBox(height: spacing.lg),
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        labelText: l10n.staffUsernameLabel,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (String? value) =>
                          (value == null || value.trim().isEmpty)
                              ? l10n.fieldRequired('') as String?
                              : null,
                    ),
                    SizedBox(height: spacing.md),
                    TextFormField(
                      controller: _passwordController,
                      textInputAction: TextInputAction.done,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: l10n.staffPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (String? value) =>
                          (value == null || value.isEmpty)
                              ? l10n.fieldRequired('') as String?
                              : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    SizedBox(height: spacing.md),
                    if (_error != null)
                      PersistentBanner(
                        message: _error!,
                        icon: Icons.error_outline,
                        tone: StatusTone.danger,
                      ),
                    SizedBox(height: spacing.md),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? SizedBox(
                              height: spacing.minTapTarget,
                              width: spacing.minTapTarget,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(l10n.loginSignInAction),
                    ),
                    SizedBox(height: spacing.md),
                    TextButton.icon(
                      onPressed:
                          _loading ? null : () => context.go(Routes.login),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      label: Text(l10n.backToPinPadAction),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
