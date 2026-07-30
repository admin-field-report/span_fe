import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme_controller.dart';
import '../../screens/auth/controllers/auth_controller.dart';
import '../../utils/app_responsive.dart';

class AppMenuContent extends StatelessWidget {
  final bool isCollapsed;
  final bool isMobile;

  const AppMenuContent({
    required this.isCollapsed,
    required this.isMobile,
    super.key,
  });

  PopupMenuItem<String> _buildPopupItem(BuildContext context, IconData icon, String label, String value) {
    final isSelected = value.startsWith('/') ? _isPathActive(context, value) : false;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodyMedium?.color;

    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final theme = Theme.of(context);

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _NavTile(
                    icon: Icons.folder_outlined,
                    label: "Projects",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/projects'),
                    onTap: () => _navigate(context, '/projects'),
                  ),
                  _buildTemplatesMenu(context, theme),
                  // _NavTile(
                  //   icon: Icons.architecture,
                  //   label: "Canvas",
                  //   isCollapsed: isCollapsed,
                  //   isSelected: _isPathActive(context, '/canvas'),
                  //   onTap: () => _navigate(context, '/canvas'),
                  // ),
                  // _NavTile(icon: Icons.groups_outlined, label: "Team", isCollapsed: isCollapsed),
                  _NavTile(
                    icon: Icons.auto_awesome,
                    label: "AI",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/ai'),
                    onTap: () => _navigate(context, '/ai'),
                  ),
                ],
              ),
            ),
            
            // =====================================
            // 🚀 FOOTER: Settings & Account
            // =====================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(color: theme.dividerColor.withOpacity(0.1), height: 1),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                children: [
                  // 🚀 Settings is now a standard route!
                  _NavTile(
                    icon: Icons.settings_outlined,
                    label: "Settings",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/settings'),
                    onTap: () => _navigate(context, '/settings'),
                  ),
                  _buildUserMenu(context, theme),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      }
    );
  }

  Widget _buildTemplatesMenu(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final mutedColor = theme.textTheme.bodyMedium?.color?.withOpacity(0.5);
    final isTemplateGroupActive = _isPathActive(context, '/templates');

    if (isCollapsed) {
      return Theme(
        data: theme.copyWith(
          popupMenuTheme: PopupMenuThemeData(
            color: theme.scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        child: PopupMenuButton<String>(
          offset: const Offset(70, 0),
          tooltip: "Templates",
          onSelected: (String path) => _navigate(context, path),
          itemBuilder: (BuildContext context) => [
            _buildPopupItem(context, Icons.assignment_outlined, "Project Templates", '/templates/projects'),
            _buildPopupItem(context, Icons.build_outlined, "Tools", '/templates/tools'),
            _buildPopupItem(context, Icons.label_outlined, "Tags", '/templates/tags'),
            _buildPopupItem(context, Icons.assessment_outlined, "Report Templates", '/templates/reports'),
          ],
          child: _NavTile(
            icon: Icons.description_outlined,
            label: "Templates", 
            isCollapsed: true,
            isSelected: isTemplateGroupActive, 
          ),
        ),
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: isTemplateGroupActive, 
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: colorScheme.primary,
        collapsedIconColor: mutedColor,
        leading: Icon(Icons.description_outlined, color: isTemplateGroupActive ? colorScheme.primary : mutedColor, size: 22),
        title: Text("Templates", style: TextStyle(color: isTemplateGroupActive ? colorScheme.primary : mutedColor, fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          _NavTile(icon: Icons.assignment_outlined, label: "Project Templates", isCollapsed: false, isSubItem: true, isSelected: _isPathActive(context, '/templates/projects'), onTap: () => _navigate(context, '/templates/projects')),
          _NavTile(icon: Icons.build_outlined, label: "Tools", isCollapsed: false, isSubItem: true, isSelected: _isPathActive(context, '/templates/tools'), onTap: () => _navigate(context, '/templates/tools')),
          _NavTile(icon: Icons.label_outlined, label: "Tags", isCollapsed: false, isSubItem: true, isSelected: _isPathActive(context, '/templates/tags'), onTap: () => _navigate(context, '/templates/tags')),
          _NavTile(icon: Icons.assessment_outlined, label: "Report Templates", isCollapsed: false, isSubItem: true, isSelected: _isPathActive(context, '/templates/reports'), onTap: () => _navigate(context, '/templates/reports')),
        ],
      ),
    );
  }

  // 🚀 2. THE TRIGGER TILE
  Widget _buildUserMenu(BuildContext context, ThemeData theme) {
    final user = authController.user;
    final userName = "${user?.firstName ?? ''} ${user?.lastName ?? ''}".trim();
    final displayName = userName.isNotEmpty ? userName : "Account";

    return Builder(
      builder: (buttonContext) {
        return _NavTile(
          icon: Icons.account_circle_outlined,
          label: displayName, 
          isCollapsed: isCollapsed,
          onTap: () {
            // Grab the exact physical coordinates of this specific tile
            final RenderBox renderBox = buttonContext.findRenderObject() as RenderBox;
            _showUserMenuPopover(context, renderBox, theme, displayName, user);
          },
        );
      }
    );
  }

  // 🚀 3. THE CUSTOM POPOVER LOGIC
  void _showUserMenuPopover(BuildContext context, RenderBox tileRenderBox, ThemeData theme, String displayName, dynamic user) {
    final colorScheme = theme.colorScheme;
    
    // Calculate the exact position of the tile
    final offset = tileRenderBox.localToGlobal(Offset.zero);
    final tileHeight = tileRenderBox.size.height;
    final tileWidth = tileRenderBox.size.width;

    // Failsafe for Mobile: Standard centered dialog since right-side popover would clip off screen
    if (AppResponsive.isMobileScreen(context)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: theme.scaffoldBackgroundColor,
          content: _buildPopoverContent(theme, colorScheme, displayName, user, context),
        )
      );
      return;
    }

    // Desktop/Tablet: Precise Floating Popover
    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Invisible backdrop (click anywhere to close)
      builder: (context) {
        return Stack(
          children: [
            // --- THE CARD ---
            Positioned(
              left: offset.dx + tileWidth + 12, // +12 width of the arrow
              // Align the bottom of the card with the bottom of the tile
              bottom: MediaQuery.of(context).size.height - offset.dy - tileHeight, 
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260, // 🚀 Fixed width prevents weird text wrapping!
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.15)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(4, 4))
                    ],
                  ),
                  child: _buildPopoverContent(theme, colorScheme, displayName, user, context),
                ),
              ),
            ),
            
            // --- THE ARROW ---
            Positioned(
              left: offset.dx + tileWidth,
              top: offset.dy + (tileHeight / 2) - 8, // Center the 16px arrow perfectly on the Y-axis of the tile
              child: CustomPaint(
                size: const Size(12, 16),
                painter: PopoverArrowPainter(
                  color: theme.scaffoldBackgroundColor,
                  borderColor: theme.dividerColor.withOpacity(0.15),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Extracted the UI content for cleanliness
  Widget _buildPopoverContent(ThemeData theme, ColorScheme colorScheme, String displayName, dynamic user, BuildContext dialogContext) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        CircleAvatar(
          radius: 32,
          backgroundColor: colorScheme.primary.withOpacity(0.1),
          child: Icon(Icons.person_outline, color: colorScheme.primary, size: 32),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          "${user?.email ?? ''}",
          style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),
        InkWell(
          onTap: () {
            Navigator.pop(dialogContext); // Close popover
            if (isMobile) Navigator.pop(dialogContext); // Close mobile drawer
            authController.logout();
          },
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: colorScheme.error, size: 18),
                const SizedBox(width: 8),
                Text("Sign Out", style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isPathActive(BuildContext context, String path) {
    final String location = GoRouterState.of(context).uri.toString();
    if (path == '/') return location == '/';
    return location.startsWith(path);
  }

  void _navigate(BuildContext context, String path) {
    if (isMobile) Navigator.pop(context);
    context.go(path);
  }
}

class _NavTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isCollapsed;
  final bool isSelected;
  final bool isSubItem;
  final VoidCallback? onTap;
  final Widget? trailing; // 🚀 Added to support the popover indicator

  const _NavTile({
    this.icon, 
    required this.label, 
    required this.isCollapsed, 
    this.isSelected = false, 
    this.isSubItem = false, 
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final activeBg = colorScheme.primary.withOpacity(0.08);
    final activeText = colorScheme.primary;
    final inactiveText = theme.textTheme.bodyMedium?.color?.withOpacity(0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.only(
            top: 12,
            bottom: 12,
            left: isCollapsed ? 0 : (isSubItem ? 42 : 12), 
            right: isCollapsed ? 0 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? activeBg : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (icon != null) 
                Icon(icon, size: isSubItem ? 18 : 22, color: isSelected ? activeText : inactiveText),
              if (!isCollapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label, 
                    style: TextStyle(
                      color: isSelected ? activeText : inactiveText, 
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, 
                      fontSize: isSubItem ? 12 : 13
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Show the active indicator OR the trailing widget (like the popover arrow)
                if (isSelected)
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  )
                else if (trailing != null)
                  trailing!
              ],
            ],
          ),
        ),
      ),
    );
  }
}


// 🚀 1. THE CUSTOM ARROW PAINTER
class PopoverArrowPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  PopoverArrowPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw the triangle pointing Left
    final path = Path()
      ..moveTo(size.width, 0) // Top right
      ..lineTo(0, size.height / 2) // Pointing left (middle)
      ..lineTo(size.width, size.height) // Bottom right
      ..close();

    canvas.drawPath(path, paint);

    // Draw the border (only on the top and bottom angled lines, leaving the right open so it blends into the card)
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final borderPath = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}