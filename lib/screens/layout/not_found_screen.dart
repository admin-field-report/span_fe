import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/app_responsive.dart';

class NotFoundScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onHomePressed;

  const NotFoundScreen({
    super.key,
    this.title = "404 - Page Not Found",
    this.message = "The page you are looking for might have been removed or is temporarily unavailable.",
    this.onHomePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final bool isDesktop = AppResponsive.isDesktopScreen(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "404",
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: isDesktop ? 160 : 100,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface.withOpacity(0.05),
                  letterSpacing: -5,
                ),
              ),
              
              Icon(
                Icons.miscellaneous_services_outlined,
                size: 80,
              ),
              
              const SizedBox(height: 40),
              
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 16),
              
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              SizedBox(
                width: isDesktop ? 200 : double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onHomePressed ?? () => context.go('/'),
                  child: const Text("Go to Home", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}