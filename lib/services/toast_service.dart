import 'dart:async';

import 'package:flutter/material.dart';

enum ToastType { success, error, warning, info }

// Toasts render in the app's root [Overlay] rather than as floating
// SnackBars: a SnackBar pinned to the top-right via a huge bottom margin
// trips Flutter's "Floating SnackBar presented off screen" assertion as soon
// as the remaining space can't fit it (e.g. tablet with the keyboard open).
// An overlay entry has no such geometry constraint and needs no Scaffold.
class ToastService {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context, {
    required String message,
    required ToastType type,
    String? title,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    final Color bgColor;
    final IconData icon;
    final Color accentColor;

    switch (type) {
      case ToastType.success:
        bgColor = const Color(0xFFE8F5E9);
        accentColor = const Color(0xFF2E7D32);
        icon = Icons.check_circle_rounded;
        break;
      case ToastType.error:
        bgColor = const Color(0xFFFFEBEE);
        accentColor = const Color(0xFFD32F2F);
        icon = Icons.error_rounded;
        break;
      case ToastType.warning:
        bgColor = const Color(0xFFFFF3E0);
        accentColor = const Color(0xFFEF6C00);
        icon = Icons.warning_rounded;
        break;
      case ToastType.info:
        bgColor = const Color(0xFFE3F2FD);
        accentColor = const Color(0xFF1565C0);
        icon = Icons.info_rounded;
        break;
    }

    hide();

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final bool isWide = media.size.width > 600;

        final toast = Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isWide ? 380 : media.size.width - 40,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accentColor, size: 28),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accentColor.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: hide,
                  icon: Icon(Icons.close_rounded, color: accentColor, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        );

        // Wide screens: pinned top-right. Phones: bottom-centered, lifted
        // above the keyboard when it's open.
        return Positioned(
          top: isWide ? media.padding.top + 20 : null,
          right: isWide ? 20 : 20,
          left: isWide ? null : 20,
          bottom: isWide ? null : media.viewInsets.bottom + media.padding.bottom + 20,
          child: toast,
        );
      },
    );

    overlay.insert(_entry!);
    _timer = Timer(const Duration(seconds: 4), hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
