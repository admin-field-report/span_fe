import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../widgets/button/button.dart';
import '../../../services/toast_service.dart';
import '../../auth/controllers/auth_controller.dart';

class CreateInspectionPanel extends StatefulWidget {
  final String projectId;

  const CreateInspectionPanel({super.key, required this.projectId});

  @override
  State<CreateInspectionPanel> createState() => _CreateInspectionPanelState();
}

class _CreateInspectionPanelState extends State<CreateInspectionPanel> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  List<dynamic> _documents = [];
  List<dynamic> _inspections = [];
  bool _isCreating = false;

  // 🚀 REPLACED TIMER WITH A ROBUST BOOLEAN FLAG
  bool _isPolling = false;

  // 🚀 COMPUTED CHECK FOR PROCESSING
  bool get _isAnyDocumentProcessing {
    return _documents.any((doc) => 
      doc['status']?.toString().toLowerCase().trim() == 'processing'
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _fetchData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isPolling = false; // Instantly kill the loop when the modal closes
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndStartPolling();
    } else {
      _isPolling = false; // Pause loop if app goes to background
    }
  }

  // ==========================================
  // 🌟 BULLETPROOF ASYNC POLLING LOGIC
  // ==========================================
  
  void _checkAndStartPolling() {
    if (!mounted) return;
    
    if (_isAnyDocumentProcessing) {
      if (!_isPolling) {
        _startPollingLoop();
      }
    } else {
      _isPolling = false; // Instantly kill loop once all are completed
    }
  }

  // 🚀 THE FIX: A dedicated async loop instead of a Timer
  Future<void> _startPollingLoop() async {
    _isPolling = true;
    
    while (_isPolling && mounted) {
      // Wait 10 seconds before making the next call
      await Future.delayed(const Duration(seconds: 10));
      
      // Double check if we should still be polling after the delay
      if (!_isPolling || !mounted) break;
      
      await _fetchData(isPolling: true);
    }
  }

  // ==========================================
  // NORMAL DATA LOGIC
  // ==========================================

  Future<void> _fetchData({bool isPolling = false}) async {
    if (!isPolling) {
      setState(() => _isLoading = true);
    }
    
    try {
      final responses = await Future.wait([
        _apiService.get('/projectDocument/project/${widget.projectId}'),
        _apiService.get('/inspection/project/${widget.projectId}'),
      ]);

      if (!mounted) return;

      final docData = jsonDecode(responses[0].body);
      final inspData = jsonDecode(responses[1].body);

      List<dynamic> fetchedDocuments = docData['success'] == true ? (docData['data'] ?? []) : [];
      List<dynamic> fetchedInspections = inspData['success'] == true ? (inspData['data'] ?? []) : [];

      fetchedInspections.sort((a, b) {
        final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      fetchedDocuments.sort((a, b) {
        final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _documents = fetchedDocuments; 
        _inspections = fetchedInspections;
        if (!isPolling) _isLoading = false;
      });

      // 🚀 Automatically evaluate if we need to start or stop the timer based on the new data
      _checkAndStartPolling();

    } catch (e) {
      if (mounted && !isPolling) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNewInspection() async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final payload = {
        "project_id": widget.projectId,
        "name": authController.user != null ? "${authController.user!.firstName} ${authController.user!.lastName}" : "",
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

  Future<void> _createFromExistingInspection(String sourceInspectionId, String sourceName) async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final payload = {
        "name": "$sourceName (Copy)", 
        "project_id": widget.projectId,
        "inspection_id": sourceInspectionId,
      };

      final response = await _apiService.post('/inspection/create-from-inspection-id', payload);
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['success'] == true && responseData['data'] != null) {
          
          final newInspectionId = responseData['data']['id'];
          
          Navigator.pop(context);
          
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

  // ==========================================
  // 🌟 STATUS BADGE UI 
  // ==========================================
  Widget _buildStatusBadge(String? statusStr, ThemeData theme) {
    final status = (statusStr ?? 'unknown').toLowerCase().trim();
    Color bgColor;
    Color textColor;
    String label = statusStr ?? 'Unknown';

    switch (status) {
      case 'processing':
        bgColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue[800]!;
        label = 'Processing';
        break;
      case 'completed':
        bgColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green[800]!;
        label = 'Completed';
        break;
      case 'failed':
        bgColor = Colors.red.withOpacity(0.1);
        textColor = Colors.red[800]!;
        label = 'Failed';
        break;
      default:
        bgColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'processing') ...[
            SizedBox(
              width: 8, 
              height: 8, 
              child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isCreating,
      child: AbsorbPointer(
        absorbing: _isCreating,
        child: Stack(
          children: [
            
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
                              
                              // 1. DOCUMENTS SECTION
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Documents", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  
                                  Button(
                                    label: "Create Blank Inspection",
                                    variant: ButtonVariant.filled,
                                    icon: Icons.add,
                                    // 🚀 Disable if ANY document is processing OR if the list is empty
                                    onPressed: (_documents.isEmpty || _isAnyDocumentProcessing) 
                                        ? null 
                                        : () => _createNewInspection(),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // 🚀 WARNING BANNER (Shows if any document is processing)
                              if (_isAnyDocumentProcessing)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 16, 
                                        height: 16, 
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber[800])
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          "Some documents are currently processing. You can create a new inspection once all processing is complete.", 
                                          style: TextStyle(color: Colors.amber[900], fontSize: 13, fontWeight: FontWeight.w500)
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              if (_documents.isEmpty)
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
                                ..._documents.map((doc) => _buildDocumentCard(doc, colorScheme, theme)),

                              const SizedBox(height: 32),

                              // 2. EXISTING INSPECTIONS SECTION
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

            if (_isCreating)
              Positioned.fill(
                child: Container(
                  color: colorScheme.surfaceContainer.withOpacity(0.6), 
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
                        mainAxisSize: MainAxisSize.min,
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

  Widget _buildDocumentCard(dynamic doc, ColorScheme colorScheme, ThemeData theme) {
    final date = DateTime.tryParse(doc['create_time'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMM yyyy').format(date) : 'Unknown Date';
    final name = doc['document_name'] ?? doc['document_url']?.split('/').last ?? 'Unnamed Document';
    final status = doc['status']; 

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
        subtitle: Text("Created: $dateStr", style: const TextStyle(fontSize: 12)),
        trailing: _buildStatusBadge(status, theme), 
      ),
    );
  }

  Widget _buildInspectionCard(dynamic insp, ColorScheme colorScheme) {
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
        title: Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text("Created By: $name", style: const TextStyle(fontSize: 12)),
        
        trailing: Button(
          label: "Create",
          variant: ButtonVariant.outline,
          onPressed: () => _createFromExistingInspection(inspectionId, name),
        ),
      ),
    );
  }
}