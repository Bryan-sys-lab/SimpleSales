import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'services/app_state.dart';
import 'services/app_stage.dart';
import 'app_brand.dart';
import 'services/auto_sync_service.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_chooser_screen.dart';
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

  // The browser has no native sqflite plugin, so the default factory throws on
  // the first database access. Point it at the IndexedDB-backed wasm build;
  // native platforms keep their own factory.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (sentryDsn.isNotEmpty) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (sentryDsn.isNotEmpty && _sentryReady) {
      Sentry.captureException(error, stackTrace: stack);
      return true;
    }
    // Without a working crash reporter, returning true would mark the error as
    // handled and discard it silently. Log it so it is visible either way.
    debugPrint('Unhandled error: $error\n$stack');
    return false;
  };

  // Initialize Sentry for crash reporting (if DSN provided). A malformed DSN
  // must never prevent the app from starting, so init is guarded and the app
  // always runs.
  if (sentryDsn.isNotEmpty) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = sentryDsn;
          options.tracesSampleRate = kReleaseMode ? 0.1 : 0.0;
          options.environment = kReleaseMode ? 'production' : 'development';
        },
        appRunner: () => runApp(const DukaPosApp()),
      );
      _sentryReady = true;
      return;
    } catch (error) {
      debugPrint('Crash reporting disabled (invalid SENTRY_DSN): $error');
    }
  }
  runApp(const DukaPosApp());
}

bool _sentryReady = false;

class DukaPosApp extends StatelessWidget {
  const DukaPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: SimplePosBrand.appName,
        debugShowCheckedModeBanner: false,
        theme: buildDukaTheme(),
        home: const RootRouter(),
      ),
    );
  }
}

/// Decides which top-level screen to show.
///
/// The order is deliberate and is expressed by [resolveAppStage] rather than
/// inline: a shop with no signed-in user always reaches the PIN pad, and the
/// first-run walkthrough only ever appears for the admin after a successful
/// sign-in. The walkthrough used to be checked first, which trapped every user
/// — cashiers included — on the welcome screens of any till that had not
/// dismissed it.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});
  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _loading = true;
  bool _dbFailed = false;
  bool _onboardingComplete = false;

  /// Which door the chooser offered. Held here because the router, not the
  /// chooser, decides what comes next, and keeping it here is what lets
  /// [resolveAppStage] stay a pure function that a test can drive with no
  /// widget tree at all.
  AppChooserIntent _intent = AppChooserIntent.signIn;

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
    final state = context.watch<AppState>();
    final shopName = state.owner?.shopName ?? '';
    final stage = resolveAppStage(
      isLoading: _loading,
      hasDatabaseFailure: _dbFailed,
      hasShop: state.owner != null,
      isSignedIn: state.isSignedIn,
      isAdmin: state.isAdmin,
      onboardingComplete: _onboardingComplete,
      chooserIntent: _intent,
    );

    return switch (stage) {
      AppStage.loading => const SplashScreen(),
      AppStage.databaseFailed => const _DatabaseErrorScreen(),
      AppStage.chooser => WelcomeChooserScreen(
          shopName: shopName,
          hasShop: state.owner != null,
          intent: _intent,
        ),
      AppStage.signingIn => const LoginScreen(),
      AppStage.settingUp => OwnerSetupScreen(
          isAdditionalShop: _intent == AppChooserIntent.addShop,
          carryOverFrom: _intent == AppChooserIntent.addShop ? state.owner : null,
          onCancel: _intent == AppChooserIntent.addShop
              ? () => setState(() => _intent = AppChooserIntent.signIn)
              : null,
        ),
      AppStage.onboarding => OnboardingScreen(
          onComplete: () => setState(() => _onboardingComplete = true)),
      AppStage.ready => const HomeShell(),
    };
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
