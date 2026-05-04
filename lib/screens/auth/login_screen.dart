import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'widgets/login_form.dart';
import 'widgets/signup_form.dart';
import 'widgets/early_access_form.dart';
import 'widgets/branding_panel.dart';
import '../../utils/app_responsive.dart';

class LoginScreen extends StatefulWidget {
  final bool showBetaLogin;
  final bool isLoginMode; 

  const LoginScreen({
    super.key, 
    this.showBetaLogin = false,
    this.isLoginMode = true, 
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
  
class _LoginScreenState extends State<LoginScreen> {
  late bool _showLoginForm; 

  @override
  void initState() {
    super.initState();
    _showLoginForm = widget.isLoginMode; 
  }

  @override
  void didUpdateWidget(LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoginMode != widget.isLoginMode) {
      setState(() {
        _showLoginForm = widget.isLoginMode;
      });
    }
  }

  void _toggleFormMode() {
    final currentUri = GoRouterState.of(context).uri;
    final queryParams = Map<String, String>.from(currentUri.queryParameters);

    final targetPath = _showLoginForm ? '/signup' : '/login';

    final newUri = Uri(
      path: targetPath, 
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    
    context.go(newUri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppResponsive.isDesktopScreen(context);

    const Color obsidianBg = Color(0xFF151A21);
    const Color emeraldAccent = Color(0xFF00AB55);
    const Color slateSurface = Color(0xFF1C252E);

    // 🚀 2. Safely check if this is a Native Android or iOS app
    final bool isNativeMobileApp = !kIsWeb && 
        (defaultTargetPlatform == TargetPlatform.android || 
         defaultTargetPlatform == TargetPlatform.iOS);

    // 🚀 3. Determine if we should show the standard login flow
    // It shows if the URL has ?beta=true OR if it's a compiled mobile app
    final bool bypassEarlyAccess = widget.showBetaLogin || isNativeMobileApp;

    Widget activeForm;
    if (!bypassEarlyAccess) {
      activeForm = const EarlyAccessForm(key: ValueKey('early_access'));
    } else {
      activeForm = _showLoginForm 
          ? LoginForm(key: const ValueKey('login'), onSwitch: _toggleFormMode) 
          : SignupForm(key: const ValueKey('signup'), onSwitch: _toggleFormMode);
    }

    return Scaffold(
      backgroundColor: obsidianBg,
      body: Row(
        children: [
          if (isDesktop)
            const Expanded(
              flex: 3,
              child: BrandingPanel(),
            ),

          Expanded(
            flex: isDesktop ? 2 : 5,
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
                                    const Icon(
                                      Icons.analytics_rounded, 
                                      size: 64, 
                                      color: emeraldAccent,
                                    ),
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
                                    const SizedBox(height: 40),
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
                                    onPressed: () {}, 
                                    child: const Text("Privacy Notice", 
                                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                  const Text("|", style: TextStyle(color: Colors.white10)),
                                  TextButton(
                                    onPressed: () {}, 
                                    child: const Text("Terms Of Use", 
                                      style: TextStyle(color: Colors.grey, fontSize: 12)),
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
        ],
      ),
    );
  }
}