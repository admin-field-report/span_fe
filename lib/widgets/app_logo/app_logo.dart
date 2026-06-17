import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final double padding;
  final Color? color;

  const AppLogo({
    super.key,
    this.size = 64.0, // Default size if none is provided
    this.padding = 12.0,
    this.color, // Optional color to tint the logo 
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final primaryColor = theme.brightness == Brightness.dark ? theme.colorScheme.primary.withOpacity(0.15) : theme.colorScheme.primary;
    
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        // 🚀 Primary transparent background as requested
        // color: theme.colorScheme.primary.withOpacity(0.15), 
        color: color ?? primaryColor, 
        // 🚀 Makes corners perfectly rounded based on whatever size you pass
        borderRadius: BorderRadius.circular(size * 0.25), 
      ),
      child: Image.asset(
        'assets/images/logo.png', // Make sure to update this to your actual asset path!
        fit: BoxFit.contain,
        // Optional: If your uploaded logo is a transparent PNG, uncomment the line below 
        // to automatically tint the white star to your app's primary color:
        // color: theme.colorScheme.primary, 
      ),
    );
  }
}