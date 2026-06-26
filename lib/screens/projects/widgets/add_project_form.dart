import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../widgets/button/button.dart';
import '../../../widgets/form_components/form_controls.dart';
import '../../templates/controllers/template_controller.dart';
import '../controllers/project_controller.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../models/project.dart'; 

class SelectableWrapper<T> implements SelectableItem<T> {
  @override
  final T id;
  @override
  final String name;

  SelectableWrapper({required this.id, required this.name});
}

class AddProjectForm extends StatefulWidget {
  final bool isDesktop;
  final Project? project; 

  const AddProjectForm({
    super.key, 
    this.isDesktop = false, 
    this.project,
  });

  @override
  State<AddProjectForm> createState() => _AddProjectFormState();
}

class _AddProjectFormState extends State<AddProjectForm> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _clientNameController = TextEditingController(); 
  final _descController = TextEditingController();
  
  String? _selectedTemplateId;
  bool _isProcessing = false;

  bool get isEditing => widget.project != null;

  @override
  void initState() {
    super.initState();
    
    // 🚀 ALWAYS load templates so the disabled dropdown can display the template's real name
    templateController.getAllTemplates();

    if (isEditing) {
      _nameController.text = widget.project!.name;
      _descController.text = widget.project!.description;
      _clientNameController.text = (widget.project as dynamic).clientName ?? '';
      
      // Safely attempt to pre-fill the template ID if your model includes it
      try {
        _selectedTemplateId = (widget.project as dynamic).templateId;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientNameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> submitProject(BuildContext context) async {
    setState(() => _isProcessing = true);

    try {
      if (isEditing) {
        // ==========================================
        // 🌟 EDIT MODE: PATCH API
        // ==========================================
        final response = await _apiService.patch('/project/updateProject/${widget.project!.id}', {
          "name": _nameController.text.trim(),
          "client_name": _clientNameController.text.trim(),
          "client_id": widget.project!.clientId,
          "description": _descController.text.trim(),
        });
        
        final Map<String, dynamic> responseData = jsonDecode(response.body); 

        if (responseData['success'] == true) {
          projectController.getAllProjects();
          if (mounted) Navigator.pop(context);
          
          ToastService.show(
            context,
            title: "Project Updated",
            message: "Your project has been updated successfully.",
            type: ToastType.success,
          );      
        } else {
          throw Exception(responseData['message'] ?? 'Failed to update project');
        }

      } else {
        // ==========================================
        // 🌟 CREATE MODE: POST API
        // ==========================================
        final response = await _apiService.post('/project/createProject', {
          "name": _nameController.text.trim(),
          "client_name": _clientNameController.text.trim(), 
          "description": _descController.text.trim(),
          "template_id": _selectedTemplateId,
        });
        
        final Map<String, dynamic> responseData = jsonDecode(response.body); 

        if (responseData['success'] == true) {
          final dynamic data = responseData['data'];
          final String newProjectId = data['id'] ?? "";

          // Bind Document
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
      }
    } catch (e) {
      debugPrint("Project Submit Error: $e");
      ToastService.show(
        context,
        title: "Error",
        message: isEditing ? "Failed to update project." : "Failed to create project.",
        type: ToastType.error,
      );    
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
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
          mainAxisSize: MainAxisSize.min, 
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
                // 🚀 WRAPPED IN ABSORB POINTER & OPACITY TO VISUALLY/PHYSICALLY DISABLE IT
                return AbsorbPointer(
                  absorbing: isEditing,
                  child: Opacity(
                    opacity: isEditing ? 0.6 : 1.0,
                    child: FormControlSelect<String>(
                      value: _selectedTemplateId,
                      isLoading: templateController.isLoading,
                      items: templateController.templates.map((t) => 
                        SelectableWrapper(id: t.id, name: t.name)
                      ).toList(),
                      hintText: "Select Template",
                      emptyText: "No templates found",
                      onChanged: (val) {
                        setState(() => _selectedTemplateId = val);
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            _buildLabel("Client Name", theme),
            FormControlTextField(
              controller: _clientNameController,
              hintText: "Enter client name...",
              prefixIcon: Icons.business_rounded, 
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null, // 🚀 MADE MANDATORY
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
        Text(isEditing ? "Edit Project" : "New Project", 
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          )),
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
    final String btnText = isEditing ? "Save Changes" : "Create Project";

    if (widget.isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end, 
        children: [
          SizedBox(
            width: 120,
            child: Button(
              label: "Close",
              variant: ButtonVariant.outline,
              onPressed: _isProcessing ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: Button(
              label: btnText,
              isLoading: _isProcessing,
              onPressed: () {
                if (_formKey.currentState!.validate()) submitProject(context);
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
            onPressed: _isProcessing ? null : () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Button(
            label: btnText,
            isLoading: _isProcessing,
            onPressed: () {
              if (_formKey.currentState!.validate()) submitProject(context);
            },
          ),
        ),
      ],
    );
  }
}