
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

  PopupMenuItem<String> _buildPopupItem(BuildContext context, IconData icon, String label, String path) {
    final isSelected = _isPathActive(context, path);
    final color = isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodyMedium?.color;

    return PopupMenuItem<String>(
      value: path,
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
                  // _NavTile(
                  //   icon: Icons.grid_view_rounded,
                  //   label: "Dashboard",
                  //   isCollapsed: isCollapsed,
                  //   isSelected: _isPathActive(context, '/'),
                  //   onTap: () => _navigate(context, '/'),
                  // ),
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
                    icon: Icons.auto_awesome,
                    label: "AI",
                    isCollapsed: isCollapsed,
                    isSelected: _isPathActive(context, '/ai'),
                    onTap: () => _navigate(context, '/ai'),
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

    // Check if we are currently anywhere inside the templates section
    final isTemplateGroupActive = _isPathActive(context, '/templates');

    if (isCollapsed) {
      // 🚀 FLYOUT MENU FOR COLLAPSED STATE
      return Theme(
        // Wraps the popup in your theme colors to match the app
        data: theme.copyWith(
          popupMenuTheme: PopupMenuThemeData(
            color: theme.scaffoldBackgroundColor, // Background color of the popup
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        child: PopupMenuButton<String>(
          offset: const Offset(70, 0), // 🚀 Pushes the menu directly to the right of the sidebar
          tooltip: "Templates",
          onSelected: (String path) => _navigate(context, path),
          itemBuilder: (BuildContext context) => [
            _buildPopupItem(context, Icons.assignment_outlined, "Project Templates", '/templates/projects'),
            _buildPopupItem(context, Icons.build_outlined, "Tools", '/templates/tools'),
            _buildPopupItem(context, Icons.label_outlined, "Tags", '/templates/tags'),
            _buildPopupItem(context, Icons.assessment_outlined, "Reports", '/templates/reports'),
          ],
          // The child is your standard tile. PopupMenuButton automatically intercepts the tap!
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
        initiallyExpanded: isTemplateGroupActive, // 🚀 Keeps menu open if a sub-item is selected!
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: colorScheme.primary,
        collapsedIconColor: mutedColor,
        leading: Icon(Icons.description_outlined, color: isTemplateGroupActive ? colorScheme.primary : mutedColor, size: 22),
        title: Text("Templates", style: TextStyle(color: isTemplateGroupActive ? colorScheme.primary : mutedColor, fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          _NavTile(
            icon: Icons.assignment_outlined, 
            label: "Project Templates", 
            isCollapsed: false, 
            isSubItem: true, 
            isSelected: _isPathActive(context, '/templates/projects'), // 🚀 Now gets highlighted!
            onTap: () => _navigate(context, '/templates/projects')
          ),
          _NavTile(
            icon: Icons.build_outlined, 
            label: "Tools", 
            isCollapsed: false, 
            isSubItem: true, 
            isSelected: _isPathActive(context, '/templates/tools'), // 🚀 Now gets highlighted!
            onTap: () => _navigate(context, '/templates/tools')
          ),
          _NavTile(
            icon: Icons.label_outlined, 
            label: "Tags", 
            isCollapsed: false, 
            isSubItem: true, 
            isSelected: _isPathActive(context, '/templates/tags'), // 🚀 Now gets highlighted!
            onTap: () => _navigate(context, '/templates/tags')
          ),
          // _NavTile(
          //   icon: Icons.assessment_outlined, 
          //   label: "Reports", 
          //   isCollapsed: false, 
          //   isSubItem: true, 
          //   isSelected: _isPathActive(context, '/templates/reports'), // 🚀 Now gets highlighted!
          //   onTap: () => _navigate(context, '/templates/reports')
          // ),
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
          // 🚀 MAGIC HERE: Pushes the content inward if it's a sub-item, 
          // but keeps the background color spanning the full width of the tile.
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