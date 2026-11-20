import 'package:flutter/material.dart';

import '../ui/brand/simple_pos_mark.dart';

/// Startup status only. The app stage controller owns restoration and routing;
/// this screen never delays startup or invents a second navigation state.
class SplashScreen extends StatelessWidget {
  const SplashScreen(
      {super.key, this.onAnimationComplete, this.playOnce = true});

  final VoidCallback? onAnimationComplete;
  final bool playOnce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: 'SimpleSales. Opening your shop.',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SimplePosMark(size: 72),
                const SizedBox(height: 20),
                Text('SimpleSales',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(height: 12),
                Text('Opening your shop…', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
