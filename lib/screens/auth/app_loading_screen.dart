import 'package:flutter/material.dart';
import '../../widgets/app_logo/app_logo.dart';

class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                // color: colorScheme.primary.withOpacity(1),
                shape: BoxShape.circle,
              ),
              // child: Icon(
              //   Icons.analytics_rounded,
              //   size: 60,
              //   color: colorScheme.primary,
              // ),
              child: AppLogo(size: 60, padding: 10),
            ),
            const SizedBox(height: 32),
            Text(
              "SPAN INSPECT",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Secure Enterprise Portal",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 64),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              "Loading...",
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}