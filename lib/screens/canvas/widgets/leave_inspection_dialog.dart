import 'package:flutter/material.dart';
import '../../../widgets/button/button.dart';

/// Asks the user to confirm leaving the inspection to create a Tag Group / Tool Set.
/// [onConfirm] runs before closing (e.g. saving the inspection) and returns false to
/// keep the user on the inspection. Resolves to true when the user should navigate.
class LeaveInspectionDialog extends StatefulWidget {
  final String noun;
  final Future<bool> Function() onConfirm;

  const LeaveInspectionDialog({
    super.key,
    required this.noun,
    required this.onConfirm,
  });

  static Future<bool> show(
    BuildContext context, {
    required String noun,
    required Future<bool> Function() onConfirm,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => LeaveInspectionDialog(noun: noun, onConfirm: onConfirm),
    );
    return result ?? false;
  }

  @override
  State<LeaveInspectionDialog> createState() => _LeaveInspectionDialogState();
}

class _LeaveInspectionDialogState extends State<LeaveInspectionDialog> {
  bool _isLeaving = false;

  Future<void> _handleConfirm() async {
    setState(() => _isLeaving = true);
    final canLeave = await widget.onConfirm();
    if (!mounted) return;
    if (canLeave) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Leave the inspection to create a ${widget.noun}?",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Your inspection is saved. You'll go to the ${widget.noun}s page. "
                "When you're done, open this inspection again and add the new "
                "${widget.noun == 'Tag Group' ? 'group' : 'set'} with +.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Button(
                      label: "Stay here",
                      variant: ButtonVariant.outline,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      onPressed: _isLeaving
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                    Button(
                      label: "Go to ${widget.noun}s",
                      trailingIcon: Icons.arrow_forward,
                      isLoading: _isLeaving,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      onPressed: _handleConfirm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
