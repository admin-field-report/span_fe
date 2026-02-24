import 'package:flutter/material.dart';

enum ToastType { success, error, warning, info }

class ToastService {
  static void show(
    BuildContext context, {
    required String message,
    required ToastType type,
    String? title,
  }) {
    
    final Size screenSize = MediaQuery.of(context).size;
    final bool isDesktop = screenSize.width > 600;

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        duration: const Duration(seconds: 4),
        margin: isDesktop
            ? EdgeInsets.only(
                bottom: screenSize.height - 120,
                left: screenSize.width - 400,
                right: 20,
              )
            : const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        content: Container(
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
              Expanded(
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
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                icon: Icon(Icons.close_rounded, color: accentColor, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}