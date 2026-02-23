import 'package:flutter/material.dart';
import '../../../core/widgets/form_components/text_field.dart';
import '../controllers/auth_controller.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  

  // Hardcoded Emerald and UI colors
  static const Color emerald = Color(0xFF00AB55);
  static const Color inactiveText = Color(0xFF919EAB);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      AuthController.instance.login(
        _emailController.text, 
        _passwordController.text
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Welcome back",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Enter details to Sign in to your account",
            textAlign: TextAlign.center,
            style: TextStyle(color: inactiveText, fontSize: 14),
          ),
          const SizedBox(height: 40),
          
          FormControlTextField(
            controller: _emailController,
            hintText: "Email Address",
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w\+\-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          FormControlTextField(
            controller: _passwordController,
            hintText: "Password",
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            textInputAction: TextInputAction.done,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Password is required';
              if (val.length < 8) return 'Minimum 8 characters';
              return null;
            },
          ),
          
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                "Forgot password?",
                style: TextStyle(
                  color: emerald,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sign In Button
          ListenableBuilder(
            listenable: AuthController.instance,
            builder: (context, _) {
              final isLoading = AuthController.instance.isLoading;

              return SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: isLoading ? null : _handleLogin, 
                  child: isLoading 
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 20, 
                            width: 20, 
                            child: CircularProgressIndicator(
                              color: Colors.white, 
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Signing in...", 
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ) 
                    : const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          ListenableBuilder(
            listenable: AuthController.instance,
            builder: (context, child) {
              if (AuthController.instance.errorMessage == null) return const SizedBox.shrink();
              return Text(
                AuthController.instance.errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500, fontSize: 13),
                textAlign: TextAlign.center,
              );
            },
          ),
          
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Don't have an account? ", style: TextStyle(fontSize: 12, color: inactiveText)),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  "Sign up",
                  style: TextStyle(color: emerald, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}