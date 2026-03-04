import 'package:flutter/material.dart';
import 'emerald_textfield.dart';
import 'reset_pasword.dart';
import '../controllers/auth_controller.dart';
import '../../../utils/app_responsive.dart';
import '../../../core/api_service.dart';

class SignupForm extends StatefulWidget {
  final VoidCallback onSwitch;
  const SignupForm({super.key, required this.onSwitch});

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  final _formKey = GlobalKey<FormState>();
  final ApiService apiService = ApiService();
  
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  
  bool _agreedToDataProcessing = false;

  static const Color emerald = Color(0xFF00AB55);
  static const Color inactiveText = Color(0xFF919EAB);
  static const Color errorRed = Color(0xFFFF4842);

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showPasswordReset(BuildContext context, String email) {
  final bool isDesktop = AppResponsive.isDesktopScreen(context);

  if (isDesktop) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 400,
          child: ResetPasswordSheet(email: email),
        ),
      ),
    );
  } else {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ResetPasswordSheet(email: email),
      ),
    );
  }
}

  void _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      final success = await AuthController.instance.signup(
      email: _emailController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      );

      if (success && mounted) {
        _showPasswordReset(context, _emailController.text.trim());
    }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      // 'onUserInteraction' makes validation trigger as soon as the user starts typing
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              "Create Account",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          const SizedBox(height: 40),
          
          EmeraldTextField(
            controller: _firstNameController,
            hintText: "First Name",
            prefixIcon: Icons.person_outline,
            validator: (val) {
              if (val == null || val.isEmpty) return 'First name is required';
              if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(val)) return 'Letters only';
              return null;
            },
          ),
          const SizedBox(height: 16),

          EmeraldTextField(
            controller: _lastNameController,
            hintText: "Last Name",
            prefixIcon: Icons.person_outline,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Last name is required';
              if (!RegExp(r'^[a-zA-Z ]+$').hasMatch(val)) return 'Only characters allowed';
              return null;
            },
          ),
          const SizedBox(height: 16),

          EmeraldTextField(
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
          const SizedBox(height: 20),

          // CHECKBOX
          FormField<bool>(
            initialValue: _agreedToDataProcessing,
            validator: (value) => _agreedToDataProcessing ? null : 'Required',
            builder: (state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _agreedToDataProcessing,
                        activeColor: emerald,
                        checkColor: Colors.white,
                        side: BorderSide(color: state.hasError ? errorRed : inactiveText),
                        onChanged: (val) {
                          setState(() => _agreedToDataProcessing = val ?? false);
                          state.didChange(val);
                        },
                      ),
                      const Expanded(
                        child: Text(
                          "I agree to the processing of personal data",
                          style: TextStyle(color: inactiveText, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(state.errorText!, style: const TextStyle(color: errorRed, fontSize: 12)),
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // BUTTON
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
                    disabledBackgroundColor: emerald.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isLoading ? null : _handleSignup,
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
                            "Signing up...", 
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ) 
                    : const Text("Sign Up", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
          
          const SizedBox(height: 10),

          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
            ],
          ),
          
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Already have an account? ",
                style: TextStyle(fontSize: 13, color: inactiveText),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onSwitch,
                  child: const Text(
                    "Sign in",
                    style: TextStyle(
                      color: emerald,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            ],
          ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}