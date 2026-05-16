import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/api_service.dart';
import '../../screens/auth/controllers/auth_controller.dart';

class ChatMessage {
  String text; 
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class AIDataScreen extends StatefulWidget {
  const AIDataScreen({super.key});

  @override
  State<AIDataScreen> createState() => _AIDataScreenState();
}

class _AIDataScreenState extends State<AIDataScreen> {

  final ApiService _apiService = ApiService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController(); // Used to auto-scroll
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  
  bool _hasStartedChat = false;
  bool _isTyping = false; 
  bool _isListening = false;
  bool _isLoading = false; // Blocks sending while API/Stream is running

  final List<String> _suggestions = [
    "Open RFIs", 
    "Weather delays", 
    "List pending inspections", 
    "Review equipment logs", 
    "Summarize today's site progress", 
    "Draft a weekly progress report for the client", 
    "Generate a concrete pour field report for sector B", 
  ];

  @override
  void initState() {
    super.initState();
    _chatController.addListener(() {
      setState(() {
        _isTyping = _chatController.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Auto-scrolls to the bottom of the chat
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  // 🚀 1. THE API CALL
  // 🚀 1. THE API CALL
  Future<void> _handleSendMessage() async {
    String text = _chatController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _hasStartedChat = true;
      _isLoading = true;
      // Add the user's message to the UI immediately
      _messages.add(ChatMessage(text: text, isUser: true));
      _chatController.clear();
      _focusNode.requestFocus(); 
      
      // Temporary loading indicator while waiting for the server
      _messages.add(ChatMessage(text: "Thinking...", isUser: false));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      // 🚀 STANDARD HTTP POST REQUEST
      final response = await _apiService.post('/ai', {
          "userMessage": text
        }
      );

      final data = jsonDecode(response.body);
        
        // 🚀 Extract the response text
        // Note: Change 'response' to whatever key your backend actually returns!
        // e.g., data['message'], data['data']['text'], etc.
        String fullResponse = data['response'] ?? "Message received, but response key was missing.";
        
        // Trigger the fake stream effect
        _simulateStream(fullResponse);
    } catch (e) {
      _showError("Failed to connect to the server. Please check your connection.");
    }
  }

  // 🚀 2. THE STREAM SIMULATOR (Called when the API returns success)
  void _simulateStream(String fullText) {
    setState(() {
      _messages.removeLast(); // Remove the "Thinking..." message
      _messages.add(ChatMessage(text: "", isUser: false)); // Add empty message to build upon
    });

    int currentIndex = 0;
    
    // Fires every 20ms to add one character at a time, creating a typewriter effect
    Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (currentIndex < fullText.length) {
        setState(() {
          _messages.last.text += fullText[currentIndex];
        });
        currentIndex++;
        
        if (currentIndex % 10 == 0) _scrollToBottom(); 
      } else {
        timer.cancel(); // Stop the stream when finished
        setState(() {
          _isLoading = false; // Re-enable the send button
        });
        _scrollToBottom();
      }
    });
  }

  // Helper to show errors gracefully in the chat
  void _showError(String errorMessage) {
    if (!mounted) return;
    setState(() {
      _messages.removeLast();
      _messages.add(ChatMessage(text: "⚠️ $errorMessage", isUser: false));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  void _toggleListening() {
    setState(() => _isListening = !_isListening);
    if (_isListening) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Listening..."), duration: Duration(seconds: 2)),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isListening) {
          setState(() {
            _chatController.text = "Show me the latest safety incidents for sector B";
            _isListening = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: authController,
      builder: (context, child) {
        return Scaffold(
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _hasStartedChat ? _buildActiveChatLayout(theme) : _buildEmptyStateLayout(theme),
            ),
          ),
        );
      }
    );
  }

  Widget _buildEmptyStateLayout(ThemeData theme) {
    return Center(
      key: const ValueKey("empty_state"),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Hi ${authController.user?.firstName ?? ''} ${authController.user?.lastName ?? 'there'}! 👋".trim(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Where should we start today?",
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),
              _buildChatInputField(theme),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: _suggestions.map((text) {
                  return ActionChip(
                    label: Text(text),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onPressed: () {
                      _chatController.text = text;
                      _handleSendMessage();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveChatLayout(ThemeData theme) {
    return Column(
      key: const ValueKey("active_state"),
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController, // 🚀 Attached scroll controller
            padding: const EdgeInsets.all(24.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _buildMessageBubble(_messages[index], theme);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _buildChatInputField(theme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatInputField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.only(left: 20, right: 8, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            // 🚀 3. THE KEYBOARD INTERCEPTOR
            child: Focus(
              onKeyEvent: (node, event) {
                // Intercept the Enter key
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                  // Check if Shift is being held down
                  if (HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight)) {
                    return KeyEventResult.ignored; // Let the TextField add a new line natively
                  } else {
                    _handleSendMessage(); // Send message
                    return KeyEventResult.handled; // Prevent the new line from happening
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _chatController,
                focusNode: _focusNode, // Important for keeping focus!
                minLines: 1,
                maxLines: 6, 
                textInputAction: TextInputAction.none, // We handle the 'Enter' action manually now
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: _isListening ? "Listening..." : "Ask anything about your tools & data...",
                  hintStyle: TextStyle(
                    color: _isListening ? Colors.red : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isListening 
                    ? Colors.red.withOpacity(0.9)
                    : (_isTyping ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isLoading 
                      ? Icons.stop_rounded // Optional: Change to stop square while loading
                      : (_isListening 
                          ? Icons.stop_rounded 
                          : (_isTyping ? Icons.arrow_upward_rounded : Icons.mic_none_rounded))
                ),
                color: _isListening || _isTyping || _isLoading
                    ? theme.colorScheme.onPrimary 
                    : theme.colorScheme.onSurfaceVariant,
                // Disable button clicks while streaming/loading
                onPressed: _isLoading 
                    ? null 
                    : (_isTyping ? _handleSendMessage : _toggleListening),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: message.isUser ? theme.colorScheme.surfaceVariant.withOpacity(0.5) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              // 🚀 THE FIX: Use MarkdownBody for AI, standard Text for User
              child: message.isUser 
                ? Text(
                    message.text,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  )
                : MarkdownBody(
                    data: message.text,
                    selectable: true, // Allows the user to copy text from the response!
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15, height: 1.5),
                      h1: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.bold, height: 1.5),
                      h2: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold, height: 1.5),
                      h3: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold, height: 1.5),
                      listBullet: TextStyle(color: theme.colorScheme.primary, fontSize: 15),
                      // Beautiful code block styling:
                      code: TextStyle(
                        backgroundColor: Colors.transparent,
                        color: theme.colorScheme.primary,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                    ),
                  ),
            ),
          ),
          
          if (message.isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceVariant,
              child: Icon(Icons.person_outline, color: theme.colorScheme.onSurfaceVariant, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}