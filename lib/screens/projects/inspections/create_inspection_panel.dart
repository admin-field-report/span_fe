import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../widgets/button/button.dart';
import '../../../services/toast_service.dart';

class CreateInspectionPanel extends StatefulWidget {
  final String projectId;

  const CreateInspectionPanel({super.key, required this.projectId});

  @override
  State<CreateInspectionPanel> createState() => _CreateInspectionPanelState();
}

class _CreateInspectionPanelState extends State<CreateInspectionPanel> {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  List<dynamic> _documents = [];
  List<dynamic> _inspections = [];
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    
    try {
      final responses = await Future.wait([
        _apiService.get('/projectDocument/project/${widget.projectId}'),
        _apiService.get('/inspection/project/${widget.projectId}'),
      ]);

      if (!mounted) return;

      final docData = jsonDecode(responses[0].body);
      final inspData = jsonDecode(responses[1].body);

      // 1. Extract both lists
      List<dynamic> fetchedDocuments = docData['success'] == true ? (docData['data'] ?? []) : [];
      List<dynamic> fetchedInspections = inspData['success'] == true ? (inspData['data'] ?? []) : [];

      // 2. Sort Inspections (Latest first)
      fetchedInspections.sort((a, b) {
        final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        
        return dateB.compareTo(dateA);
      });

      // 🚀 3. NEW: Sort Documents (Latest first)
      fetchedDocuments.sort((a, b) {
        // IMPORTANT: Ensure 'create_time' matches the exact key returned by your document API!
        // If your API uses 'createdAt' or 'createDate' instead, change it here.
        final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        
        return dateB.compareTo(dateA);
      });

      setState(() {
        _documents = fetchedDocuments; // 🚀 Assign the newly sorted list
        _inspections = fetchedInspections;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewInspection() async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final payload = {
        "project_id": widget.projectId
      };

      final response = await _apiService.post('/inspection/create', payload);
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['success'] == true && responseData['data'] != null) {
          
          final String newInspectionId = responseData['data']['id'];
          
          Navigator.pop(context, newInspectionId); 
          
        } else {
          ToastService.show(context, message: "Failed to parse inspection data.", type: ToastType.error);
        }
      } else {
        ToastService.show(context, message: responseData['message'] ?? "Failed to create inspection", type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Network error occurred.", type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  // 🚀 CREATE FROM EXISTING INSPECTION
  Future<void> _createFromExistingInspection(String sourceInspectionId, String sourceName) async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final payload = {
        "name": "$sourceName (Copy)", // You can customize this default name!
        "project_id": widget.projectId,
        "inspection_id": sourceInspectionId,
      };

      final response = await _apiService.post('/inspection/create-from-inspection-id', payload);
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['success'] == true && responseData['data'] != null) {
          
          final newInspectionId = responseData['data']['id'];
          
          // 1. Close the popup
          Navigator.pop(context);
          
          // 2. Redirect straight to the newly duplicated inspection!
          final exactUrl = '/projects/details/${widget.projectId}/inspections/$newInspectionId';
          context.go(exactUrl);
          
        } else {
          ToastService.show(context, message: "Failed to parse inspection data.", type: ToastType.error);
        }
      } else {
        ToastService.show(context, message: responseData['message'] ?? "Failed to duplicate inspection", type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Network error occurred.", type: ToastType.error);
      }
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

    // 1. Screen Disable (Blocks back button/swipes)
    return PopScope(
      canPop: !_isCreating,
      // 2. Blocks all physical taps on the screen
      child: AbsorbPointer(
        absorbing: _isCreating,
        child: Stack(
          children: [
            
            // --- YOUR EXACT EXISTING UI ---
            Container(
              color: colorScheme.surfaceContainer,
              child: Column(
                children: [
                  // --- HEADER ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Create New Inspection", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- CONTENT ---
                  Expanded(
                    child: _isLoading 
                      ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              
                              // 1. DOCUMENTS SECTION (With Create Button in Header)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Documents", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  
                                  // "Create inspection option at Documents header"
                                  Button(
                                    label: "Create Blank Inspection",
                                    variant: ButtonVariant.filled,
                                    icon: Icons.add,
                                    onPressed: _documents.isEmpty ? null : () => _createNewInspection(),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              if (_documents.isEmpty)
                                // Text("No template documents available.", style: TextStyle(color: colorScheme.secondary))
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.description_outlined, 
                                      size: 48, 
                                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3)
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      "No template documents available.", 
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        color: theme.colorScheme.onSurfaceVariant
                                      )
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                      child: Text(
                                        "Please upload a document from Project Documents to create an inspection.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13, 
                                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                ..._documents.map((doc) => _buildDocumentCard(doc, colorScheme)),

                              const SizedBox(height: 32),

                              // 2. EXISTING INSPECTIONS SECTION (Create Button per row)
                              Text("Use Existing Inspection", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),

                              if (_inspections.isEmpty)
                                Text("No previous inspections found.", style: TextStyle(color: colorScheme.secondary))
                              else
                                ..._inspections.map((insp) => _buildInspectionCard(insp, colorScheme)),
                            ],
                          ),
                        ),
                  ),
                ],
              ),
            ),

            // 🚀 3. Middle-of-Screen Loader Overlay WITH MESSAGE
            if (_isCreating)
              Positioned.fill(
                child: Container(
                  color: colorScheme.surfaceContainer.withOpacity(0.6), // Blurs/dims the background slightly
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          )
                        ]
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // Keeps the box wrapped tightly around the content
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            "Creating Inspection...",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(dynamic doc, ColorScheme colorScheme) {
    final date = DateTime.tryParse(doc['create_time'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMM yyyy').format(date) : 'Unknown Date';
    final name = doc['document_name'] ?? doc['document_url']?.split('/').last ?? 'Unnamed Document';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        leading: Icon(Icons.description_outlined, color: colorScheme.primary),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("Created: $dateStr", style: TextStyle(fontSize: 12)),
        // Optional: If you also want them to create FROM a specific document, add a trailing button here!
      ),
    );
  }

  Widget _buildInspectionCard(dynamic insp, ColorScheme colorScheme) {
    // 1. Safely extract the date and name so we have something to pass to the API
    final dateStr = insp['create_time'];
    final formattedDate = dateStr != null 
        ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(dateStr)) 
        : "Unknown Date";
        
    final name = insp['name'] ?? "Inspection $formattedDate";
    final inspectionId = insp['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant), 
        borderRadius: BorderRadius.circular(8)
      ),
      child: ListTile(
        leading: Icon(Icons.history, color: colorScheme.primary),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("Created: $formattedDate", style: const TextStyle(fontSize: 12)),
        
        // 🚀 2. CALL THE NEW METHOD HERE
        trailing: Button(
          label: "Create",
          variant: ButtonVariant.outline,
          onPressed: () => _createFromExistingInspection(inspectionId, name),
        ),
      ),
    );
  }
}