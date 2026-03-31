import 'dart:ui';
import 'package:flutter/material.dart';
import 'loader.dart'; 

import '../../core/router.dart'; 

class LoadingOverlay {
  
  static void show() {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false, 
      barrierColor: Colors.black.withOpacity(0.2), 
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, 
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0), 
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface, 
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 24,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Loader(
                  size: 50, 
                  color: Theme.of(context).colorScheme.primary, 
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Hides the loader WITHOUT needing context
  static void hide() {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}