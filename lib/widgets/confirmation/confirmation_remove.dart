import 'package:flutter/material.dart';
import '../../../widgets/button/button.dart';

class ConfirmationDialog extends StatefulWidget {
  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;
  final Color confirmColor;
  final Future<void> Function() onConfirm;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.description,
    required this.onConfirm,
    this.confirmLabel = "Confirm",
    this.cancelLabel = "Cancel",
    this.confirmColor = Colors.red,
  });

  @override
  State<ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<ConfirmationDialog> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              widget.description,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  Button(
                    width: isDesktop ? 120 : double.infinity,
                    label: widget.cancelLabel,
                    variant: ButtonVariant.outline,
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                  Button(
                    width: isDesktop ? 120 : double.infinity,
                    label: widget.confirmLabel,
                    color: widget.confirmColor,
                    isLoading: _isLoading,
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await widget.onConfirm();
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}