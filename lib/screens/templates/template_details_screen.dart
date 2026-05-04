import 'package:field_report_fe/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/button/button.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../../models/template.dart';
import '../../models/tag_models.dart';
import '../tools/models/tool_group.dart';
import './controllers/template_controller.dart';

// ==========================================
// RIGHT PANE: REUSABLE DETAILS COMPONENT
// ==========================================
class TemplateDetailPanel extends StatefulWidget {
  final Template template;

  const TemplateDetailPanel({super.key, required this.template});

  @override
  State<TemplateDetailPanel> createState() => _TemplateDetailPanelState();
}

class _TemplateDetailPanelState extends State<TemplateDetailPanel> with SingleTickerProviderStateMixin {

late TabController _tabController;
final Set<int> _fetchedTabs = {};

  @override
  void initState() {
    super.initState();
    
    // 🚀 2. INITIALIZE THE TAB CONTROLLER AND LISTENER
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    // Fetch data for the FIRST tab when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDataForTab(0); 
    });
  }

  // 🚀 2. REWRITE THIS METHOD
  void _fetchDataForTab(int tabIndex) {
    // If we already fetched this tab for the current template, do nothing!
    if (_fetchedTabs.contains(tabIndex)) return;

    final templateId = widget.template.id;
    
    // Mark this tab as fetched so we don't fetch it again
    _fetchedTabs.add(tabIndex);

    if (tabIndex == 0) {
      templateController.getTagGroupsForTemplate(templateId);
    } else if (tabIndex == 1) {
      templateController.getToolGroupsForTemplate(templateId);
    } else if (tabIndex == 2) {
      templateController.getDocumentsForTemplate(templateId);
    }
  }

  void _handleTabSelection() {
    // We removed the 'indexIsChanging' check entirely. 
    // Our _fetchedTabs Set safely prevents this from spamming the API!
    _fetchDataForTab(_tabController.index);
  }


  // 🚀 2. UPDATE THE WIDGET LIFECYCLE
  @override
  void didUpdateWidget(covariant TemplateDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the user clicked a different template...
    if (oldWidget.template.id != widget.template.id) {
      
      // 1. Wipe the memory of what we've fetched
      _fetchedTabs.clear(); 
      
      // 2. Instantly clear the old data from the screen so it doesn't flash
      templateController.clearTemplateDetails();
      
      // 3. Reset the UI back to the first tab (Standard Master-Detail UX)
      if (_tabController.index != 0) {
        _tabController.animateTo(0); 
        // Note: animateTo(0) automatically triggers _handleTabSelection, which fetches the API!
      } else {
        // If they were already on the first tab, manually trigger the fetch
        _fetchDataForTab(0);
      }
    }
  }

  void _deleteDocument(TemplateDocument doc) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return ConfirmationDialog(
          title: "Delete Document",
          description: "Are you sure you want to delete '${doc.displayName}'?",
          confirmLabel: "Delete",
          confirmColor: Colors.red,
          onConfirm: () async {
            // 1. Call the API
            bool success = await templateController.deleteDocument(doc.id);

            if (success) {
              // 2. Show Success Toast
              if (mounted) {
                ToastService.show(
                  context, 
                  message: "Document deleted successfully!", 
                  type: ToastType.success
                );
              }
              templateController.getDocumentsForTemplate(widget.template.id);
              
            } else {
              // Show Error Toast and throw exception to keep dialog open/stop spinner
              if (mounted) {
                ToastService.show(
                  context, 
                  message: "Failed to delete document.", 
                  type: ToastType.error
                );
              }
              throw Exception("API Deletion Failed"); 
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 🚀 Grab the data directly from your controller
    final isLoading = templateController.isDetailLoading;
    final tagGroups = templateController.currentTagGroups;

    final isToolsLoading = templateController.isToolGroupsLoading;
    final toolGroups = templateController.currentToolGroups;

    return DefaultTabController(
      length: 3,
      child: Container(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            // PANEL HEADER
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      widget.template.name, 
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(6)),
                    child: Text("ID: ${widget.template.id}", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            
            TabBar(
              controller: _tabController,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              tabs: const [Tab(text: "Tag Groups"), Tab(text: "Tool Sets"), Tab(text: "Documents")],
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

            // TABS CONTENT
            Expanded(
              // 🚀 Wait for controller to finish loading
              child: isLoading 
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : TabBarView(
                  controller: _tabController,
                    children: [
                      // 🚀 THE TAG GROUPS TAB
                      _buildTabContent(
                        theme: theme, 
                        isLoading: templateController.isDetailLoading,
                        title: "Assigned Tag Groups", 
                        itemCount: tagGroups.length,
                        emptyMessage: "No tag groups assigned yet.",
                        onActionButtonPressed: () {
                          _openManageTagsModal(context, templateController.currentTagGroups);
                        },
                        itemBuilder: (context, index) {
                          final group = tagGroups[index];
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name, 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                                ),
                                const SizedBox(height: 8),
                                
                                group.tags.isEmpty
                                    ? Text("No tags in this group.", style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant))
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: group.tags.map((tag) => _buildTagChip(tag)).toList(),
                                      )
                              ],
                            ),
                          );
                        }
                      ),
                      
                      // Placeholder for Tool Sets Tab
                      _buildTabContent(
                        theme: theme, 
                        isLoading: templateController.isToolGroupsLoading,
                        title: "Assigned Tool Sets", 
                        itemCount: toolGroups.length, 
                        emptyMessage: "No tool sets assigned yet.", 
                        // 🚀 HOOKED UP!
                        onActionButtonPressed: () => _openManageToolSetsModal(context, toolGroups),
                        itemBuilder: (context, index) {
                          final group = toolGroups[index];
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name, 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                                ),
                                const SizedBox(height: 8),
                                
                                group.tools.isEmpty
                                    ? Text("No tools in this set.", style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant))
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: group.tools.map((tool) {
                                          // 🚀 Clean, subtle UI chips for the tools!
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.build_circle_outlined, size: 14, color: theme.colorScheme.primary),
                                                const SizedBox(width: 6),
                                                Text(tool.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      )
                              ],
                            ),
                          );
                        }
                      ),
                      
                      // Placeholder for Documents Tab
                      // 🚀 THE DOCUMENTS TAB
                      _buildTabContent(
                        theme: theme, 
                        isLoading: templateController.isDocumentsLoading, 
                        title: "Template Documents", 
                        itemCount: templateController.currentDocuments.length, 
                        emptyMessage: "No documents uploaded yet.", 
                        
                        // 🚀 CUSTOMIZE THE BUTTON
                        buttonLabel: "Upload Document",
                        buttonIcon: Icons.upload_file,
                        onActionButtonPressed: () => _openUploadDocumentModal(context),
                        
                        itemBuilder: (context, index) {
                          final doc = templateController.currentDocuments[index];
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
                            ),
                            title: Text(
                              doc.displayName, // 🚀 Uses our magic getter
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                "Uploaded: ${doc.formattedDate}", 
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: "Delete Document",
                              onPressed: () => _deleteDocument(doc),
                            ),
                          );
                        }
                      ),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 REFACTORED TAG CHIP (Much cleaner since the Model handles the hex conversion now!)
  Widget _buildTagChip(AppTag tag) {
    // Determine text color based on the actual background color luminance
    Color textColor = tag.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    bool isWhiteBg = tag.color == Colors.white || tag.color.computeLuminance() > 0.95;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tag.color, // Direct from your model
        borderRadius: BorderRadius.circular(16),
        border: isWhiteBg ? Border.all(color: Colors.grey.shade300) : null,
      ),
      child: Text(
        tag.name,
        style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildTabContent({
    required ThemeData theme, 
    required bool isLoading, 
    required String title, 
    required int itemCount,
    required String emptyMessage,
    String buttonLabel = "Manage", // Default is Manage
    IconData buttonIcon = Icons.settings, // Default is Settings
    required VoidCallback onActionButtonPressed, 
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),

              Button(
                label: buttonLabel,
                onPressed: onActionButtonPressed,
                variant: ButtonVariant.outline,
                icon: buttonIcon,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isLoading 
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : itemCount == 0
                  ? Center(child: Text(emptyMessage, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                  : Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: ListView.separated(
                        itemCount: itemCount,
                        separatorBuilder: (context, index) => Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                        itemBuilder: itemBuilder,
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _openManageTagsModal(BuildContext context, List<AppTagGroup> assignedGroups) async {
    final isDesktop = MediaQuery.of(context).size.width >= 800; // Your breakpoint

    bool? didUpdate;

    if (isDesktop) {
      // 🚀 DESKTOP: Show Dialog
      didUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
            child: ManageTagGroupsContent(
              templateId: widget.template.id,
              currentlyAssigned: assignedGroups,
              isMobile: false,
            ),
          ),
        ),
      );
    } else {
      // 🚀 MOBILE: Show Bottom Sheet
      didUpdate = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true, // Allows it to take up more screen height
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
          // Adjust for keyboard popping up
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: ManageTagGroupsContent(
              templateId: widget.template.id,
              currentlyAssigned: assignedGroups,
              isMobile: true,
            ),
          ),
        ),
      );
    }

    // Refresh data if saved successfully
    if (didUpdate == true && mounted) {
      templateController.getTagGroupsForTemplate(widget.template.id);
    }
  }

  Future<void> _openManageToolSetsModal(BuildContext context, List<TemplateToolGroup> assignedGroups) async {
    final isDesktop = MediaQuery.of(context).size.width >= 800; // Your breakpoint

    bool? didUpdate;

    if (isDesktop) {
      // 🚀 DESKTOP: Show Dialog
      didUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
            child: ManageToolSetsContent( // 🚀 Uses the Tool Sets Modal
              templateId: widget.template.id,
              currentlyAssigned: assignedGroups,
              isMobile: false,
            ),
          ),
        ),
      );
    } else {
      // 🚀 MOBILE: Show Bottom Sheet
      didUpdate = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true, // Allows it to take up more screen height
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Padding(
          // Adjust for keyboard popping up
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: ManageToolSetsContent( // 🚀 Uses the Tool Sets Modal
              templateId: widget.template.id,
              currentlyAssigned: assignedGroups,
              isMobile: true,
            ),
          ),
        ),
      );
    }

    // Refresh data if saved successfully
    if (didUpdate == true && mounted) {
      templateController.getToolGroupsForTemplate(widget.template.id);
    }
  }

  Future<void> _openUploadDocumentModal(BuildContext context) async {
    final didUpload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: UploadDocumentModal(templateId: widget.template.id),
        ),
      ),
    );

    // Refresh the Document tab data if the upload was successful
    if (didUpload == true && mounted) {
      ToastService.show(
        context, 
        message: "Document uploaded successfully!", 
        type: ToastType.success
      );
      templateController.getDocumentsForTemplate(widget.template.id); 
    }
  }
}


enum TagFilter { all, selected, unselected }

class ManageTagGroupsContent extends StatefulWidget {
  final String templateId;
  final List<AppTagGroup> currentlyAssigned;
  final bool isMobile;

  const ManageTagGroupsContent({
    super.key,
    required this.templateId,
    required this.currentlyAssigned,
    required this.isMobile,
  });

  @override
  State<ManageTagGroupsContent> createState() => _ManageTagGroupsContentState();
}

class _ManageTagGroupsContentState extends State<ManageTagGroupsContent> {
  bool _isLoading = true;
  bool _isSaving = false;
  
  List<AppTagGroup> _masterList = [];
  late Set<String> _selectedIds;
  
  String _searchQuery = '';
  TagFilter _currentFilter = TagFilter.all;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.currentlyAssigned.map((g) => g.id).toSet();
    _fetchMasterList();
  }

  Future<void> _fetchMasterList() async {
    // Uses the controller method we set up earlier!
    final list = await templateController.getAllMasterTagGroups();
    if (mounted) {
      setState(() {
        _masterList = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    bool success = await templateController.assignTagsToTemplate(
      templateId: widget.templateId, 
      tagGroupIds: _selectedIds.toList(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
      ToastService.show(context, message: "Tag Groups updated!", type: ToastType.success);
    } else {
      setState(() => _isSaving = false);
      ToastService.show(context, message: "Failed to update Tag Groups.", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 🚀 1. Apply Search Filter
    var filteredList = _masterList.where((g) => 
      g.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    // 🚀 2. Apply Selection Filter (All / Selected / Unselected)
    if (_currentFilter == TagFilter.selected) {
      filteredList = filteredList.where((g) => _selectedIds.contains(g.id)).toList();
    } else if (_currentFilter == TagFilter.unselected) {
      filteredList = filteredList.where((g) => !_selectedIds.contains(g.id)).toList();
    }

    return PopScope(
      canPop: !_isSaving, 
      
      child: AbsorbPointer(
          absorbing: _isSaving, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Padding(
                padding: EdgeInsets.only(
                  left: 24.0, right: 16.0, 
                  top: widget.isMobile ? 16.0 : 24.0, 
                  bottom: 16.0
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Manage Tag Groups", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
              ),
              
              // SEARCH BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SearchField(
                  width: 350,
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 16),

              // FILTER CHIPS (All | Selected | Unselected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip("All", TagFilter.all, theme),
                    _buildFilterChip("Selected (${_selectedIds.length})", TagFilter.selected, theme),
                    _buildFilterChip("Unselected", TagFilter.unselected, theme),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

              // THE LIST
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : filteredList.isEmpty
                        ? Center(child: Text("No groups match your filters.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                        : ListView.builder(
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final group = filteredList[index];
                              final isSelected = _selectedIds.contains(group.id);

                              return CheckboxListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                value: isSelected,
                                activeColor: theme.colorScheme.primary,
                                controlAffinity: ListTileControlAffinity.trailing,
                                onChanged: (bool? checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedIds.add(group.id);
                                    } else {
                                      _selectedIds.remove(group.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

              // ACTIONS
              Padding(
                padding: EdgeInsets.only(
                  left: 24.0, right: 24.0, 
                  top: 16.0, 
                  bottom: widget.isMobile ? 32.0 : 24.0 // Extra padding on mobile for home bars
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(
                      label: "Cancel",
                      variant: ButtonVariant.outline,
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Button(
                      label: "Save Changes",
                      variant: ButtonVariant.filled,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _save,
                    ),
                  ],
                ),
              ),
            ],
          )
        ),
    );
  }

  // Helper for the Filter Chips
  Widget _buildFilterChip(String label, TagFilter filterValue, ThemeData theme) {
    final isSelected = _currentFilter == filterValue;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primaryContainer,
      onSelected: (_) => setState(() => _currentFilter = filterValue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: isSelected ? Colors.transparent : theme.colorScheme.outlineVariant),
    );
  }
}




enum ToolSetFilter { all, selected, unselected }

class ManageToolSetsContent extends StatefulWidget {
  final String templateId;
  final List<TemplateToolGroup> currentlyAssigned;
  final bool isMobile;

  const ManageToolSetsContent({
    super.key,
    required this.templateId,
    required this.currentlyAssigned,
    required this.isMobile,
  });

  @override
  State<ManageToolSetsContent> createState() => _ManageToolSetsContentState();
}

class _ManageToolSetsContentState extends State<ManageToolSetsContent> {
  bool _isLoading = true;
  bool _isSaving = false;
  
  List<ToolGroup> _masterList = [];
  late Set<String> _selectedIds;
  
  String _searchQuery = '';
  ToolSetFilter _currentFilter = ToolSetFilter.all;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.currentlyAssigned.map((g) => g.customToolGroupId).toSet();
    _fetchMasterList();
  }

  Future<void> _fetchMasterList() async {
    final list = await templateController.getAllMasterToolGroups();
    if (mounted) {
      setState(() {
        _masterList = list;
        _isLoading = false;
      });
    }
  }


  Future<void> _save() async {
    setState(() => _isSaving = true);

    bool success = await templateController.assignToolGroupsToTemplate(
      templateId: widget.templateId, 
      toolGroupIds: _selectedIds.toList(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
      ToastService.show(context, message: "Tool Groups updated!", type: ToastType.success);
    } else {
      setState(() => _isSaving = false);
      ToastService.show(context, message: "Failed to update Tool Groups.", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Apply Search Filter
    var filteredList = _masterList.where((g) => 
      g.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    // 2. Apply Selection Filter
    if (_currentFilter == ToolSetFilter.selected) {
      filteredList = filteredList.where((g) => _selectedIds.contains(g.id)).toList();
    } else if (_currentFilter == ToolSetFilter.unselected) {
      filteredList = filteredList.where((g) => !_selectedIds.contains(g.id)).toList();
    }

    return PopScope(
      canPop: !_isSaving,
      child: AbsorbPointer(
          absorbing: _isSaving, 
          child:Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Padding(
                padding: EdgeInsets.only(
                  left: 24.0, right: 16.0, 
                  top: widget.isMobile ? 16.0 : 24.0, 
                  bottom: 16.0
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Manage Tool Sets", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                  ],
                ),
              ),
              
              // SEARCH BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SearchField(
                  width: 350,
                  hintText: "Search tool sets...",
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 16),

              // FILTER CHIPS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip("All", ToolSetFilter.all, theme),
                    _buildFilterChip("Selected (${_selectedIds.length})", ToolSetFilter.selected, theme),
                    _buildFilterChip("Unselected", ToolSetFilter.unselected, theme),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

              // THE LIST
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : filteredList.isEmpty
                        ? Center(child: Text("No tool sets match your filters.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                        : ListView.builder(
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final group = filteredList[index];
                              final isSelected = _selectedIds.contains(group.id);

                              return CheckboxListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                value: isSelected,
                                activeColor: theme.colorScheme.primary,
                                controlAffinity: ListTileControlAffinity.trailing,
                                onChanged: (bool? checked) {
                                  setState(() {
                                    checked == true ? _selectedIds.add(group.id) : _selectedIds.remove(group.id);
                                  });
                                },
                              );
                            },
                          ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

              // ACTIONS
              Padding(
                padding: EdgeInsets.only(
                  left: 24.0, right: 24.0, 
                  top: 16.0, 
                  bottom: widget.isMobile ? 32.0 : 24.0
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(
                      label: "Cancel",
                      variant: ButtonVariant.outline,
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Button(
                      label: "Save Changes",
                      variant: ButtonVariant.filled,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _save,
                    ),
                  ],
                ),
              ),
            ],
          )
      )
    );
  }

  Widget _buildFilterChip(String label, ToolSetFilter filterValue, ThemeData theme) {
    final isSelected = _currentFilter == filterValue;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primaryContainer,
      onSelected: (_) => setState(() => _currentFilter = filterValue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: isSelected ? Colors.transparent : theme.colorScheme.outlineVariant),
    );
  }
}



class UploadDocumentModal extends StatefulWidget {
  final String templateId;

  const UploadDocumentModal({super.key, required this.templateId});

  @override
  State<UploadDocumentModal> createState() => _UploadDocumentModalState();
}

class _UploadDocumentModalState extends State<UploadDocumentModal> {
  PlatformFile? _selectedFile;
  bool _isUploading = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // 🚀 Crucial for cross-platform (Web & Mobile) byte extraction
    );

    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null) return;

    setState(() => _isUploading = true);

    // Call the controller method we just built
    bool success = await templateController.uploadDocument(widget.templateId, _selectedFile!);

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (success) {
      Navigator.pop(context, true); // Return true to trigger a refresh
    } else {
      // Show error snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload failed. Please try again."), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Upload Document", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 24),

          // --- UPLOAD AREA ---
          GestureDetector(
            onTap: _isUploading ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedFile != null ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  style: BorderStyle.solid,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedFile != null ? Icons.picture_as_pdf : Icons.upload_file,
                    size: 48,
                    color: _selectedFile != null ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  
                  if (_selectedFile == null) ...[
                    const Text("Click to select a PDF file", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Only .pdf files are supported", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  ] else ...[
                    Text(_selectedFile!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text("${(_selectedFile!.size / 1024 / 1024).toStringAsFixed(2)} MB", style: TextStyle(color: theme.colorScheme.primary)),
                  ]
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // --- ACTIONS ---
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                label: "Cancel",
                variant: ButtonVariant.outline,
                onPressed: _isUploading ? null : () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              Button(
                label: "Upload File",
                variant: ButtonVariant.filled,
                icon: Icons.cloud_upload,
                isLoading: _isUploading,
                // Disable button if no file is selected OR if it's currently uploading
                onPressed: (_selectedFile == null || _isUploading) ? null : _handleUpload,
              ),
            ],
          ),
        ],
      ),
    );
  }
}