import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import 'emerald_textfield.dart';

enum ResetStep { requestEmail, verifyCode, success }

class ForgotPasswordForm extends StatefulWidget {
  final VoidCallback onBackToLogin;
  
  const ForgotPasswordForm({super.key, required this.onBackToLogin});

  @override
  State<ForgotPasswordForm> createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends State<ForgotPasswordForm> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // Styling
  static const Color emerald = Color(0xFF00AB55);
  static const Color inactiveText = Color(0xFF919EAB);

  // Track the current phase of the reset process
  ResetStep _currentStep = ResetStep.requestEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // 🚀 Step 1: Request Code
  void _handleSendCode() async {
    if (_formKey.currentState!.validate()) {
      final success = await AuthController.instance.forgotPassword(
        _emailController.text.trim()
      );
      
      if (success && mounted) {
        setState(() => _currentStep = ResetStep.verifyCode);
      }
    }
  }

  // 🚀 Step 2: Reset Password
  void _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      final success = await AuthController.instance.resetForgotPassword(
        _emailController.text.trim(),
        _codeController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        setState(() => _currentStep = ResetStep.success);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildCurrentStep(context),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    switch (_currentStep) {
      case ResetStep.requestEmail:
        return _buildRequestEmailForm();
      case ResetStep.verifyCode:
        return _buildVerifyCodeForm();
      case ResetStep.success:
        return _buildSuccessScreen();
    }
  }

  // ==========================================
  // UI: STEP 1 - REQUEST EMAIL
  // ==========================================
  Widget _buildRequestEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Forgot your password?",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 8),
          const Text(
            "Please enter the email address associated with your account and we will email you a 6-digit code.",
            textAlign: TextAlign.center,
            style: TextStyle(color: inactiveText, fontSize: 14),
          ),
          const SizedBox(height: 40),
          
          EmeraldTextField(
            controller: _emailController,
            hintText: "Email Address",
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w\+\-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          _buildSubmitButton(
            label: "Send Request", 
            onPressed: _handleSendCode,
          ),
          
          _buildErrorMessage(),
          const SizedBox(height: 24),
          _buildReturnToLoginButton(),
        ],
      ),
    );
  }

  // ==========================================
  // UI: STEP 2 - VERIFY CODE & RESET
  // ==========================================
  Widget _buildVerifyCodeForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Check your email",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            "We've sent a 6-digit verification code to\n${_emailController.text}",
            textAlign: TextAlign.center,
            style: const TextStyle(color: inactiveText, fontSize: 14),
          ),
          const SizedBox(height: 32),
          
          EmeraldTextField(
            controller: _codeController,
            hintText: "Verification Code",
            prefixIcon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Code is required';
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          EmeraldTextField(
            controller: _passwordController,
            hintText: "New Password",
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Password is required';
              if (val.length < 8) return 'Minimum 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),

          EmeraldTextField(
            controller: _confirmPasswordController,
            hintText: "Confirm Password",
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            textInputAction: TextInputAction.done,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Please confirm your password';
              if (val != _passwordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 32),

          _buildSubmitButton(
            label: "Update Password", 
            onPressed: _handleResetPassword,
          ),
          
          _buildErrorMessage(),
          const SizedBox(height: 24),
          _buildReturnToLoginButton(),
        ],
      ),
    );
  }

  // ==========================================
  // UI: STEP 3 - SUCCESS
  // ==========================================
  Widget _buildSuccessScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 64, color: emerald),
        const SizedBox(height: 24),
        const Text(
          "Password Updated!",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        const SizedBox(height: 8),
        const Text(
          "Your password has been successfully reset. You can now sign in with your new password.",
          textAlign: TextAlign.center,
          style: TextStyle(color: inactiveText, fontSize: 14),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: widget.onBackToLogin, 
            child: const Text("Return to Sign In", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  // ==========================================
  // HELPER COMPONENTS
  // ==========================================
  Widget _buildSubmitButton({required String label, required VoidCallback onPressed}) {
    return ListenableBuilder(
      listenable: authController,
      builder: (context, _) {
        final isLoading = authController.forgotPasswordLoading;

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
            onPressed: isLoading ? null : onPressed, 
            child: isLoading 
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text("Processing...", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ) 
              : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildErrorMessage() {
    return ListenableBuilder(
      listenable: authController,
      builder: (context, child) {
        if (authController.forgotPasswordErrorMessage == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Text(
            authController.forgotPasswordErrorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  Widget _buildReturnToLoginButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.chevron_left_rounded, color: emerald, size: 20),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => {
              authController.resetForgotPasswordState(),
              widget.onBackToLogin(),
            },
            child: const Text(
              "Return to sign in",
              style: TextStyle(color: emerald, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        )
      ],
    );
  }
}