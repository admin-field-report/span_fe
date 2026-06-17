import 'package:flutter/material.dart';
import '../../services/toast_service.dart';
import '../../models/template.dart';
import '../../widgets/button/button.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/form_components/text_field.dart';
import './template_details_screen.dart';
import './controllers/template_controller.dart';

class TemplateManagementScreen extends StatefulWidget {
  const TemplateManagementScreen({super.key});

  @override
  State<TemplateManagementScreen> createState() => _TemplateManagementScreenState();
}

class _TemplateManagementScreenState extends State<TemplateManagementScreen> {
  String _searchQuery = '';
  Template? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      templateController.getAllTemplates();
    });
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _handleTemplateSelected(Template template, bool isMobile) {
    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(template.name, style: TextStyle(fontSize: 16))),
            body: TemplateDetailPanel(template: template), // We will do this next!
          ),
        ),
      );
    } else {
      setState(() => _selectedTemplate = template);
    }
  }

  // 🚀 Updated Delete Flow
  void _confirmDelete(Template template) async {
    // Wait for the dialog to return a boolean
    final didDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent accidental closing while loading
      builder: (context) => DeleteTemplateDialog(template: template),
    );

    if (didDelete == true && mounted) {
      
      // 🚀 Clean up the UI
      if (_selectedTemplate?.id == template.id) {
        setState(() {
          _selectedTemplate = null; // Clear the right pane
        });
      }

      // Show a success toast!
      ToastService.show(
        context,
        title: "Template Deleted",
        message: "The template has been removed.",
        type: ToastType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      body: SafeArea(
        // 🚀 Listen to the global controller for state changes
        child: AnimatedBuilder(
          animation: templateController,
          builder: (context, child) {
            
            return LayoutBuilder(
              builder: (context, constraints) {
                bool isMobile = constraints.maxWidth < 800;

                if (isMobile) {
                  return _buildListPane(theme, isMobile);
                }

                return Row(
                  children: [
                    SizedBox(width: 380, child: _buildListPane(theme, isMobile)),
                    Container(width: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                    Expanded(
                      child: _selectedTemplate == null
                          ? _buildEmptyDetailState(theme)
                          : TemplateDetailPanel(template: _selectedTemplate!),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ==========================================
  // LEFT PANE: THE LIST
  // ==========================================
  Widget _buildListPane(ThemeData theme, bool isMobile) {
    // 🚀 Use data from the controller!
    final templates = templateController.templates;
    final isLoading = templateController.isLoading;
    final error = templateController.error;

    // Local Search Filtering
    final filteredTemplates = templates
        .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Templates", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(Icons.add_circle, color: theme.colorScheme.primary, size: 28),
                tooltip: "Create Template",
                onPressed: () async {
                  
                  // 🚀 1. Wait for the dialog to finish and see if it returns a Template
                  final newTemplate = await showDialog<Template>(
                    context: context,
                    barrierDismissible: false, 
                    builder: (context) => const CreateTemplateDialog(),
                  );

                  // 🚀 2. If a template was created, auto-select it!
                  if (newTemplate != null && mounted) {
                    // Check screen width to determine if we should push a route (Mobile) 
                    // or just update the right pane (Desktop)
                    bool isMobile = MediaQuery.of(context).size.width < 800;
                    
                    _handleTemplateSelected(newTemplate, isMobile);
                  }
                },
              )
            ],
          ),
        ),
        
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: SearchField(
            hintText: "Search templates...",
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

        // 🚀 Dynamic List Body (Loading / Error / Empty / List)
        Expanded(
          child: _buildListBody(theme, isMobile, isLoading, error, filteredTemplates),
        ),
      ],
    );
  }

  // Extracted list body logic to handle all your API states cleanly
  Widget _buildListBody(ThemeData theme, bool isMobile, bool isLoading, String? error, List<Template> filteredTemplates) {
    // 1. Loading State
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    }

    // 2. Error State
    if (error != null && filteredTemplates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text("Error: $error", style: TextStyle(color: Colors.red[400]), textAlign: TextAlign.center),
        ),
      );
    }

    // 3. Empty State
    if (filteredTemplates.isEmpty) {
      return Center(child: Text("No templates found.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)));
    }

    // 4. Success Data State
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filteredTemplates.length,
      itemBuilder: (context, index) {
        final template = filteredTemplates[index];
        final isSelected = !isMobile && _selectedTemplate?.id == template.id;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          child: ListTile(
            selected: isSelected,
            selectedTileColor: theme.colorScheme.primary.withOpacity(0.10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.only(left: 16, right: 8),
            
            title: Text(
              template.name, 
              style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              "Created: ${_formatDate(template.createDate)}", 
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            
            onTap: () => _handleTemplateSelected(template, isMobile),
            
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                  onPressed: () => _confirmDelete(template), 
                ),
                Icon(Icons.chevron_right, size: 20, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyDetailState(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text("Select a template to view details", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}


class CreateTemplateDialog extends StatefulWidget {
  const CreateTemplateDialog({super.key});

  @override
  State<CreateTemplateDialog> createState() => _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends State<CreateTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Clear API error as soon as the user starts typing to fix it
    _nameController.addListener(() {
      if (_errorMessage != null && mounted) {
        setState(() => _errorMessage = null);
        _formKey.currentState?.validate(); // Re-trigger validation to clear the red border
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // 🚀 Await the actual template object from the controller
    final newTemplate = await templateController.createTemplate(_nameController.text.trim());

    if (!mounted) return;

    if (newTemplate != null) {
      Navigator.pop(context, newTemplate); 
      ToastService.show(
        context,
        title: "Template Created",
        message: "Your template has been added successfully.",
        type: ToastType.success,
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = templateController.error; 
      });
      _formKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450), 
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // 🚀 HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("New Template", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text("Give your template a recognizable name to get started.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 32),

                FormControlTextField(
                  controller: _nameController,
                  labelText: "Template Name *",
                  hintText: "e.g., Weekly Safety Audit",
                  errorText: _errorMessage, 
                  variant: TextFieldVariant.filled,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter a name';
                    if (value.trim().length < 3) return 'Name must be at least 3 characters';
                    return null;
                  },
                ),
                
                const SizedBox(height: 32),

                // 🚀 ACTIONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(
                      label: "Cancel",
                      variant: ButtonVariant.outline,
                      onPressed: _isSubmitting ? () {} : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Button(
                      label: _isSubmitting ? "Creating..." : "Create",
                      variant: ButtonVariant.filled,
                      onPressed: _isSubmitting ? () {} : _submit,
                      isLoading: _isSubmitting,
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeleteTemplateDialog extends StatefulWidget {
  final Template template;

  const DeleteTemplateDialog({super.key, required this.template});

  @override
  State<DeleteTemplateDialog> createState() => _DeleteTemplateDialogState();
}

class _DeleteTemplateDialogState extends State<DeleteTemplateDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _delete() async {
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    // 🚀 Wait for the controller to finish the API call
    final success = await templateController.removeTemplate(widget.template.id);

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true); // Return true to signal success
    } else {
      setState(() {
        _isDeleting = false;
        _errorMessage = templateController.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // HEADER
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 28),
                  const SizedBox(width: 12),
                  Text("Delete Template", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              
              // WARNING TEXT
              Text(
                "Are you sure you want to delete '${widget.template.name}'? This action cannot be undone.",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15, height: 1.5),
              ),
              
              // ERROR MESSAGE (If API fails)
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: TextStyle(color: Colors.red[400], fontSize: 13)),
              ],
              
              const SizedBox(height: 32),

              // 🚀 ACTIONS USING YOUR CUSTOM BUTTON
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    label: "Cancel",
                    variant: ButtonVariant.outline,
                    onPressed: _isDeleting ? null : () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: _isDeleting ? "Deleting..." : "Delete",
                    variant: ButtonVariant.filled,
                    // You can optionally pass color: Colors.red[600] here if your Button component supports it!
                    isLoading: _isDeleting,
                    onPressed: _isDeleting ? null : _delete,
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}