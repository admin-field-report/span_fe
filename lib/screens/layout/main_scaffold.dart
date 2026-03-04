import 'package:field_report_fe/screens/auth/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import '../../core/theme_controller.dart'; 
import 'app_menu_content.dart';
import '../settings/settings_screen.dart';
import '../../utils/utils.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;
  const MainScaffold({required this.child, super.key});

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
          
          // --- MOBILE DRAWER ---
          drawer: isMobile
              ? Drawer(
                  width: 280,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      _buildSidebarHeader(effectiveCollapsed, colorScheme),
                      Expanded(
                        child: AppMenuContent(
                          isCollapsed: effectiveCollapsed, 
                          isMobile: true,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          endDrawer: const SettingsScreen(),
              
          body: Row(
            children: [
              // --- SIDEBAR (Desktop/Tablet) ---
              if (!isMobile)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      width: effectiveCollapsed ? 88 : 280,
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        border: Border(
                          right: BorderSide(
                            color: theme.dividerColor.withOpacity(isDark ? 0.2 : 0.12), 
                            width: 1,
                          ),
                        ),
                        // Light mode shadow on the border
                        boxShadow: isDark ? null : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(4, 0),
                          ),
                        ],
                      ),
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
                    
                    // --- THE TOGGLE (Improved Hit-Zone) ---
                    Positioned(
                      right: -15,
                      top: 40,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _isCollapsed = !_isCollapsed);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.dividerColor.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 300),
                              turns: effectiveCollapsed ? 0.5 : 0,
                              child: Icon(
                                Icons.chevron_left,
                                size: 16,
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              
              // --- MAIN CONTENT --- running
              Expanded(
                child: Column(
                  children: [
                    _buildStickyHeader(context, isMobile, colorScheme, theme),
                    Expanded(
                      child: Padding(
                          padding: isMobile ? const EdgeInsets.symmetric(horizontal: 15, vertical: 20) : const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: isMobile ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 0, 16, 16),
                          child: ClipRRect(
                            // borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(24),
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- MAIN CONTENT --- failing inner comp
              // Expanded(
              //   child: Column(
              //     crossAxisAlignment: CrossAxisAlignment.stretch,
              //     children: [
              //       // 1. STICKY HEADER: Stays fixed at the top
              //       _buildStickyHeader(context, isMobile, colorScheme, theme),
                    
              //       // 2. SCROLLABLE BODY: The only vertical scroll in the app
              //       Expanded(
              //         child: SingleChildScrollView(
              //           key: const ValueKey('main_layout_scroll'),
              //           // physics: BouncingScrollPhysics makes it feel premium on web/mobile
              //           physics: const BouncingScrollPhysics(), 
              //           child: Padding(
              //             padding: EdgeInsets.symmetric(
              //               horizontal: isMobile ? 16 : 24, 
              //               vertical: 20
              //             ),
              //             child: Column(
              //               // IMPORTANT: mainAxisSize.min tells the ScrollView 
              //               // exactly how much space to create.
                            
              //               mainAxisSize: MainAxisSize.min, 
              //               children: [
              //                 // widget.child is your CommonTable wrapped in AppCard
              //                 widget.child, 
              //                 // SizedBox( height: 2000),
              //               ],
              //             ),
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),

            ],
          ),
        );
      },
    );
  }

  // --- STICKY HEADER ---
  Widget _buildStickyHeader(BuildContext context, bool isMobile, ColorScheme colorScheme, ThemeData theme) {
  return Container(
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      children: [
        // MOBILE MENU ICON (Left Side Drawer)
        if (isMobile)
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            color: colorScheme.onSurface,
          ),
        
        const Spacer(),
        
        // SETTINGS ICON (Right Side Drawer)
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        
        const SizedBox(width: 16),
        
       // --- USER POPOVER ---
        PopupMenuButton(
          offset: const Offset(0, 50),
          padding: EdgeInsets.zero,
          surfaceTintColor: theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.1)),
          ),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primary,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: _buildPopoverContent(theme, colorScheme),
            ),
          ],
        ),
      ],
    ),
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
                "Field Report", 
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
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.primary.withOpacity(0.1),
                  child: Icon(Icons.person_outline, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${authController.user?.firstName} ${authController.user?.lastName}',
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${authController.user?.email}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5)
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Logout Footer Action
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.pop(context);
                authController.logout();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: colorScheme.error),
                    const SizedBox(width: 12),
                    Text(
                      "Sign Out",
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}