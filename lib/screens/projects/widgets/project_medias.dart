import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/project_controller.dart';
import '../../../utils/app_responsive.dart';
import '../../../models/project.dart';

class ProjectMediaTab extends StatefulWidget {
    final String projectId;

  const ProjectMediaTab({super.key, required this.projectId});

  @override
  State<ProjectMediaTab> createState() => _ProjectMediaTabState();
}


class _ProjectMediaTabState extends State<ProjectMediaTab> {

  @override
  void initState() {
    super.initState();
    projectController.getAllProjectMedia(widget.projectId);
  }

  String formatInspectionDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectController,
      builder: (context, _) {
        final groups = projectController.groupedMedia;
        final int crossAxisCount = AppResponsive.isDesktopScreen(context) ? 5 : 2;

        if (projectController.isMediaLoading) return _buildSkeletonGrid(crossAxisCount);
        if (groups.isEmpty) return const Center(child: Text("No media found."));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- SECTION TITLE: "Inspection as of Feb 23, 2026" ---
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.blue),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Inspection as of ${formatInspectionDate(group.createTime)}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              letterSpacing: 0.3
                            ),
                          ),
                          Text(
                            "${group.items.length} Images",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // --- THE GRID ---
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: group.items.length,
                  itemBuilder: (context, itemIndex) {
                    return MediaCard(
                      imageUrl: group.items[itemIndex].imageUrl,
                      tags: group.items[itemIndex].tags,
                    );
                  },
                ),
                const SizedBox(height: 32), // Space between groups
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSkeletonGrid(int crossAxisCount) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(), // Disable scrolling while loading
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: 10, // Show 10 skeleton cards
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Container(color: Colors.white10)), // Image area
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(width: 60, height: 12, color: Colors.white10), // Tag area
            ),
          ],
        ),
      ),
    );
  }
}


class MediaCard extends StatelessWidget {
  final String imageUrl;
  final List<ProjectMediaTag> tags;

  const MediaCard({super.key, required this.imageUrl, required this.tags});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Image.network(
              imageUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              // 1. SMOOTH FADE: Prevents the image from "flashing" in
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              // 2. INNER LOADER: Small indicator while image downloads
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: tags.map((tag) => _buildTag(tag)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(ProjectMediaTag tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tag.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tag.color.withOpacity(0.4)),
      ),
      child: Text(
        tag.name.toUpperCase(),
        style: TextStyle(color: tag.color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}