import 'package:flutter/material.dart';

/// Modal bottom sheet for Eve Word-profile clarification Q&A.
///
/// When Eve can't finish building a profile from the example documents
/// alone, the job status settles on `needs_clarification` and the BE
/// exposes a list of follow-up questions:
///
/// GET `/reportTemplate/:id/profile/clarifications`
/// → `{ questions: [ { id, question, options? } ] }`
///
/// This sheet lets the user answer each question (either by picking one of
/// the provided `options` chips or typing a free-form answer), then returns
/// a `questionId -> answer` map for:
///
/// POST `/reportTemplate/:id/profile/clarifications`
/// Body: `{ clarification_answers: { [questionId]: answer } }`
class EveProfileClarificationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> questions;

  const EveProfileClarificationSheet({
    super.key,
    required this.questions,
  });

  /// Convenience helper: show the sheet and return the answers (or null if
  /// the user dismissed it without submitting).
  static Future<Map<String, String>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> questions,
  }) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => EveProfileClarificationSheet(questions: questions),
    );
  }

  @override
  State<EveProfileClarificationSheet> createState() =>
      _EveProfileClarificationSheetState();
}

class _EveProfileClarificationSheetState
    extends State<EveProfileClarificationSheet> {
  // One free-text controller and one "selected chip" slot per question,
  // indexed the same way as widget.questions.
  late final List<TextEditingController> _controllers;
  late final List<String?> _selectedOptions;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.questions.length,
      (_) => TextEditingController(),
    );
    _selectedOptions = List<String?>.filled(widget.questions.length, null);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _questionId(Map<String, dynamic> question, int index) {
    final id = question['id']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    // Fallback so a missing id still submits something usable for debugging.
    return 'q_$index';
  }

  String _questionText(Map<String, dynamic> question) {
    return question['question']?.toString().trim().isNotEmpty == true
        ? question['question'].toString().trim()
        : question['prompt']?.toString().trim() ?? 'Question';
  }

  List<String> _options(Map<String, dynamic> question) {
    final raw = question['options'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _submit() {
    final answers = <String, String>{};
    for (var i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final id = _questionId(question, i);
      final option = _selectedOptions[i];
      final typed = _controllers[i].text.trim();
      // A picked chip wins over typed text if both are somehow set.
      final answer = (option != null && option.isNotEmpty) ? option : typed;
      if (answer.isNotEmpty) {
        answers[id] = answer;
      }
    }

    if (answers.isEmpty) {
      setState(() {
        _validationError = 'Please answer at least one question before submitting.';
      });
      return;
    }

    Navigator.of(context).pop(answers);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              // Drag handle.
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Profile clarifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'The Word profile builder needs a bit more detail before it can finish.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _validationError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  itemCount: widget.questions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final question = widget.questions[index];
                    final options = _options(question);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _questionText(question),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (options.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: options.map((option) {
                              final selected = _selectedOptions[index] == option;
                              return ChoiceChip(
                                label: Text(option),
                                selected: selected,
                                onSelected: (value) {
                                  setState(() {
                                    _selectedOptions[index] =
                                        value ? option : null;
                                    _validationError = null;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        if (options.isNotEmpty) const SizedBox(height: 8),
                        TextField(
                          controller: _controllers[index],
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: options.isEmpty
                                ? 'Your answer'
                                : 'Or type a custom answer',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_validationError != null) {
                              setState(() => _validationError = null);
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Submit answers'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
