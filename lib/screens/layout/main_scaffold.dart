import 'package:flutter/material.dart';
import '../../core/theme_controller.dart'; 
import 'app_menu_content.dart';
import '../settings/settings_screen.dart';
import '../../utils/utils.dart';
import '../../screens/auth/controllers/auth_controller.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;
  final bool isScrollable;
  final bool removePadding;

  const MainScaffold({
    required this.child,
    this.isScrollable = true,
    this.removePadding = false,
    super.key
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  bool _isCollapsed = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        
        final bool isMobile = AppResponsive.isMobileScreen(context);
        final bool isTabletRange = AppResponsive.isTabletScreen(context);

        bool effectiveCollapsed = isMobile ? false : (isTabletRange ? !_isCollapsed : _isCollapsed);

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: theme.scaffoldBackgroundColor, 
          
          // --- 1. MOBILE DRAWER (Safe for Notch) ---
          drawer: isMobile
              ? Drawer(
                  width: 280,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildSidebarHeader(false, colorScheme),
                        Expanded(
                          child: AppMenuContent(isCollapsed: false, isMobile: true),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          endDrawer: const SettingsScreen(),
              
          body: SafeArea(
            child: Row(
              children: [
                // --- 2. SIDEBAR (Desktop/Tablet) ---
                if (!isMobile)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    width: (effectiveCollapsed ? 88.0 : 280.0) + 15.0, 
                    child: Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 15), 
                          decoration: BoxDecoration(
                            color: theme.scaffoldBackgroundColor,
                            border: Border(
                              right: BorderSide(
                                color: theme.dividerColor.withOpacity(isDark ? 0.2 : 0.12), 
                                width: 1,
                              ),
                            ),
                            boxShadow: isDark ? null : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(4, 0),
                              ),
                            ],
                          ),
                          // 🚀 3. Added Material so your Accordion/Menu InkWell clicks & ripples work perfectly!
                          child: Material(
                            color: Colors.transparent,
                            child: Column(
                              children: [
                                _buildSidebarHeader(effectiveCollapsed, colorScheme),
                                Expanded(
                                  child: AppMenuContent(
                                    isCollapsed: effectiveCollapsed, 
                                    isMobile: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // --- SIDEBAR TOGGLE ---
                        Positioned(
                          right: 0,
                          top: 40,
                          child: _buildToggleCircle(effectiveCollapsed, theme, colorScheme, isDark),
                        ),
                      ],
                    ),
                  ),
                
                // --- 3. MAIN CONTENT AREA ---
                Expanded(
                  child: Column(
                    children: [
                      // FIXED HEADER
                      _buildStickyHeader(context, isMobile, colorScheme, theme),
                      
                      // DYNAMIC BODY
                      // Expanded(
                      //   child: Padding(
                      //     padding: isMobile 
                      //         ? const EdgeInsets.fromLTRB(15, 10, 15, 20) 
                      //         : const EdgeInsets.fromLTRB(20, 0, 24, 20),
                      //     child: AnimatedContainer(
                      //       duration: const Duration(milliseconds: 300),
                      //       margin: isMobile ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 0, 16, 16),
                      //       child: ClipRRect(
                      //         borderRadius: BorderRadius.circular(8),
                      //         child: widget.child,
                      //       ),
                      //     ),
                      //   ),
                      // ),
                      // DYNAMIC BODY
                      Expanded(
                        child: Padding(
                          padding: widget.removePadding 
                              ? EdgeInsets.zero 
                              : (isMobile 
                                  ? const EdgeInsets.fromLTRB(15, 10, 15, 20) 
                                  : const EdgeInsets.fromLTRB(15, 0, 15, 15)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: widget.removePadding 
                                ? EdgeInsets.zero 
                                : (isMobile ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 0, 16, 16)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(widget.removePadding ? 0 : 8),
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- HELPER: TOGGLE BUTTON ---
  Widget _buildToggleCircle(bool collapsed, ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isCollapsed = !_isCollapsed),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Center(
            child: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 16,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
      ),
    );
  }

  // --- STICKY HEADER ---
  Widget _buildStickyHeader(BuildContext context, bool isMobile, ColorScheme colorScheme, ThemeData theme) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              color: colorScheme.onSurface,
            ),
          // const Spacer(),
          // IconButton(
          //   icon: const Icon(Icons.settings_outlined, size: 20),
          //   onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          //   color: colorScheme.onSurface.withOpacity(0.6),
          // ),
          // const SizedBox(width: 16),
          // _buildUserAvatar(theme, colorScheme),
        ],
      ),
    );
  }

  // --- USER AVATAR & POPOVER ---
  Widget _buildUserAvatar(ThemeData theme, ColorScheme colorScheme) {
    return PopupMenuButton(
      offset: const Offset(0, 50),
      surfaceTintColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.primary,
        child: const Icon(Icons.person, color: Colors.white, size: 20),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: _buildPopoverContent(theme, colorScheme)),
      ],
    );
  }

  Widget _buildSidebarHeader(bool collapsed, ColorScheme colorScheme) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_rounded, color: colorScheme.primary, size: 32),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                "Span Inspect", 
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPopoverContent(ThemeData theme, ColorScheme colorScheme) {
    final user = authController.user;
    return SizedBox(
      width: 220,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withOpacity(0.1),
              child: Icon(Icons.person_outline, color: colorScheme.primary),
            ),
            title: Text("${user?.firstName} ${user?.lastName}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("${user?.email}", style: const TextStyle(fontSize: 11)),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: colorScheme.error, size: 18),
            title: Text("Sign Out", style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              authController.logout();
            },
          ),
        ],
      ),
    );
  }
}