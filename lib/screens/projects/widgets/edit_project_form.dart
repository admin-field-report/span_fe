import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../widgets/button/button.dart';
import '../../../widgets/form_components/form_controls.dart';
import '../controllers/project_controller.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../utils/app_responsive.dart';

class EditProjectForm extends StatefulWidget {
  final String projectId;

  const EditProjectForm({
    super.key,
    required this.projectId,
  });

  @override
  State<EditProjectForm> createState() => _EditProjectFormState();
}

class _EditProjectFormState extends State<EditProjectForm> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientNameController = TextEditingController();
  
  bool _isFetching = true; 
  bool _isUpdating = false;
  
  String? _clientId; 

  @override
  void initState() {
    super.initState();
    _fetchProjectDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchProjectDetails() async {
    try {
      final response = await _apiService.get('/project/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final data = responseData['data'];
        
        if (mounted) {
          setState(() {
            _nameController.text = data['name'] ?? "";
            
            if (data['client'] != null && data['client']['name'] != null) {
              _clientNameController.text = data['client']['name'];
            } else {
              _clientNameController.text = "";
            }
            
            _clientId = data['client_id']; 
            _isFetching = false;
          });
        }
      } else {
        throw Exception("Failed to load project details");
      }
    } catch (e) {
      debugPrint("Fetch Project Error: $e");
      if (mounted) {
        setState(() => _isFetching = false);
        ToastService.show(context, title: "Error", message: "Could not load project details.", type: ToastType.error);
      }
    }
  }

  Future<void> updateProject(BuildContext context) async {
    setState(() => _isUpdating = true);

    try {
      String? currentClientId = _clientId;
      final String inputClientName = _clientNameController.text.trim();
      final String inputProjectName = _nameController.text.trim();

      if (currentClientId == null && inputClientName.isNotEmpty) {
        final clientResponse = await _apiService.post('/client/createClient', {
          "name": inputClientName
        });
        final clientData = jsonDecode(clientResponse.body);
        
        if (clientData['data'] != null && clientData['data']['id'] != null) {
          currentClientId = clientData['data']['id'];
        } else {
          throw Exception("Failed to create client");
        }
      } 
      else if (currentClientId != null) {
        await _apiService.patch('/client/updateClient/$currentClientId', {
          "name": inputClientName
        });
      }

      final projectUpdateResponse = await _apiService.patch('/project/updateClientToProject/${widget.projectId}', {
        "client_id": currentClientId,
        "name": inputProjectName
      });

      final projectUpdateData = jsonDecode(projectUpdateResponse.body);
      
      if (projectUpdateData['message'] == "Client added to project successfully" || projectUpdateData['data'] != null) {
        projectController.getAllProjects(); 
        if (mounted) Navigator.pop(context, true); 
        
        ToastService.show(
          context,
          title: "Project Updated",
          message: "Project details have been updated successfully.",
          type: ToastType.success,
        );
      } else {
        throw Exception("Failed to update project");
      }
      
    } catch (e) {
      debugPrint("Update Project Error: $e");
      ToastService.show(context, title: "Error", message: "Failed to update project.", type: ToastType.error);    
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final bool isDesktop = AppResponsive.isDesktopScreen(context);

    return Container(
      constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: isDesktop ? 24 : MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: isDesktop 
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _isFetching 
        ? const SizedBox(
            height: 200, 
            child: Center(child: CircularProgressIndicator())
          )
        : Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme, colorScheme),
                const SizedBox(height: 32),

                // 🚀 NEW: Disables inputs and dims them while updating!
                IgnorePointer(
                  ignoring: _isUpdating,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isUpdating ? 0.6 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel("Project Name", theme),
                        FormControlTextField(
                          controller: _nameController,
                          hintText: "Enter project name...",
                          prefixIcon: Icons.business_center_outlined,
                          validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
                        ),
                        const SizedBox(height: 20),

                        _buildLabel("Client Name", theme),
                        FormControlTextField(
                          controller: _clientNameController,
                          hintText: "Enter client name",
                          prefixIcon: Icons.person_outline,
                          validator: (v) {
                            if (_clientId != null && (v == null || v.trim().isEmpty)) {
                              return "Client name is required for this project.";
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                _buildActions(colorScheme, isDesktop),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 🚀 NEW: Dynamic Title with Loading Indicator
        Row(
          children: [
            Text(
              "Edit Project", 
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.8,
              )
            ),
            if (_isUpdating) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 16, 
                height: 16, 
                child: CircularProgressIndicator(
                  strokeWidth: 2.5, 
                  color: colorScheme.primary,
                )
              ),
            ]
          ],
        ),
        IconButton(
          onPressed: _isUpdating ? null : () => Navigator.pop(context),
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

  Widget _buildActions(ColorScheme colorScheme, bool isDesktop) {
    if (isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 120,
            child: Button(
              label: "Cancel",
              variant: ButtonVariant.outline,
              onPressed: _isUpdating ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: Button(
              label: "Save Changes",
              isLoading: _isUpdating,
              onPressed: () {
                if (_formKey.currentState!.validate()) updateProject(context);
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
            label: "Cancel",
            variant: ButtonVariant.outline,
            onPressed: _isUpdating ? null : () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Button(
            label: "Save Changes",
            isLoading: _isUpdating,
            onPressed: () {
              if (_formKey.currentState!.validate()) updateProject(context);
            },
          ),
        ),
      ],
    );
  }
}