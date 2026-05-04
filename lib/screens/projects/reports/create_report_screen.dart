import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

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

  // Step 2: NEW Local Files
  final List<PlatformFile> _selectedFiles = [];

  // Step 2: EXISTING Documents
  bool _isLoadingExistingDocs = true;
  List<dynamic> _existingDocuments = [];
  final List<dynamic> _selectedExistingDocs = []; 

  // Step 3: Clarification Questions
  List<dynamic> _clarificationQuestions = [];
  final Map<int, TextEditingController> _questionAnswers = {};
  String? _summarizeJobId;

  int get _totalSelectedDocuments => _selectedFiles.length + _selectedExistingDocs.length;

  @override
  void initState() {
    super.initState();
    _fetchInspections();
    _fetchExistingDocuments(); 
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

  // --- FETCH EXISTING DOCUMENTS LOGIC ---
  Future<void> _fetchExistingDocuments() async {
    try {
      final response = await _apiService.get('/reportTemplate/getByUserAndComapany');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (responseData['success'] == true || responseData['data'] != null) {
        setState(() {
          _existingDocuments = responseData['data'] ?? [];
          _isLoadingExistingDocs = false;
        });
      }
    } catch (e) {
      debugPrint("🚨 Error fetching existing documents: $e");
      if (mounted) setState(() => _isLoadingExistingDocs = false);
    }
  }

  // --- STEP 2 LOGIC (LOCAL FILES) ---
  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true, 
      );
      if (result != null) {
        setState(() => _selectedFiles.addAll(result.files));
      }
    } catch (e) {
      debugPrint("Error picking files: $e");
    }
  }

  void _removeFile(int index) => setState(() => _selectedFiles.removeAt(index));

  // 🚀 THE HEAVY LIFTING: Merge Existing + Upload New -> Register Template -> Trigger AI
  Future<void> _processDocumentsAndAnalyze() async {
    setState(() {
      _isProcessing = true;
      _loadingMessage = "Preparing Documents...";
    });

    try {
      List<String> finalFileKeys = [];
      List<String> finalOriginalFilenames = [];

      // 1. ADD EXISTING DOCUMENTS (No S3 upload needed!)
      for (var doc in _selectedExistingDocs) {
        final String s3Url = doc['s3_report_template_url']?.toString() ?? "";
        finalFileKeys.add(s3Url); 
        
        // Extract the filename from the end of the S3 URL since 'name' is null
        String originalName = doc['name'] ?? "Existing_Document.pdf";
        if (doc['name'] == null && s3Url.isNotEmpty) {
          originalName = s3Url.split('/').last;
        }
        
        finalOriginalFilenames.add(originalName);
      }

      // 2. PROCESS & UPLOAD LOCAL NEW FILES (If any)
      if (_selectedFiles.isNotEmpty) {
        setState(() => _loadingMessage = "Getting upload URLs...");
        
        final presignPayload = {
          "project_id": widget.projectId,
          "files": _selectedFiles.map((f) => {
            "file_name": f.name,
            "content_type": "application/pdf"
          }).toList()
        };

        final presignRes = await _apiService.post('/reportTemplate/upload-presigned-urls', presignPayload);
        final presignData = jsonDecode(presignRes.body);
        final List<dynamic> uploads = presignData['data'] ?? [];

        setState(() => _loadingMessage = "Uploading ${_selectedFiles.length} new documents...");

        List<String> newlyUploadedKeys = []; // 🚀 Track keys for the new API call

        for (var upload in uploads) {
          final fileName = upload['file_name'];
          final signedUrl = upload['signedUrl'];
          final fileKey = upload['key'];

          final localFile = _selectedFiles.firstWhere((f) => f.name == fileName);
          List<int> fileBytes = localFile.bytes ?? await File(localFile.path!).readAsBytes();

          final s3Res = await http.put(
            Uri.parse(signedUrl),
            headers: { 'Content-Type': 'application/pdf' },
            body: fileBytes,
          );

          if (s3Res.statusCode != 200 && s3Res.statusCode != 201) {
            throw Exception("Failed to upload $fileName to S3");
          }
          
          finalFileKeys.add(fileKey);
          finalOriginalFilenames.add(fileName);
          newlyUploadedKeys.add(fileKey); // 🚀 Add to tracking list
        }

        // 🚀 2.5 REGISTER NEW DOCUMENTS IN THE DATABASE
        if (newlyUploadedKeys.isNotEmpty) {
          setState(() => _loadingMessage = "Registering new templates...");
          final createTemplatePayload = {
            "s3_report_template_url": newlyUploadedKeys
          };
          
          final createRes = await _apiService.post('/reportTemplate/create', createTemplatePayload);
          
          if (createRes.statusCode != 200 && createRes.statusCode != 201) {
            debugPrint("Warning: Failed to register new templates in DB. Proceeding anyway...");
          }
        }
      }

      // 3. START SUMMARIZE JOB WITH MERGED DATA
      setState(() => _loadingMessage = "Starting AI Analysis...");
      final summarizePayload = {
        "inspection_ids": _selectedInspectionIds,
        "skill_name": "inspection-skill",
        "fileKeys": finalFileKeys,
        "originalFilenames": finalOriginalFilenames
      };

      final summarizeRes = await _apiService.post('/inspection/report/summarize', summarizePayload);
      final summarizeData = jsonDecode(summarizeRes.body);
      
      final String rawEndpoint = summarizeData['status_endpoint'];
      final String statusEndpoint = rawEndpoint.startsWith('/v1') 
          ? rawEndpoint.replaceFirst('/v1', '') 
          : rawEndpoint;
          
      _summarizeJobId = summarizeData['job_id'];

      // 4. POLL STATUS ENDPOINT
      setState(() => _loadingMessage = "Analyzing Data... This may take a minute.");
      
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
          
          setState(() {
            _clarificationQuestions = pollData['result']['clarification_questions'] ?? [];
            _questionAnswers.clear();
            for (int i = 0; i < _clarificationQuestions.length; i++) {
              _questionAnswers[i] = TextEditingController();
            }
            _currentStep += 1; 
          });
        } else if (pollData['status'] == 'failed' || pollData['status'] == 'error') {
          throw Exception("Analysis job failed on server.");
        }
      }

      if (!isComplete) throw Exception("Analysis timed out.");

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
      if (_totalSelectedDocuments < 3 || _totalSelectedDocuments > 10) {
        ToastService.show(context, message: "Please select between 3 and 10 total PDFs (Selected: $_totalSelectedDocuments).", type: ToastType.error);
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
      final Map<String, String> answersPayload = {};
      
      for (int i = 0; i < _clarificationQuestions.length; i++) {
        final qText = _clarificationQuestions[i]['question'];
        final aText = _questionAnswers[i]?.text.trim() ?? "";
        
        if (aText.isNotEmpty) {
          answersPayload[qText] = aText;
        }
      }

      // Proceed with the payload (it might be an empty map {}, which is perfectly fine)
      final finalizeRes = await _apiService.post(
        '/report-skills/finalize-from-summarize/$_summarizeJobId',
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
          
          final skillContent = pollData['result']['skill']['skill_content'];
          final skillId = pollData['result']['skill']['id'];

          ToastService.show(context, message: "Skill generated successfully!", type: ToastType.success);
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ReportSkillPreviewScreen(
                projectId: widget.projectId,
                skillId: skillId,
                initialContent: skillContent,
                inspectionIds: [..._selectedInspectionIds],
              ),
            ),
          );
          
        } else if (pollData['status'] == 'failed' || pollData['status'] == 'error') {
          throw Exception("Finalization failed on server.");
        }
      }

      if (!isComplete) throw Exception("Finalization timed out.");

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
                                    title: Text(insp['name'] ?? "Inspection", style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Created: $date", 
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
                  // STEP 2: DOCUMENTS (MERGED LOCAL + SERVER UI)
                  // ==========================================
                  Step(
                    title: const Text("Select Sample Documents", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Combine 3 to 10 total PDF files"),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: (_totalSelectedDocuments >= 3 && _totalSelectedDocuments <= 10) 
                                ? colorScheme.primaryContainer 
                                : colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Total Selected: $_totalSelectedDocuments / 10", 
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              color: (_totalSelectedDocuments >= 3 && _totalSelectedDocuments <= 10) 
                                  ? colorScheme.onPrimaryContainer 
                                  : colorScheme.onErrorContainer
                            )
                          ),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Upload New Local Files", style: TextStyle(fontWeight: FontWeight.w600)),
                            Button(
                              label: "Browse PDFs", 
                              variant: ButtonVariant.outline, 
                              icon: Icons.upload_file, 
                              onPressed: _totalSelectedDocuments >= 10 ? null : _pickFiles
                            ),
                          ],
                        ),
                        if (_selectedFiles.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...List.generate(_selectedFiles.length, (index) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                              title: Text(_selectedFiles[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _removeFile(index)),
                            );
                          }),
                        ],

                        const Divider(height: 32),

                        const Text("Or Select Existing Documents", style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        
                        _isLoadingExistingDocs 
                          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                          : _existingDocuments.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text("No existing documents found on server.", style: TextStyle(color: Colors.grey)),
                              )
                            : Container(
                                height: 250, 
                                decoration: BoxDecoration(
                                  border: Border.all(color: colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(8)
                                ),
                                child: ListView.separated(
                                  itemCount: _existingDocuments.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final doc = _existingDocuments[index];
                                    
                                    // 🚀 Parse name from S3 URL if 'name' is null
                                    final String s3Url = doc['s3_report_template_url']?.toString() ?? "";
                                    String displayName = doc['name'] ?? "Document ${index + 1}";
                                    if (doc['name'] == null && s3Url.isNotEmpty) {
                                      displayName = s3Url.split('/').last;
                                    }
                                    
                                    final isSelected = _selectedExistingDocs.contains(doc);

                                    return CheckboxListTile(
                                      value: isSelected,
                                      activeColor: colorScheme.primary,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      title: Text(
                                        displayName, 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis, 
                                        style: const TextStyle(fontSize: 14)
                                      ),
                                      secondary: const Icon(Icons.cloud_done_outlined, color: Colors.blueGrey, size: 20),
                                      onChanged: _totalSelectedDocuments >= 10 && !isSelected 
                                        ? null 
                                        : (bool? val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedExistingDocs.add(doc);
                                              } else {
                                                _selectedExistingDocs.remove(doc);
                                              }
                                            });
                                          },
                                    );
                                  },
                                ),
                              ),
                      ],
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