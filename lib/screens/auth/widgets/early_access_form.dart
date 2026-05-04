import 'package:flutter/material.dart';
import 'emerald_textfield.dart';

class EarlyAccessForm extends StatefulWidget {
  const EarlyAccessForm({super.key});

  @override
  State<EarlyAccessForm> createState() => _EarlyAccessFormState();
}

class _EarlyAccessFormState extends State<EarlyAccessForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSubmitted = false;

  // Hardcoded colors matching your theme
  static const Color emerald = Color(0xFF00AB55);
  static const Color inactiveText = Color(0xFF919EAB);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestAccess() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      // TODO: Replace with your actual API call to save the email
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmitted = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show success state if the form has been submitted
    if (_isSubmitted) {
      return _buildSuccessState();
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Request Early Access",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Enter your email address to join the waitlist and get notified when we launch.",
            textAlign: TextAlign.center,
            style: TextStyle(color: inactiveText, fontSize: 14, height: 1.5),
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

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _handleRequestAccess, 
              child: _isLoading 
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
                        "Joining...", 
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ) 
                : const Text("Join Waitlist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // A visually pleasing success state to show after submission
  Widget _buildSuccessState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: emerald.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            color: emerald,
            size: 64,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "You're on the list!",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Thank you for your interest. We've added ${_emailController.text} to our waitlist and will be in touch soon.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: inactiveText, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}