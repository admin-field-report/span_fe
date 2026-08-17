import 'package:flutter/material.dart';
import 'emerald_textfield.dart';
import '../controllers/auth_controller.dart';

class ResetPasswordSheet extends StatefulWidget {
  final String email;
  const ResetPasswordSheet({super.key, required this.email});

  @override
  State<ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<ResetPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _tempPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  static const Color emerald = Color(0xFF1C58F6);

  // Strong Password Validator Logic
  String? _validateStrongPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Minimum 8 characters';
    
    // Check for Uppercase, Lowercase, Number, and Special Char
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$')
        .hasMatch(value)) {
      return 'Must include A-z, 0-9, and @\$!%*?&';
    }
    return null;
  }

  void _updatePassword() {
    if (_formKey.currentState!.validate()) {
      authController.resetPassword(
        widget.email,
       _newPasswordController.text,
       _tempPasswordController.text
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0E131E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Reset Your Password",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "A temporary password was sent to ${widget.email}",
              style: const TextStyle(color: Color(0xFF919EAB), fontSize: 13),
            ),
            const SizedBox(height: 24),

            // TEMPORARY PASSWORD
            EmeraldTextField(
              controller: _tempPasswordController,
              hintText: "Temporary Password",
              prefixIcon: Icons.vpn_key_outlined,
              isPassword: true,
              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // NEW PASSWORD
            EmeraldTextField(
              controller: _newPasswordController,
              hintText: "New Password",
              prefixIcon: Icons.lock_outline,
              isPassword: true,
              validator: _validateStrongPassword,
            ),
            const SizedBox(height: 16),

            // CONFIRM PASSWORD
            EmeraldTextField(
              controller: _confirmPasswordController,
              hintText: "Confirm New Password",
              prefixIcon: Icons.lock_reset_outlined,
              isPassword: true,
              validator: (val) => val != _newPasswordController.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 24),
            ListenableBuilder(
              listenable: authController,
              builder: (context, _) {
                final isLoading = authController.resetingPassword;
                return SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald,
                      disabledBackgroundColor: emerald.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isLoading ? null : _updatePassword,
                    child: isLoading 
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 20, 
                              width: 20, 
                              child: CircularProgressIndicator(
                                color: Color(0xFF0A1224), 
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Updating password...", 
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ) 
                      : const Text("Update Password", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ListenableBuilder(
                  listenable: authController,
                  builder: (context, child) {
                    if (authController.errorMessageResetingPassword == null) return const SizedBox.shrink();
                    return Text(
                      authController.errorMessageResetingPassword!,
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500, fontSize: 13),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ],
            ),
          const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}