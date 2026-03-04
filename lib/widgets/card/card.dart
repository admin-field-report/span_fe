// import 'package:flutter/material.dart';

// class AppCard extends StatelessWidget {
//   final Widget child;
//   final double borderRadius;
//   final EdgeInsetsGeometry? padding;
//   final Color? backgroundColor;
//   final BorderSide? border;
//   final VoidCallback? onTap;

//   const AppCard({
//     super.key,
//     required this.child,
//     this.borderRadius = 16.0,
//     this.padding,
//     this.backgroundColor,
//     this.border,
//     this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//       return Expanded(
//         child: Card(
//           elevation: 0,
//           shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(borderRadius),
//         ),
//         color: backgroundColor ?? theme.colorScheme.surfaceContainer,
//         clipBehavior: Clip.antiAlias,
//         child: InkWell(
//           onTap: onTap,
//           borderRadius: BorderRadius.circular(borderRadius),
//           child: Padding(
//             padding: padding ?? const EdgeInsets.all(20.0),
//             child: child,
//           ),
//         ),
//       )
//     );
//   }
// }

import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const AppCard({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
      ),
      color: backgroundColor ?? theme.colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20.0),
        child: child,
      ),
    );
  }
}