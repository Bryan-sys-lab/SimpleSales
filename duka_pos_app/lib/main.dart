import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app_brand.dart';
import 'l10n/generated/app_localizations.dart';
import 'routing/app_router.dart';
import 'routing/app_stage_controller.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';

/// Sentry DSN for crash reporting - get from https://sentry.io
const String sentryDsn = String.fromEnvironment(
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

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (sentryDsn.isNotEmpty) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
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
        (SentryFlutterOptions options) {
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

/// The composition root.
///
/// Everything the app needs is provided HERE and nowhere else: the session, the
/// boot gate, the router. A screen reaches downward for its dependencies and
/// never sideways for someone else's.
class DukaPosApp extends StatelessWidget {
  const DukaPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        // The boot gate reads the session, so it is created after it — and both
        // live ABOVE `MaterialApp.router`, because the router's `redirect` reads
        // the gate and a provider below the router could not be seen by the
        // guard.
        ChangeNotifierProvider<AppStageController>(
          create: (BuildContext context) =>
              AppStageController(context.read<AppState>())..boot(),
        ),
        // Last: the router needs the two above. It is never rebuilt afterwards —
        // `refreshListenable` re-runs the guard on its own, and rebuilding a
        // `GoRouter` throws away every branch's navigation stack.
        Provider<GoRouter>(
            create: (BuildContext context) => appRouter(context)),
      ],
      child: const _ThemedApp(),
    );
  }
}

/// Reads the two providers the router is built from.
///
/// Named so the dependency arrow is stated once: `lib/routing` depends on the
/// session and the boot gate, and on nothing above them.
GoRouter appRouter(BuildContext context) => buildAppRouter(
      stage: context.read<AppStageController>(),
      appState: context.read<AppState>(),
    );

/// The app widget: theme, locale and the router, injected exactly once.
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  static bool _exitRequested = false;
  static Timer? _exitTimer;

  void _onPopInvoked(BuildContext context, bool didPop, Object? result) {
    if (didPop) return;
    final GoRouter router = context.read<GoRouter>();
    if (router.canPop()) {
      router.pop();
      return;
    }
    if (_exitRequested) {
      _exitTimer?.cancel();
      _exitTimer = null;
      _exitRequested = false;
      SystemNavigator.pop();
      return;
    }
    _exitRequested = true;
    _exitTimer = Timer(const Duration(seconds: 2), () {
      _exitRequested = false;
    });
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext != null) {
      ScaffoldMessenger.of(navigatorContext).showSnackBar(
        const SnackBar(content: Text('Press back again to exit')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({ThemeData light, ThemeData dark}) themes = buildDukaThemes();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) =>
          _onPopInvoked(context, didPop, result),
      child: MaterialApp.router(
      title: SimplePosBrand.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: context.read<GoRouter>(),
      theme: themes.light,
      darkTheme: themes.dark,
      // Both themes are hand-authored and both pass AA independently, so the
      // system setting is honoured rather than forced. The mode is read from
      // `MediaQuery.platformBrightnessOf` inside each theme's own construction,
      // which means the OS choice is respected with no stored preference and
      // therefore no first-frame flash: there is nothing to restore late.
      themeMode: ThemeMode.system,

      // Localization. Three things have to be wired together or "English-only"
      // silently costs more than it looks:
      //
      //   * `AppLocalizations.localizationsDelegates` already contains the three
      //     `Global*` delegates, so appending them again would duplicate each one
      //     and `Localizations._loadAll` would take the first — which is the
      //     wrong one the moment anyone vendors their own.
      //   * `supportedLocales` comes from the ARB catalogue rather than a
      //     hand-written list, so a locale cannot be half-shipped: adding
      //     `app_sw.arb` is the whole of adding Swahili.
      //   * `locale` is left null so the OS decides. There is nothing to restore
      //     before the first frame because there is no stored preference, which
      //     is why there is no locale flash on boot the way a persisted choice
      //     would cause.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: null,
      // No `localeResolutionCallback`: the default resolution picks the first
      // supported locale whose language matches the device and falls back to the
      // first supported locale, so an OS set to French still gets English rather
      // than English copy inside French chrome. Adding a callback would only be
      // needed once the app has a language the OS cannot select.
      // A theme change is a sudden luminance change the user did not cause.
      // Interpolating it renders a half-styled state no screen was laid out for.
      themeAnimationStyle: AnimationStyle.noAnimation,
      ),
    );
  }
}
