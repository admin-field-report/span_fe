import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../controllers/inspection_controller.dart'; 

class InspectionDetailsScreen extends StatefulWidget {
  final String inspectionId;

  const InspectionDetailsScreen({
    super.key,
    required this.inspectionId,
  });

  @override
  State<InspectionDetailsScreen> createState() => _InspectionDetailsScreenState();
}

class _InspectionDetailsScreenState extends State<InspectionDetailsScreen> {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspectionController.fetchInspectionDetails(widget.inspectionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: inspectionController,
      builder: (context, _) {
        
        // ---------------------------------------------------------
        // 1. MODERN SKELETON LOADING STATE
        // ---------------------------------------------------------
        if (inspectionController.isDetailsLoading) {
          return _buildSkeletonLoader(theme);
        }

        // ---------------------------------------------------------
        // 2. ERROR STATE
        // ---------------------------------------------------------
        if (inspectionController.detailsError != null) {
          return _buildErrorState(theme);
        }

        final documents = inspectionController.documents;
        final mediaUrls = inspectionController.mediaUrls;

        // ---------------------------------------------------------
        // 3. EMPTY STATE
        // ---------------------------------------------------------
        if (documents.isEmpty && mediaUrls.isEmpty) {
          return _buildEmptyState(context, theme);
        }

        // ---------------------------------------------------------
        // 4. SUCCESS STATE (Modern UI)
        // ---------------------------------------------------------
        return Padding(
          padding: const EdgeInsets.only(top: 8.0), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, theme),
              const SizedBox(height: 32),
              
              _buildSectionTitle("Documents", documents.length, theme),
              const SizedBox(height: 16),
              _buildDocumentsList(theme, documents),
              
              const SizedBox(height: 40),
              
              _buildSectionTitle("Inspection Media", mediaUrls.length, theme),
              const SizedBox(height: 16),
              _buildMediaGrid(theme, mediaUrls),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // UI BUILDERS
  // =========================================================

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: theme.colorScheme.onSurface,
        ),
        const SizedBox(width: 8),
        Text(
          "Inspection Detail",
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count, ThemeData theme) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsList(ThemeData theme, List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return _buildEmptySection(theme, "No documents attached.");
    }

    // Upgraded to ListView.builder to easily handle "n" number of documents
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final docName = doc['document_name'] ?? 'Document ${index + 1}'; 
        final docUrl = doc['document_url'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            // Added subtle shadow for depth
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final String documentId = doc['id']; 
                final String projectDocumentId = doc['project_document_id'] ?? '';

                final currentPath = GoRouterState.of(context).uri.path;
                final cleanPath = currentPath.endsWith('/') 
                    ? currentPath.substring(0, currentPath.length - 1) 
                    : currentPath;
                    
                final canvasUrl = '$cleanPath/canvas/$projectDocumentId?document=$documentId&page=1';
                
                context.go(
                  canvasUrl,
                  extra: () {
                    if (mounted) {
                      inspectionController.fetchInspectionDetails(widget.inspectionId);
                    }
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    // Added a modern file icon indicator
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            docUrl.split('/').last, // Show just the filename for cleaner UI
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaGrid(ThemeData theme, List<String> mediaUrls) {
    if (mediaUrls.isEmpty) {
      return _buildEmptySection(theme, "No media attached.");
    }

    return GridView.builder(
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250, // Slightly smaller to fit more in the row nicely
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0, 
      ),
      itemCount: mediaUrls.length,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              mediaUrls[index],
              fit: BoxFit.cover, 
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SkeletonContainer(); // Use skeleton while image loads
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================
  // STATE WIDGETS (Skeletons, Errors, Empty)
  // =========================================================

  Widget _buildSkeletonLoader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonContainer(width: 40, height: 40, isCircle: true),
              const SizedBox(width: 16),
              const SkeletonContainer(width: 200, height: 28),
            ],
          ),
          const SizedBox(height: 32),
          const SkeletonContainer(width: 120, height: 20),
          const SizedBox(height: 16),
          const SkeletonContainer(width: double.infinity, height: 80),
          const SizedBox(height: 12),
          const SkeletonContainer(width: double.infinity, height: 80),
          const SizedBox(height: 40),
          const SkeletonContainer(width: 150, height: 20),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: 4, // Show 4 fake skeleton squares
            itemBuilder: (context, index) => const SkeletonContainer(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            inspectionController.detailsError!,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => inspectionController.fetchInspectionDetails(widget.inspectionId),
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined, size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            "No Data Found",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "This inspection doesn't have any documents or media yet.",
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Go Back"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, color: theme.colorScheme.outlineVariant, size: 32),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }
}

// =========================================================
// REUSABLE SKELETON ANIMATION WIDGET
// =========================================================
class SkeletonContainer extends StatefulWidget {
  final double? width;
  final double? height;
  final bool isCircle;

  const SkeletonContainer({
    super.key,
    this.width,
    this.height,
    this.isCircle = false,
  });

  @override
  State<SkeletonContainer> createState() => _SkeletonContainerState();
}

class _SkeletonContainerState extends State<SkeletonContainer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true); // Pulses back and forth
    
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine)
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle ? null : BorderRadius.circular(12),
        ),
      ),
    );
  }
}