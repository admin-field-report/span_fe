import 'package:flutter/material.dart';
import './controllers/auth_controller.dart';

class AppLoadingScreen extends StatefulWidget {
  const AppLoadingScreen({super.key});

  @override
  State<AppLoadingScreen> createState() => _AppLoadingScreenState();
}

class _AppLoadingScreenState extends State<AppLoadingScreen> {
  @override
  void initState() {
    super.initState();
    authController.fetchUserDetails();
  }

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
            // 1. LOGO CONTAINER
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.analytics_rounded,
                size: 60,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            
            // 2. COMPANY NAME (Using Theme TextStyles)
            Text(
              "FIELD REPORT",
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
            
            // 3. THEMED LOADER
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            
            // 4. STATUS TEXT
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