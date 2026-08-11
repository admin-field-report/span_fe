import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../controllers/project_controller.dart';
import '../../../utils/app_responsive.dart';
import '../../../models/project.dart';
import '../../../widgets/search_field/search_field.dart';

class ProjectMediaTab extends StatefulWidget {
    final String projectId;

  const ProjectMediaTab({super.key, required this.projectId});

  @override
  State<ProjectMediaTab> createState() => _ProjectMediaTabState();
}


class _ProjectMediaTabState extends State<ProjectMediaTab> {
  String _searchQuery = "";
  
  @override
  void initState() {
    super.initState();
    projectController.getAllProjectMedia(widget.projectId);
  }

  String formatInspectionDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  List<InspectionMediaGroup> getFilteredMedia() {
    if (_searchQuery.isEmpty) return projectController.groupedMedia;

    final query = _searchQuery.toLowerCase();

    return projectController.groupedMedia.map((group) {
      final filteredItems = group.items.where((item) {
        return item.tags.any((tag) => 
          tag.name.toLowerCase().contains(query)
        );
      }).toList();

      return InspectionMediaGroup(
        inspectionId: group.inspectionId,
        inspectionName: group.inspectionName,
        createTime: group.createTime,
        items: filteredItems,
      );
    }).where((group) => group.items.isNotEmpty).toList(); 
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return ListenableBuilder(
      listenable: projectController,
      builder: (context, _) {
        final groups = getFilteredMedia();
        final int crossAxisCount = AppResponsive.isDesktopScreen(context) ? 5 : 2;
        final bool isLoading = projectController.isMediaLoading;
        final bool isEmpty = groups.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Your toolbar stays sticky at the top!
            _buildTopToolbar(theme),
            const SizedBox(height: 10),

            // 🚀 THE FIX: Added Expanded & SingleChildScrollView
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Ensures it scrolls smoothly
                child: Builder(
                  builder: (context) {
                    if (isLoading) {
                      return _buildSkeletonGrid(crossAxisCount);
                    }

                    if (isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: _buildEmptyState(context),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: groups.map((group) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGroupHeader(group),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 40),
                        ],
                      )).toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }


  Widget _buildTopToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16), 
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              hintText: 'Seaerch By Tags',
              width: 350,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) ...[
            const Spacer(),
            Tooltip(
              message: 'Refresh Media',
              child: InkWell(
                onTap: projectController.isMediaLoading ? null : () {
                  projectController.getAllProjectMedia(widget.projectId);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded, 
                    size: 20, 
                    color: colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
              ),
            ),
          ],
        ],
      )
    );
  }

  Widget _buildGroupHeader(dynamic group) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // Icon
        Container(
          padding: const EdgeInsets.all(10), // Slightly larger padding for breathing room
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10), // Softer, more modern border radius
          ),
          child: Icon(Icons.camera_alt_rounded, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 14),
        
        // Title & Subtitle 
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Inspection as of ${formatInspectionDate(group.createTime)}",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3, // Tighter letter spacing is a hallmark of modern UI
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${group.items.length} Images",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // 🌟 MODERN VIEW DETAILS PILL BUTTON 🌟
        FilledButton.tonal(
          onPressed: () {
            final exactUrl = '/projects/details/${widget.projectId}/inspections/${group.inspectionId}';
            context.go(exactUrl);
          },
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.4), // Soft tinted background
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20), // Perfect pill shape
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "View Details",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              // Trailing chevron indicates forward navigation
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: theme.colorScheme.primary), 
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonGrid(int crossAxisCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 20),
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: 10,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.03), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12))
                )
              )
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 60, 
                    height: 10, 
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withOpacity(0.05), 
                      borderRadius: BorderRadius.circular(4)
                    )
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined, 
              size: 48, 
              color: colorScheme.onSurfaceVariant.withOpacity(0.2)
            ),
            const SizedBox(height: 16),
            Text(
              "No Records Found", 
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(0.6)
              )
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
              // Grid thumbnails: decode at a bounded size instead of the full
              // camera resolution — big memory + jank win on photo-heavy lists.
              cacheWidth: 800,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
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