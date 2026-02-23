import 'package:flutter/material.dart';
import 'dart:async';

class ConstructionProject {
  final String title;
  final String description;
  final String image;

  ConstructionProject({required this.title, required this.description, required this.image});
}

class BrandingPanel extends StatefulWidget {
  const BrandingPanel({super.key});

  @override
  State<BrandingPanel> createState() => _BrandingPanelState();
}

class _BrandingPanelState extends State<BrandingPanel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  // 2. Mock Data List
  final List<ConstructionProject> projects = [
    ConstructionProject(
      title: "Skyline Residency Phase II",
      description: "Monitoring structural integrity and concrete pouring schedules for high-rise residential development.",
      image: "images/construction_1.jpg",
    ),
    ConstructionProject(
      title: "Grand Central Interchange",
      description: "Managing RFI/RFPs for complex infrastructure and multi-level transport hub synchronization.",
      image: "images/construction_2.jpg",
    ),
    ConstructionProject(
      title: "Industrial Logistics Park",
      description: "Real-time heavy machinery tracking and safety compliance for 500,000 sq. ft. warehouse facility.",
      image: "images/construction_3.jpg",
    ),
    ConstructionProject(
      title: "Harbor Bridge Refurbishment",
      description: "Coordinating sub-contractor workflows and material delivery logs for heritage bridge preservation.",
      image: "images/construction_4.jpg",
    ),
    ConstructionProject(
      title: "Sustainable Tech Campus",
      description: "Tracking LEED certification data and solar grid integration across the 50-acre innovation hub.",
      image: "images/construction_5.jpg",
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 3. Auto-loop Timer (5 seconds)
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_currentPage < projects.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Stack(
        children: [
          // 4. Image Slider
          PageView.builder(
            controller: _pageController,
            onPageChanged: (int page) => setState(() => _currentPage = page),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              return Image.asset(
                'assets/${projects[index].image}',
                fit: BoxFit.cover,
              );
            },
          ),

          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
              ),
            ),
          ),

          // 5. Navigation Icons
          Positioned(
            top: 0,
            bottom: 0,
            left: 10,
            child: _buildNavButton(Icons.chevron_left, () {
              _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
            }),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 10,
            child: _buildNavButton(Icons.chevron_right, () {
              _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
            }),
          ),

          // Slider Text & Indicators
          Positioned(
            bottom: 60,
            left: 40,
            right: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projects[_currentPage].title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  projects[_currentPage].description,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 30),
                
                // 6. Dot Indicators
                Row(
                  children: List.generate(projects.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 8),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index ? theme.colorScheme.primary : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    return Center(
      child: IconButton(
        icon: Icon(icon, color: Colors.white54, size: 40),
        onPressed: onTap,
      ),
    );
  }
}