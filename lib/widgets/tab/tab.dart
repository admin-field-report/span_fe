import 'package:flutter/material.dart';

class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<String> tabs;
  final Function(int)? onTap;
  final double horizontalPadding;

  const AppTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.onTap,
    this.horizontalPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: TabBar(
          controller: controller,
          onTap: onTap,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          physics: const BouncingScrollPhysics(),
          
          labelColor: isDark ? Colors.white : Colors.black,
          unselectedLabelColor: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.5),
          
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 3,
          indicatorColor: isDark ? Colors.white : Colors.black,
          
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          
          tabs: tabs.map((title) => Tab(text: title)).toList(),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(48);
}