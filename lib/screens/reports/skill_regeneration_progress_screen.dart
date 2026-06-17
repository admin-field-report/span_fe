import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/api_service.dart'; // Ensure this points to your actual API Service
import '../../../widgets/button/button.dart';

enum RegenerationPhase { polling, questioning, generating, success }

class SkillRegenerationProgressScreen extends StatefulWidget {
  final String templateId;
  final String jobId;
  final String statusEndpoint;

  const SkillRegenerationProgressScreen({
    super.key,
    required this.templateId,
    required this.jobId,
    required this.statusEndpoint,
  });

  @override
  State<SkillRegenerationProgressScreen> createState() => _SkillRegenerationProgressScreenState();
}

class _SkillRegenerationProgressScreenState extends State<SkillRegenerationProgressScreen> {
  final ApiService _apiService = ApiService();
  
  RegenerationPhase _currentPhase = RegenerationPhase.polling;
  String _loadingMessage = "Analyzing document changes & generating skills...";
  String? _errorMessage;

  // Data from the background job's 'result'
  List<dynamic> _questions = [];
  final List<TextEditingController> _answerControllers = [];
  List<String> _conflicts = [];
  List<String> _inconsistencies = [];

  @override
  void initState() {
    super.initState();
    _pollSkillGenerationStatus();
  }

  @override
  void dispose() {
    for (var controller in _answerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // ==========================================
  // 1. POLLING API LOGIC (Initial Extraction)
  // ==========================================
  Future<void> _pollSkillGenerationStatus() async {
    bool isCompleted = false;

    while (!isCompleted && mounted) {
      try {
        final response = await _apiService.get(widget.statusEndpoint);
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final resData = jsonDecode(response.body);
          final status = resData['status']; 

          if (status == 'completed') {
            isCompleted = true;
            
            final result = resData['result'] ?? {};
            final String? nextStepEndpoint = result['next_step'];
            
            final List<String> loadedConflicts = result['design_conflicts'] != null 
                ? List<String>.from(result['design_conflicts']) 
                : [];
                
            final List<String> loadedInconsistencies = result['inconsistencies'] != null 
                ? List<String>.from(result['inconsistencies']) 
                : [];

            if (mounted) {
              if (nextStepEndpoint != null && nextStepEndpoint.isNotEmpty) {
                await _fetchQuestions(nextStepEndpoint, loadedConflicts, loadedInconsistencies);
              } else {
                setState(() => _currentPhase = RegenerationPhase.success);
              }
            }
          } else if (status == 'failed') {
            isCompleted = true;
            if (mounted) {
              setState(() {
                _errorMessage = "Skill generation failed on the server. Please try again.";
                _currentPhase = RegenerationPhase.polling; 
              });
            }
          } else {
            await Future.delayed(const Duration(seconds: 3));
          }
        } else {
           await Future.delayed(const Duration(seconds: 3));
        }
      } catch (e) {
        isCompleted = true;
        if (mounted) setState(() => _errorMessage = "Error connecting to server: $e");
      }
    }
  }

  // ==========================================
  // 2. FETCH CLARIFICATION QUESTIONS
  // ==========================================
  Future<void> _fetchQuestions(String endpoint, List<String> conflicts, List<String> inconsistencies) async {
    try {
      final response = await _apiService.get(endpoint);
      final resData = jsonDecode(response.body);

      final Map<String, dynamic>? dataBlock = resData['data'];
      final List<dynamic>? questionsArray = dataBlock?['clarification_questions'];

      if (questionsArray != null && questionsArray.isNotEmpty) {
        setState(() {
          _questions = questionsArray;
          _conflicts = conflicts;
          _inconsistencies = inconsistencies;

          _answerControllers.clear();
          for (var _ in _questions) {
            _answerControllers.add(TextEditingController());
          }

          _currentPhase = RegenerationPhase.questioning;
        });
      } else {
        setState(() => _currentPhase = RegenerationPhase.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load clarification questions: $e";
          _currentPhase = RegenerationPhase.polling; 
        });
      }
    }
  }

  // ==========================================
  // 3. SUBMIT ANSWERS & POLL FINAL STATUS
  // ==========================================
  void _submitAnswersAndGenerate() async {
    setState(() {
      _currentPhase = RegenerationPhase.generating;
      _loadingMessage = "Submitting clarifications...";
      _errorMessage = null; // Clear previous errors if retrying
    });

    try {
      // 1. 🚀 Build Payload as a Map (Question -> Answer)
      Map<String, String> answersPayload = {};
      for (int i = 0; i < _questions.length; i++) {
        final questionText = _questions[i]['question'] ?? "Question ${i + 1}";
        answersPayload[questionText] = _answerControllers[i].text.trim();
      }

      // 2. 🚀 Send POST request to apply-clarifications
      final response = await _apiService.post(
        '/reportTemplate/${widget.templateId}/apply-clarifications',
        {
          "clarification_answers": answersPayload
        }
      );

      final resData = jsonDecode(response.body);
      
      // 3. 🚀 Extract new status_endpoint
      final String? finalStatusEndpoint = resData['status_endpoint'] ?? (resData['data'] != null ? resData['data']['status_endpoint'] : null);

      if (finalStatusEndpoint == null) {
        // Fallback: If no async job is returned, assume instant completion
        if (mounted) setState(() => _currentPhase = RegenerationPhase.success);
        return;
      }

      // 4. 🚀 Poll the final status endpoint until "completed"
      if (mounted) {
        setState(() => _loadingMessage = "Finalizing report template skill. Almost done...");
      }

      bool isCompleted = false;
      while (!isCompleted && mounted) {
        final pollResponse = await _apiService.get(finalStatusEndpoint);
        
        if (pollResponse.statusCode >= 200 && pollResponse.statusCode < 300) {
          final pollData = jsonDecode(pollResponse.body);
          final status = pollData['status'];

          if (status == 'completed') {
            isCompleted = true;
            if (mounted) setState(() => _currentPhase = RegenerationPhase.success);
          } else if (status == 'failed') {
            isCompleted = true;
            throw Exception(pollData['message'] ?? "Final template generation failed.");
          } else {
            await Future.delayed(const Duration(seconds: 3));
          }
        } else {
          await Future.delayed(const Duration(seconds: 3));
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to finalize template: $e";
          // Drop back to questioning phase so the user can hit submit again if it was a network error
          _currentPhase = RegenerationPhase.questioning; 
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 1,
        title: const Text("Updating Template Skills"),
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentPhase == RegenerationPhase.polling && _errorMessage == null) {
              _showExitWarning(context);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700), 
            child: _buildCurrentPhase(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPhase(ThemeData theme) {
    switch (_currentPhase) {
      case RegenerationPhase.polling:
      case RegenerationPhase.generating:
        return _buildLoadingOrErrorState(theme);
      case RegenerationPhase.questioning:
        return _buildQuestionnaireState(theme);
      case RegenerationPhase.success:
        return _buildSuccessState(theme);
    }
  }

  // ==========================================
  // PHASE 1 & 3: LOADING / ERROR STATE
  // ==========================================
  Widget _buildLoadingOrErrorState(ThemeData theme) {
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              "Something went wrong",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Button(
              label: "Go Back",
              onPressed: () => Navigator.pop(context),
            )
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
                strokeWidth: 4,
              ),
            ),
            Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary, size: 32),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          _loadingMessage,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "This might take a minute. Please don't close this screen.",
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        )
      ],
    );
  }

  // ==========================================
  // PHASE 2: Q&A STATE
  // ==========================================
  Widget _buildQuestionnaireState(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Clarification Questions",
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Answer these to refine the report template (Optional)",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              
              // if (_conflicts.isNotEmpty || _inconsistencies.isNotEmpty)
              //   _buildInsightsBox(theme),

              ...List.generate(_questions.length, (index) {
                final question = _questions[index];
                
                final questionText = question['question'] ?? "Question ${index + 1}";
                final contextText = question['context'] ?? "";
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 24.0),
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest, 
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${index + 1}. $questionText",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                      
                      // if (contextText.isNotEmpty) ...[
                      //   const SizedBox(height: 16),
                      //   Container(
                      //     padding: const EdgeInsets.all(12),
                      //     decoration: BoxDecoration(
                      //       color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      //       borderRadius: BorderRadius.circular(8),
                      //       border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 4)),
                      //     ),
                      //     child: Row(
                      //       crossAxisAlignment: CrossAxisAlignment.start,
                      //       children: [
                      //         Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.primary),
                      //         const SizedBox(width: 8),
                      //         Expanded(
                      //           child: Column(
                      //             crossAxisAlignment: CrossAxisAlignment.start,
                      //             children: [
                      //               Text(
                      //                 "Context", 
                      //                 style: theme.textTheme.labelSmall?.copyWith(
                      //                   color: theme.colorScheme.primary, 
                      //                   fontWeight: FontWeight.bold,
                      //                   letterSpacing: 0.5,
                      //                 )
                      //               ),
                      //               const SizedBox(height: 4),
                      //               Text(
                      //                 contextText, 
                      //                 style: theme.textTheme.bodySmall?.copyWith(
                      //                   color: theme.colorScheme.onSurfaceVariant,
                      //                   height: 1.4,
                      //                 )
                      //               ),
                      //             ],
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ),
                      // ],
                      
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: _answerControllers[index],
                        decoration: InputDecoration(
                          hintText: "Enter your answer here (Optional)...",
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                        ),
                        maxLines: 3,
                        minLines: 2,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Button(
              label: "Finalize Report Template", // 🚀 Updated Button Title
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _submitAnswersAndGenerate,
            ),
          ),
        )
      ],
    );
  }

  Widget _buildInsightsBox(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text(
                "Document Analysis Insights", 
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error, 
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_conflicts.isNotEmpty) ...[
            Text("Design Conflicts Detected:", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 6),
            ..._conflicts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(c, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4))),
                ]
              )
            )),
            const SizedBox(height: 12),
          ],

          if (_inconsistencies.isNotEmpty) ...[
            Text("Inconsistencies Noticed:", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 6),
            ..._inconsistencies.take(4).map((c) => Padding( 
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(c, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4))),
                ]
              )
            )),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // PHASE 4: SUCCESS STATE
  // ==========================================
  Widget _buildSuccessState(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, size: 64, color: Colors.green),
        ),
        const SizedBox(height: 24),
        Text(
          "Template Updated Successfully!",
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "The skills have been successfully regenerated.",
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        Button(
          label: "Return to Template Details",
          onPressed: () => Navigator.pop(context),
        )
      ],
    );
  }

  Future<void> _showExitWarning(BuildContext context) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Update?"),
        content: const Text("The template is still generating its new skills in the background. Are you sure you want to leave this screen?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Stay")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Leave"),
          ),
        ],
      )
    );

    if (shouldExit == true && mounted) {
      Navigator.pop(context);
    }
  }
}