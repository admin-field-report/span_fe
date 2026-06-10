import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import 'report_skill_preview_screen.dart';

class CreateReportScreen extends StatefulWidget {
  final String projectId;

  const CreateReportScreen({super.key, required this.projectId});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final ApiService _apiService = ApiService();
  
  int _currentStep = 0;
  bool _isProcessing = false; 
  String _loadingMessage = "";

  // Step 1: Inspections
  bool _isLoadingInspections = true;
  List<dynamic> _inspections = [];
  final List<String> _selectedInspectionIds = []; 

  // 🚀 Step 2: Report Templates (Replaced Documents)
  bool _isLoadingTemplates = true;
  List<dynamic> _reportTemplates = [];
  dynamic _selectedReportTemplate; // Single selection

  // Step 3: Clarification Questions
  List<dynamic> _clarificationQuestions = [];
  final Map<int, TextEditingController> _questionAnswers = {};

  @override
  void initState() {
    super.initState();
    _fetchInspections();
    _fetchReportTemplates();
  }

  @override
  void dispose() {
    for (var controller in _questionAnswers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // --- STEP 1 LOGIC ---
  Future<void> _fetchInspections() async {
    try {
      final response = await _apiService.get('/inspection/project/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (responseData['success'] == true) {
        List<dynamic> fetched = responseData['data'] ?? [];
        fetched.sort((a, b) {
          final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA); 
        });

        setState(() {
          _inspections = fetched;
          _isLoadingInspections = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingInspections = false);
    }
  }

 Future<void> _fetchReportTemplates() async {
    try {
      final response = await _apiService.get('/reportTemplate/getByCompanyId');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (responseData['success'] == true || responseData['data'] != null) {
        List<dynamic> fetched = responseData['data'] ?? [];
        
        // Sort newest first
        fetched.sort((a, b) {
          final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA); 
        });

        setState(() {
          _reportTemplates = fetched;
          _isLoadingTemplates = false;
        });
      }
    } catch (e) {
      debugPrint("🚨 Error fetching report templates: $e");
      if (mounted) setState(() => _isLoadingTemplates = false);
    }
  }

  // 🚀 THE HEAVY LIFTING: Merge Existing + Upload New -> Register Template -> Trigger AI
  Future<void> _processDocumentsAndAnalyze() async {
    setState(() {
      _isProcessing = true;
      _loadingMessage = "Generating Skill & Questions...";
    });

    try {
      // 1. TRIGGER SKILL GENERATION
      final genRes = await _apiService.post('/reportTemplate/${_selectedReportTemplate['id']}/generate-skill', {});
      final genData = jsonDecode(genRes.body);

      final String statusEndpoint = genData['data']['status_endpoint'].toString().replaceFirst('/v1', '');

      // 2. POLL UNTIL SKILL IS GENERATED
      bool isComplete = false;
      while (!isComplete) {
        await Future.delayed(const Duration(seconds: 3));
        final pollRes = await _apiService.get(statusEndpoint);
        final pollData = jsonDecode(pollRes.body);
        if (pollData['status'] == 'completed') isComplete = true;
      }

      // 3. GET CLARIFICATION QUESTIONS
      setState(() => _loadingMessage = "Fetching questions...");
      final qRes = await _apiService.get('/reportTemplate/${_selectedReportTemplate['id']}/clarification-questions');
      final qData = jsonDecode(qRes.body);

      setState(() {
        _clarificationQuestions = qData['data']['clarification_questions'] ?? []; // Adjust key based on API
        _questionAnswers.clear();
        for (int i = 0; i < _clarificationQuestions.length; i++) {
          _questionAnswers[i] = TextEditingController();
        }
        _currentStep = 2; // Move to the Questions Step
      });
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Error: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- STEPPER CONTROLS ---
  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_selectedInspectionIds.isEmpty) {
        ToastService.show(context, message: "Please select at least one inspection.", type: ToastType.error);
        return;
      }
      setState(() => _currentStep += 1);
    } 
    else if (_currentStep == 1) {
      // 🚀 Validate single template selection
      if (_selectedReportTemplate == null) {
        ToastService.show(context, message: "Please select a Report Template.", type: ToastType.error);
        return;
      }
      _processDocumentsAndAnalyze();
    }
    else if (_currentStep == 2) {
      _submitFinalReport();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    } else {
      Navigator.pop(context);
    }
  }

  // 🚀 FINAL STEP: Submit Answers and Finalize Skill
  Future<void> _submitFinalReport() async {
    setState(() {
      _isProcessing = true;
      _loadingMessage = "Finalizing Report Formatting...";
    });
    
    try {
      // 1. APPLY CLARIFICATIONS

      final Map<String, String> answersPayload = {};
      
      for (int i = 0; i < _clarificationQuestions.length; i++) {
        final qText = _clarificationQuestions[i]['question'];
        final aText = _questionAnswers[i]?.text.trim() ?? "";
        
        if (aText.isNotEmpty) {
          answersPayload[qText] = aText;
        }
      }

      if (answersPayload.isEmpty) {

        final templateDetails = await _apiService.get('/reportTemplate/getById/${_selectedReportTemplate['id']}');
        final templateData = jsonDecode(templateDetails.body);

        final bool? didCreateReport = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ReportSkillPreviewScreen(
              projectId: widget.projectId,
              reportTemplateId: _selectedReportTemplate['id'],
              initialContent: templateData['data']['skill_content'] ?? "",
              inspectionIds: [..._selectedInspectionIds],
            ),
          ),
        );

        if (!context.mounted) return;
        if (didCreateReport == true) {
          Navigator.pop(context, true);
        }
      } else {
        // Proceed with the payload (it might be an empty map {}, which is perfectly fine)
        final finalizeRes = await _apiService.post(
          '/reportTemplate/${_selectedReportTemplate['id']}/apply-clarifications',
          {'clarification_answers': answersPayload}
        );
        
        final finalizeData = jsonDecode(finalizeRes.body);

        final String rawEndpoint = finalizeData['status_endpoint'];
        final String statusEndpoint = rawEndpoint.startsWith('/v1') 
            ? rawEndpoint.replaceFirst('/v1', '') 
            : rawEndpoint;

        bool isComplete = false;
        int attempts = 0;
        final int maxAttempts = 30;

        while (!isComplete && attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 3));
          attempts++;

          final pollRes = await _apiService.get(statusEndpoint);
          final pollData = jsonDecode(pollRes.body);

          if (pollData['status'] == 'completed') {
            isComplete = true;
            
            if (!mounted) return;
            
            final skillContent = pollData['result']['skill_content'];
            // final skillId = pollData['result']['skill']['id'];

            ToastService.show(context, message: "Skill generated successfully!", type: ToastType.success);
            
            final bool? didCreateReport = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => ReportSkillPreviewScreen(
                  projectId: widget.projectId,
                  // skillId: 'skillId',
                  reportTemplateId: _selectedReportTemplate['id'],
                  initialContent: skillContent,
                  inspectionIds: [..._selectedInspectionIds],
                ),
              ),
            );
            if (!context.mounted) return;
            if (didCreateReport == true) {
              Navigator.pop(context, true);
            }
            
          } else if (pollData['status'] == 'failed' || pollData['status'] == 'error') {
            throw Exception("Finalization failed on server.");
          }
        }

        if (!isComplete) throw Exception("Finalization timed out.");
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Error: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        title: const Text("Create Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: colorScheme.surface,
        centerTitle: false,
      ),
      body: PopScope(
        canPop: !_isProcessing,
        child: AbsorbPointer(
          absorbing: _isProcessing,
          child: Stack(
            children: [
              Stepper(
                type: StepperType.vertical, 
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                
                controlsBuilder: (BuildContext context, ControlsDetails details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: Row(
                      children: [
                        Button(
                          label: _currentStep == 2 ? "Finalize Report" : (_currentStep == 1 ? "Analyze Documents" : "Continue"),
                          variant: ButtonVariant.filled,
                          onPressed: details.onStepContinue,
                        ),
                        const SizedBox(width: 12),
                        Button(
                          label: _currentStep == 0 ? "Cancel" : "Back",
                          variant: ButtonVariant.outline,
                          onPressed: details.onStepCancel,
                        ),
                      ],
                    ),
                  );
                },

                steps: [
                  // ==========================================
                  // STEP 1: SELECT INSPECTIONS
                  // ==========================================
                  Step(
                    title: const Text("Select Inspections", style: TextStyle(fontWeight: FontWeight.bold)),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                    content: _isLoadingInspections 
                      ? const Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator())
                      : _inspections.isEmpty
                        ? const Text("No inspections available for this project.")
                        : SizedBox(
                            height: 350,
                            child: ListView.builder(
                              itemCount: _inspections.length,
                              itemBuilder: (context, index) {
                                final insp = _inspections[index];
                                final id = insp['id'];
                                final isSelected = _selectedInspectionIds.contains(id);

                                final dateStr = insp['create_time'];
                                final date = dateStr != null 
                                  ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(dateStr)) 
                                  : "Unknown Date";

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant, 
                                      width: isSelected ? 2 : 1
                                    ),
                                    borderRadius: BorderRadius.circular(8)
                                  ),
                                  child: CheckboxListTile(
                                    value: isSelected,
                                    activeColor: colorScheme.primary,
                                    onChanged: (val) => setState(() { 
                                      val == true ? _selectedInspectionIds.add(id) : _selectedInspectionIds.remove(id); 
                                    }),
                                    title: Text(date, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Created By: ${insp['name'] ?? 'Unknown'}",
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)
                                          ),
                                        ],
                                      ),
                                    ),
                                    controlAffinity: ListTileControlAffinity.leading, 
                                  ),
                                );
                              },
                            ),
                          ),
                  ),

                  // ==========================================
                  // 🚀 NEW STEP 2: SELECT REPORT TEMPLATE
                  // ==========================================
                  Step(
                    title: const Text("Select Report Template", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Choose the master template to build this report against"),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    content: _isLoadingTemplates 
                      ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                      : _reportTemplates.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text("No report templates found.", style: TextStyle(color: Colors.grey)),
                          )
                        : Container(
                            height: 300, // Fixed height making it scrollable
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              border: Border.all(color: colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(8)
                            ),
                            child: ListView.separated(
                              itemCount: _reportTemplates.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final template = _reportTemplates[index];
                                final bool hasDocuments = template['documents'] == true;

                                return RadioListTile<dynamic>(
                                  value: template,
                                  groupValue: _selectedReportTemplate,
                                  activeColor: colorScheme.primary,
                                  title: Text(
                                    template['name'] ?? "Unnamed Template", 
                                    maxLines: 1, 
                                    overflow: TextOverflow.ellipsis, 
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600, 
                                      fontSize: 14,
                                      // Optional: Dim the title text slightly if it's disabled
                                      color: hasDocuments ? colorScheme.onSurface : colorScheme.onSurface.withOpacity(0.5),
                                    )
                                  ),
                                  subtitle: hasDocuments
                                      ? null
                                      : Text(
                                          "No documents available for this template",
                                          style: TextStyle(fontSize: 12, color: colorScheme.error.withOpacity(0.8)), 
                                        ),
                                  // Setting onChanged to null automatically disables the entire tile
                                  onChanged: hasDocuments 
                                      ? (val) {
                                          setState(() {
                                            _selectedReportTemplate = val;
                                          });
                                        }
                                      : null, 
                                );
                              },
                            ),
                          ),
                  ),

                  // ==========================================
                  // STEP 3: CLARIFICATION QUESTIONS
                  // ==========================================
                  Step(
                    title: const Text("Clarification Questions", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Answer these to refine the report structure (Optional)"), 
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                    content: _clarificationQuestions.isEmpty 
                      ? const Text("No questions generated.")
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(_clarificationQuestions.length, (index) {
                            final qData = _clarificationQuestions[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                border: Border.all(color: colorScheme.outlineVariant),
                                borderRadius: BorderRadius.circular(12)
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: colorScheme.primaryContainer,
                                        child: Text("${index + 1}", style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          qData['question'] ?? "",
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _questionAnswers[index],
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      hintText: "Enter your answer here (Optional)...",
                                      filled: true,
                                      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  )
                                ],
                              ),
                            );
                          }),
                        ),
                  ),
                ],
              ),

              if (_isProcessing)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0), 
                    child: Container(
                      color: colorScheme.scrim.withOpacity(0.3), 
                      child: Center(
                        child: Container(
                          width: 320, 
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(28), 
                            border: Border.all(
                              color: colorScheme.outlineVariant.withOpacity(0.5),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.15),
                                blurRadius: 40,
                                spreadRadius: -5,
                                offset: const Offset(0, 10),
                              )
                            ]
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 5,
                                      strokeCap: StrokeCap.round, 
                                      color: colorScheme.primary,
                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                  Icon(
                                    Icons.auto_awesome, 
                                    color: colorScheme.primary,
                                    size: 32,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              Text(
                                _loadingMessage, 
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700, 
                                  color: colorScheme.onSurface,
                                  letterSpacing: 0.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Please do not close the app.", 
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}