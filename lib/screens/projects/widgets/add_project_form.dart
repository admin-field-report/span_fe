import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../widgets/button/button.dart';
import '../../../widgets/form_components/form_controls.dart';
import '../../templates/controllers/template_controller.dart';
import '../controllers/project_controller.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';

class SelectableWrapper<T> implements SelectableItem<T> {
  @override
  final T id;
  @override
  final String name;

  SelectableWrapper({required this.id, required this.name});
}

class AddProjectForm extends StatefulWidget {
  final bool isDesktop;
  const AddProjectForm({super.key, this.isDesktop = false});

  @override
  State<AddProjectForm> createState() => _AddProjectFormState();
}

class _AddProjectFormState extends State<AddProjectForm> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedTemplateId;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    templateController.getAllTemplates();
  }

  Future<void> createProject(BuildContext context) async {
    setState(() => _isCreating = true);

    try {
      // 1. Call the first API to create the project
      final response = await _apiService.post('/project/createProject', {
        "name": _nameController.text.trim(),
        "description": _descController.text.trim(),
        "template_id": _selectedTemplateId,
      });
      
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        
        // 🚀 EXTRACT THE NEW PROJECT ID
        final dynamic data = responseData['data'];
        final String newProjectId = data['id']?? "";

        // 2. Call the second API to bind the project document
        if (newProjectId.isNotEmpty && _selectedTemplateId != null) {
          final docResponse = await _apiService.post('/projectDocument', {
            "name": _nameController.text.trim(),
            "project_id": newProjectId,
            "template_id": _selectedTemplateId,
          });
          
          final Map<String, dynamic> docResponseData = jsonDecode(docResponse.body);
          
          if (docResponseData['success'] != true) {
            debugPrint("Warning: Project created, but document binding failed.");
          }
        }

        projectController.getAllProjects();
        if (mounted) Navigator.pop(context);
        
        ToastService.show(
          context,
          title: "Project Created",
          message: "Your project has been created and bound successfully.",
          type: ToastType.success,
        );      
      } else {
        throw Exception(responseData['message'] ?? 'Failed to create project');
      }
    } catch (e) {
      debugPrint("Create Project Error: $e");
      ToastService.show(
        context,
        title: "Error",
        message: "Failed to create project.",
        type: ToastType.error,
      );    
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(maxWidth: widget.isDesktop ? 600 : double.infinity),
      padding: EdgeInsets.only(
          left: 24, 
          right: 24, 
          top: 24,
          // Add extra padding at the bottom for mobile safe area
          bottom: widget.isDesktop ? 24 : MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: widget.isDesktop 
              ? BorderRadius.circular(24)
              : const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Constrains height to content
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, colorScheme),
            const SizedBox(height: 32),

            _buildLabel("Project Name", theme),
            FormControlTextField(
              controller: _nameController,
              hintText: "Enter name...",
              prefixIcon: Icons.edit_note_rounded,
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
            const SizedBox(height: 20),

            _buildLabel("Select Template", theme),
            ListenableBuilder(
              listenable: templateController,
              builder: (context, _) {
                return FormControlSelect<String>(
                  value: _selectedTemplateId,
                  isLoading: templateController.isLoading,
                  items: templateController.templates.map((t) => 
                    SelectableWrapper(id: t.id, name: t.name)
                  ).toList(),
                  hintText: "Select Template",
                  emptyText: "No templates found for this user",
                  onChanged: (val) {
                    setState(() => _selectedTemplateId = val);
                  },
                  // validator: (val) => val == null ? "Required" : null,
                );
              },
            ),
            const SizedBox(height: 20),

            _buildLabel("Description", theme),
            SizedBox(
              height: 120,
              child: FormControlTextArea(
                controller: _descController,
                hintText: "What is this project about?",
                prefixIcon: Icons.description_outlined,
              ),
            ),
            
            const SizedBox(height: 40),
            _buildActions(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("New Project", 
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          )),
        // Close icon always available in top right for clarity
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.onSurface.withOpacity(0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(text.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: theme.colorScheme.onSurface.withOpacity(0.5),
      )),
    );
  }

  Widget _buildActions(ColorScheme colorScheme) {
    // Desktop: Bottom Right placement
    if (widget.isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end, // Aligns to right
        children: [
          SizedBox(
            width: 120,
            child: Button(
              label: "Close",
              variant: ButtonVariant.outline,
              onPressed: _isCreating ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: Button(
              label: "Create Project",
              isLoading: _isCreating,
              onPressed: () {
                if (_formKey.currentState!.validate()) createProject(context);
              },
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Button(
            label: "Close",
            variant: ButtonVariant.outline,
            onPressed: _isCreating ? null : () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Button(
            label: "Create Project",
            isLoading: _isCreating,
            onPressed: () {
              if (_formKey.currentState!.validate()) createProject(context);
            },
          ),
        ),
      ],
    );
  }
}