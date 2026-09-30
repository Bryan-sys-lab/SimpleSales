import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'services/app_state.dart';
import 'services/auto_sync_service.dart';
import 'screens/owner_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

/// Sentry DSN for crash reporting - get from https://sentry.io
const sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '', // Empty = crash reporting disabled
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (sentryDsn.isNotEmpty) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (sentryDsn.isNotEmpty) Sentry.captureException(error, stackTrace: stack);
    return true;
  };

  // Initialize Sentry for crash reporting (if DSN provided)
  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = kReleaseMode ? 0.1 : 0.0;
        options.environment = kReleaseMode ? 'production' : 'development';
      },
      appRunner: () => runApp(const DukaPosApp()),
    );
  } else {
    // No Sentry DSN - run without crash reporting
    runApp(const DukaPosApp());
  }
}

class DukaPosApp extends StatelessWidget {
  const DukaPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Duka POS',
        debugShowCheckedModeBanner: false,
        theme: buildDukaTheme(),
        home: const RootRouter(),
      ),
    );
  }
}

/// Decides which of the three top-level screens to show:
/// no owner yet -> setup; owner exists but nobody signed in -> lock screen;
/// signed in -> the app itself.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});
  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _loading = true;
  bool _dbFailed = false;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final state = context.read<AppState>();
      await state.loadOwner();
      final prefs = await SharedPreferences.getInstance();
      _onboardingComplete =
          prefs.getBool('onboarding_completed_${state.workspaceKey}') ?? false;
      await AutoSyncService.start();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      // Report to Sentry if available; do not expose database contents in the UI.
      if (sentryDsn.isNotEmpty) {
        Sentry.captureException(e, stackTrace: StackTrace.current);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _dbFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_dbFailed) return const _DatabaseErrorScreen();
    final state = context.watch<AppState>();
    if (state.owner == null) return const OwnerSetupScreen();
    if (!_onboardingComplete) {
      return OnboardingScreen(
          onComplete: () => setState(() => _onboardingComplete = true));
    }
    if (!state.isSignedIn) return const LoginScreen();
    return const HomeShell();
  }
}

/// Shown if the local database can't be opened at all.
class _DatabaseErrorScreen extends StatelessWidget {
  const _DatabaseErrorScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: DukaColors.danger),
              SizedBox(height: 16),
              Text('This app could not open its data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                "This can happen after a crash or a low-storage event. Nothing has been changed or deleted — "
                "but the app can't read your inventory or sales right now.\n\n"
                "If you have a recent backup file (.xlsx or .json), reinstalling the app and restoring that "
                "backup from Settings is the safest way forward. If this keeps happening, contact support.",
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
