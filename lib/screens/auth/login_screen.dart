import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/login_form.dart';
import 'widgets/signup_form.dart';
import 'widgets/early_access_form.dart';
import 'widgets/forgot_password_form.dart';
import 'widgets/auth_background.dart';
import '../../widgets/app_logo/app_logo.dart';
import '../../utils/app_responsive.dart';

enum AuthMode { login, signup, forgotPassword }

class LoginScreen extends StatefulWidget {
  final bool showBetaLogin;
  final AuthMode authMode;

  const LoginScreen({
    super.key, 
    this.showBetaLogin = false,
    this.authMode = AuthMode.login, 
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
  
class _LoginScreenState extends State<LoginScreen> {
  late AuthMode _currentMode; 

  @override
  void initState() {
    super.initState();
    _currentMode = widget.authMode; 
  }

  @override
  void didUpdateWidget(LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authMode != widget.authMode) {
      setState(() {
        _currentMode = widget.authMode;
      });
    }
  }

  // 🚀 Universal navigation method that preserves query parameters
  void _navigateTo(String targetPath) {
    final currentUri = GoRouterState.of(context).uri;
    final queryParams = Map<String, String>.from(currentUri.queryParameters);

    final newUri = Uri(
      path: targetPath, 
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    
    context.go(newUri.toString());
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppResponsive.isDesktopScreen(context);

    const Color obsidianBg = Color(0xFF050A15);
    const Color emeraldAccent = Color(0xFF1C58F6);
    const Color slateSurface = Color(0xFF0A1224);

    final bool isNativeMobileApp = !kIsWeb && 
        (defaultTargetPlatform == TargetPlatform.android || 
         defaultTargetPlatform == TargetPlatform.iOS);

    final bool bypassEarlyAccess = widget.showBetaLogin || isNativeMobileApp;

    // 🚀 Clean switch statement to determine the active form
    Widget activeForm;
    if (!bypassEarlyAccess) {
      activeForm = const EarlyAccessForm(key: ValueKey('early_access'));
    } else {
      switch (_currentMode) {
        case AuthMode.login:
          activeForm = LoginForm(
            key: const ValueKey('login'), 
            onSwitchToSignup: () => _navigateTo('/signup'),
            onForgotPassword: () => _navigateTo('/forgot-password'),
          );
          break;
        case AuthMode.signup:
          activeForm = SignupForm(
            // NOTE: Ensure your SignupForm also accepts an onSwitchToLogin callback now
            key: const ValueKey('signup'), 
            onSwitch: () => _navigateTo('/login'),
          );
          break;
        case AuthMode.forgotPassword:
          activeForm = ForgotPasswordForm(
            key: const ValueKey('forgot_password'),
            onBackToLogin: () => _navigateTo('/login'),
          );
          break;
      }
    }

    return Scaffold(
      backgroundColor: obsidianBg,
      body: AuthBackground(
        child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          child: Column(
                            children: [
                              const Spacer(),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 450),
                                child: Column(
                                  children: [
                                    AppLogo(size: 70, padding: 6, color: emeraldAccent),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Span Inspect",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                        fontSize: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 25),
                                    Container(
                                      padding: const EdgeInsets.all(32),
                                      decoration: BoxDecoration(
                                        color: slateSurface,
                                        borderRadius: BorderRadius.circular(28),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.05),
                                        ),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        transitionBuilder: (Widget child, Animation<double> animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          );
                                        },
                                        child: activeForm,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () => _launchUrl('https://spaninspect.com/privacy-policy'),
                                    child: const Text("Privacy Notice", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                  const Text("|", style: TextStyle(color: Colors.white10)),
                                  TextButton(
                                    onPressed: () => _launchUrl('https://spaninspect.com/terms-of-service'),
                                    child: const Text("Terms Of Service", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ),
    );
  }
}