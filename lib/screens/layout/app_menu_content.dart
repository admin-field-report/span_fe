
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme_controller.dart';

class AppMenuContent extends StatelessWidget {
  final bool isCollapsed;
  final bool isMobile;

  const AppMenuContent({
    required this.isCollapsed,
    required this.isMobile,
    super.key,
  });

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
                    icon: Icons.grid_view_rounded,
                    label: "Dashboard",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/'),
                    onTap: () => _navigate(context, '/'),
                  ),
                  _NavTile(
                    icon: Icons.folder_outlined,
                    label: "Projects",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/projects'),
                    onTap: () => _navigate(context, '/projects'),
                  ),
                  _buildTemplatesMenu(context, theme),
                  _NavTile(
                    icon: Icons.architecture,
                    label: "Canvas",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/canvas'),
                    onTap: () => _navigate(context, '/canvas'),
                  ),
                  _NavTile(icon: Icons.groups_outlined, label: "Team", isCollapsed: isCollapsed),
                  _NavTile(
                    icon: Icons.analytics_outlined,
                    label: "AI & Data",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/ai-data'),
                    onTap: () => _navigate(context, '/ai-data'),
                  ),
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

    if (isCollapsed) {
      return _NavTile(
        icon: Icons.description_outlined,
        label: "Templates",
        isCollapsed: true,
        onTap: () => _navigate(context, '/templates'),
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: colorScheme.primary,
        collapsedIconColor: mutedColor,
        leading: Icon(Icons.description_outlined, color: mutedColor, size: 22),
        title: Text("Templates", style: TextStyle(color: mutedColor, fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          _NavTile(icon: Icons.assignment_outlined, label: "Project Templates", isCollapsed: false, isSubItem: true, onTap: () => _navigate(context, '/templates/projects')),
          _NavTile(icon: Icons.build_outlined, label: "Tools", isCollapsed: false, isSubItem: true, onTap: () => _navigate(context, '/templates/tools')),
          _NavTile(icon: Icons.label_outlined, label: "Tags", isCollapsed: false, isSubItem: true, onTap: () => _navigate(context, '/templates/tags')),
          _NavTile(icon: Icons.assessment_outlined, label: "Reports", isCollapsed: false, isSubItem: true, onTap: () => _navigate(context, '/templates/reports')),
        ],
      ),
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

  const _NavTile({this.icon, required this.label, required this.isCollapsed, this.isSelected = false, this.isSubItem = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Dynamic styling based on selection and theme accent
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
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: isCollapsed ? 0 : 12),
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
                    )
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  )
              ],
            ],
          ),
        ),
      ),
    );
  }
}