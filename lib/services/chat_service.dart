import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'model_download_service.dart';
import 'settings_service.dart';
import 'groq_service.dart';

/// Chat service with automatic chat template support and context management
/// 
/// Features:
/// - Automatic template detection from model filename (Qwen, Llama-3, etc.)
/// - Multi-turn conversation history management
/// - Streaming token generation
/// - Stop/cancel generation
/// - Configurable system messages
/// 
/// Example:
/// ```dart
/// final chatService = ChatService();
/// await chatService.initialize();
/// await chatService.loadModel(...);
/// chatService.sendMessage('Hello!'); // Auto-uses correct template
/// ```
/// 
/// Supported models (auto-detected):
/// - Qwen / Qwen2 (ChatML)
/// - Llama-3 (Llama-3 format)
/// - Llama-2 (Llama-2 format)
/// - Phi-2/3, Gemma, Alpaca, Vicuna
class ChatService {
  final ModelDownloadService _downloadService = ModelDownloadService();
  final SettingsService _settingsService = SettingsService();
  late final GroqService _groqService;
  LlamaController? _llama;
  bool _useOnlineInference = false;
  final StreamController<String> _messageStreamController = StreamController<String>.broadcast();
  final StreamController<bool> _generatingStateController = StreamController<bool>.broadcast();
  final StreamController<ContextInfo> _contextInfoStreamController = StreamController<ContextInfo>.broadcast();
  final StreamController<bool> _modelUnloadStreamController = StreamController<bool>.broadcast();
  final List<ChatMessage> _conversationHistory = [];
  StreamSubscription<String>? _generationSubscription;
  bool _isLoadingModel = false;
  bool _isGenerating = false;
  bool _isCancelled = false;
  
  // Simple context management (80% rule)
  ContextHelper? _contextHelper;
  
  // User-configurable generation settings
  GenerationConfig generationConfig = const GenerationConfig();
  
  // Settings
  int _contextSize = 2048; // Default context size
  String _chatTemplate = 'auto'; // Default chat template
  bool _autoUnloadModel = false; // Whether to auto-unload model
  int _autoUnloadTimeout = 60; // Timeout in seconds (default 60)
  Timer? _autoUnloadTimer; // Timer for auto-unloading
  bool _ttsEnabled = false; // TTS enabled state
  
  Stream<String> get messageStream => _messageStreamController.stream;
  Stream<bool> get generatingStateStream => _generatingStateController.stream;
  Stream<ContextInfo> get contextInfoStream => _contextInfoStreamController.stream;
  Stream<bool> get modelUnloadStream => _modelUnloadStreamController.stream;
  
  bool get isLoadingModel => _isLoadingModel;
  bool get isGenerating => _isGenerating;
  bool get ttsEnabled => _ttsEnabled;
  bool get isOnlineMode => _useOnlineInference;

  void setOnlineMode(bool enabled) {
    _useOnlineInference = enabled;
    debugPrint('[ChatService] Online mode set to: $enabled');
  }

  List<ChatMessage> get conversationHistory => List.unmodifiable(_conversationHistory);
  ContextHelper? get contextHelper => _contextHelper;
  
  /// Initialize the chat service
  /// 
  /// [systemMessage] - Optional custom system message. If null, uses default from settings.
  Future<bool> initialize({String? systemMessage}) async {
    debugPrint('[ChatService] Initializing ChatService...');
    
    // Initialize the settings service
    await _settingsService.init();
    
    // Initialize Groq service
    _groqService = GroqService(settingsService: _settingsService);
    
    // Load settings
    _contextSize = _settingsService.contextSize;
    _chatTemplate = _settingsService.chatTemplate;
    _autoUnloadModel = _settingsService.autoUnloadModel;
    _autoUnloadTimeout = _settingsService.autoUnloadTimeout;
    _ttsEnabled = _settingsService.ttsEnabled;
    
    // Register all custom templates with native code
    await _registerCustomTemplates();
    
    // Initialize the download service
    final modelExists = await _downloadService.initialize();
    
    // Add system message to conversation history
    if (_conversationHistory.isEmpty) {
      // Use passed system message, or get from settings, or fall back to default
      final finalSystemMessage = systemMessage ?? _settingsService.systemMessage;
      _conversationHistory.add(ChatMessage(
        role: 'system',
        content: finalSystemMessage,
      ));
      debugPrint('[ChatService] ✓ System message added to conversation history');
      debugPrint('[ChatService]   Content: "$finalSystemMessage"');
    }
    
    return modelExists;
  }
  
  /// Register all custom templates with the native layer
  /// Called on app initialization to sync Dart storage with Kotlin runtime
  Future<void> _registerCustomTemplates() async {
    try {
      final customTemplates = _settingsService.getAllCustomTemplates();
      
      if (customTemplates.isEmpty) {
        debugPrint('[ChatService] No custom templates to register');
        return;
      }
      
      debugPrint('[ChatService] Registering ${customTemplates.length} custom template(s)...');
      
      for (final entry in customTemplates.entries) {
        try {
          await _llama?.registerCustomTemplate(entry.key, entry.value);
          debugPrint('[ChatService]   ✓ Registered: ${entry.key}');
        } catch (e) {
          debugPrint('[ChatService]   ✗ Failed to register ${entry.key}: $e');
        }
      }
      
      debugPrint('[ChatService] ✓ Custom template registration complete');
    } catch (e) {
      debugPrint('[ChatService] ✗ Error registering custom templates: $e');
    }
  }
  
  /// Update the system message (replaces existing if present)
  void setSystemMessage(String message) {
    debugPrint('[ChatService] Updating system message...');
    if (_conversationHistory.isEmpty) {
      _conversationHistory.add(ChatMessage(
        role: 'system',
        content: message,
      ));
    } else if (_conversationHistory.first.role == 'system') {
      _conversationHistory[0] = ChatMessage(
        role: 'system',
        content: message,
      );
    } else {
      _conversationHistory.insert(0, ChatMessage(
        role: 'system',
        content: message,
      ));
    }
    debugPrint('[ChatService] ✓ System message updated: "$message"');
  }
  
  String? get modelPath => _downloadService.modelPath;
  
  /// Pick and load a model from local storage
  Future<String?> pickLocalModel() async {
    return await _downloadService.pickLocalModel();
  }
  
  /// Set a custom model path
  void setCustomModelPath(String path) {
    _downloadService.setCustomModelPath(path);
  }
  
  bool get hasModelPath => _downloadService.modelPath != null;
  
  Future<void> loadModel({
    required void Function(double progress) onProgress,
    required void Function(String status) onStatus,
  }) async {
    debugPrint('[ChatService] ===== Starting model load process =====');
    
    if (_isLoadingModel) {
      debugPrint('[ChatService] ⚠ Model is already loading, returning');
      return;
    }
    
    _isLoadingModel = true;
    debugPrint('[ChatService] Set _isLoadingModel = true');
    onStatus('Loading model...');
    
    try {
      // First, dispose of any existing model
      if (_llama != null) {
        debugPrint('[ChatService] Disposing existing LlamaController...');
        try {
          // Always try to dispose, ignore errors
          await _llama!.dispose();
          debugPrint('[ChatService] ✓ Existing model disposed');
        } catch (e) {
          debugPrint('[ChatService] ⚠ Error disposing existing model (continuing anyway): $e');
        }
        
        // Always clear reference and wait for cleanup
        _llama = null;
        debugPrint('[ChatService] ✓ LlamaController reference cleared');
        
        // Give extra time for native cleanup to complete
        debugPrint('[ChatService] Waiting 1 second for native cleanup...');
        await Future.delayed(Duration(seconds: 1));
        debugPrint('[ChatService] ✓ Native cleanup wait complete');
      }
      
      final modelPath = _downloadService.modelPath;
      debugPrint('[ChatService] Model path from download service: $modelPath');
      
      if (modelPath == null) {
        debugPrint('[ChatService] ✗ Error: Model path is null');
        throw Exception('Model file path is null');
      }
      
      final modelFile = File(modelPath);
      debugPrint('[ChatService] Checking if model file exists at: $modelPath');
      
      if (!await modelFile.exists()) {
        debugPrint('[ChatService] ✗ Error: Model file does not exist at path');
        throw Exception('Model file does not exist at: $modelPath');
      }
      
      final fileSize = await modelFile.length();
      debugPrint('[ChatService] ✓ Model file exists! Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Ensure we're in a clean state
      if (_llama != null) {
        debugPrint('[ChatService] ⚠ Warning: _llama is not null before creation!');
        throw Exception('Cannot load model: Previous model not properly disposed');
      }
      
      debugPrint('[ChatService] Creating new LlamaController instance...');
      onStatus('Creating LlamaController...');
      _llama = LlamaController();
      debugPrint('[ChatService] ✓ LlamaController created');
      
      // Wait a moment before loading
      await Future.delayed(Duration(milliseconds: 200));
      
      // Listen to progress
      debugPrint('[ChatService] Setting up progress listener...');
      _llama!.loadProgress.listen((progress) {
        final progressPercent = progress * 100;
        debugPrint('[ChatService] Load progress: ${progressPercent.toStringAsFixed(1)}%');
        onProgress(progressPercent);
      });
      
      // Use context size from settings
      final contextSize = _contextSize;
      
      debugPrint('[ChatService] Calling loadModel with:');
      debugPrint('[ChatService]   - modelPath: $modelPath');
      debugPrint('[ChatService]   - threads: 4');
      debugPrint('[ChatService]   - contextSize: $contextSize');
      
      await _llama!.loadModel(
        modelPath: modelPath,
        threads: 4,
        contextSize: contextSize,
      );
      
      debugPrint('[ChatService] ✓✓✓ Model loaded successfully!');
      
      // Initialize context helper with FLLAMA-inspired improvements (80% rule) - MUST match model context!
      _contextHelper = ContextHelper(
        contextSize: contextSize,  // Use settings context size
        maxMessagesToKeep: 15,  // Increased from 8 to 15 for better context preservation
      );
      debugPrint('[ChatService] ✓ Context helper initialized');
      debugPrint('[ChatService]   - Context: $contextSize tokens');
      debugPrint('[ChatService]   - Safe limit: ${_contextHelper!.safeTokenLimit} tokens (80%)');
      debugPrint('[ChatService]   - Safety buffer: ${_contextHelper!.safetyBuffer} tokens (20%)');
      debugPrint('[ChatService]   - Max messages to keep: 15 (increased for better context preservation)');
      
      // Broadcast initial context info
      await _broadcastContextInfo();
      
      onStatus('Model loaded successfully!');
    } catch (e) {
      debugPrint('[ChatService] ✗✗✗ Error loading model: $e');
      debugPrint('[ChatService] Stack trace: ${StackTrace.current}');
      
      // Provide more helpful error messages
      String errorMessage = e.toString();
      if (errorMessage.contains('Model already loaded')) {
        errorMessage = 'Model already loaded. Please restart the app or wait a moment and try again.';
        debugPrint('[ChatService] ⚠ HINT: This usually means native cleanup is still in progress.');
        debugPrint('[ChatService] ⚠ HINT: Try increasing the cleanup delay or restart the app.');
      }
      
      onStatus('Failed to load model: $errorMessage');
      
      // Cleanup on error
      if (_llama != null) {
        try {
          await _llama!.dispose();
        } catch (disposeError) {
          debugPrint('[ChatService] Error during cleanup dispose: $disposeError');
        }
        _llama = null;
      }
      
      rethrow;
    } finally {
      _isLoadingModel = false;
      debugPrint('[ChatService] Set _isLoadingModel = false');
      debugPrint('[ChatService] ===== Model load process complete =====');
    }
  }
  
  Future<bool> isModelLoaded() async {
    debugPrint('[ChatService] Checking if model is loaded...');
    if (_llama == null) {
      debugPrint('[ChatService] LlamaController is null');
      return false;
    }
    final isLoaded = await _llama!.isModelLoaded();
    debugPrint('[ChatService] Model loaded status: $isLoaded');
    return isLoaded;
  }
  
  /// Get list of supported chat templates
  /// Returns templates like: ['chatml', 'qwen', 'llama3', 'llama2', 'phi', 'gemma', 'alpaca', 'vicuna']
  Future<List<String>> getSupportedTemplates() async {
    debugPrint('[ChatService] Getting supported templates...');
    if (_llama == null) {
      debugPrint('[ChatService] ✗ LlamaController is null');
      return [];
    }
    try {
      final templates = await _llama!.getSupportedTemplates();
      debugPrint('[ChatService] ✓ Supported templates: $templates');
      return templates;
    } catch (e) {
      debugPrint('[ChatService] ✗ Error getting templates: $e');
      return [];
    }
  }
  
  /// Send a message and get a streaming response
  /// 
  /// [message] - The user's message
  /// [template] - Optional template override (e.g., 'chatml', 'llama3')
  ///              If null, template is auto-detected from model filename
  void sendMessage(String message, {String? template}) async {
    debugPrint('[ChatService] ===== Sending message with chat template =====');
    debugPrint('[ChatService] User message: "$message"');
    if (template != null) {
      debugPrint('[ChatService] Template override: $template');
    } else {
      debugPrint('[ChatService] Template: auto-detected from model');
    }
    
    // Reset auto-unload timer since there's user activity
    _resetAutoUnloadTimer();
    
    if (_isGenerating) {
      debugPrint('[ChatService] ⚠ Already generating, returning');
      return;
    }
    
    // Online Inference Logic
    if (_useOnlineInference) {
      debugPrint('[ChatService] Using Online Inference (Groq)');
      await _sendMessageOnline(message);
      return;
    }

    if (_llama == null) {
      debugPrint('[ChatService] ✗ Error: LlamaController is null');
      _messageStreamController.add("Error: Model not loaded. Please load the model first.\n");
      return;
    }
    
    // Simple context check (80% rule)
    // Check BEFORE adding the new message to see if we'll exceed the limit
    if (_contextHelper != null && _llama != null) {
      final info = await _llama!.getContextInfo();
      final estimatedNewTokens = _contextHelper!.estimateTokens(message);
      final projectedTotal = info.tokensUsed + estimatedNewTokens;
      
      debugPrint('[ChatService] Context check: ${info.tokensUsed}/${info.contextSize} tokens (${info.usagePercentage.toStringAsFixed(1)}%)');
      debugPrint('[ChatService] Estimated new message: ~$estimatedNewTokens tokens');
      debugPrint('[ChatService] Projected total: $projectedTotal tokens');
      
      if (_contextHelper!.mustClear(projectedTotal)) {
        debugPrint('[ChatService] ⚠ Projected context at ${(projectedTotal / info.contextSize * 100).toStringAsFixed(0)}% - clearing old messages...');
        await _handleContextOverflow();
        _messageStreamController.add("[Context cleared to continue conversation]\n\n");
      } else if (_contextHelper!.isNearLimit(projectedTotal)) {
        debugPrint('[ChatService] ⚠ Projected context at ${(projectedTotal / info.contextSize * 100).toStringAsFixed(0)}% - approaching limit');
      }
    }
    
    _isGenerating = true;
    _isCancelled = false;
    _generatingStateController.add(true);
    debugPrint('[ChatService] Set _isGenerating = true');
    
    try {
      // Before adding the new message, ensure history doesn't get too long
      // Truncate history if it's getting too long to prevent KV cache issues
      // FLLAMA-inspired approach: Keep more messages but with smarter trimming
      _truncateHistoryIfNeeded(20); // Increased from 15 to 20 for better context preservation
      
      // Add user message to conversation history
      _conversationHistory.add(ChatMessage(
        role: 'user',
        content: message,
      ));
      debugPrint('[ChatService] Added user message to conversation history');
      debugPrint('[ChatService] Current conversation length: ${_conversationHistory.length} messages');
      
      // Check if context might be getting too long - implement conversation history management
      if (_conversationHistory.length > 12) { // With truncation, this shouldn't happen often
        debugPrint('[ChatService] ⚠ Conversation history is getting long (${_conversationHistory.length} messages)');
        debugPrint('[ChatService] ⚠ This might cause KV cache shifting issues during generation');
      }
      
      // Notify UI about user message
      _messageStreamController.add("User: $message\nAI: ");
      
      // Calculate safe max tokens based on 80% rule
      final maxTokens = await _calculateSafeMaxTokens();
      
      // Generate response using chat template (auto-detected or override)
      debugPrint('[ChatService] Starting generation with parameters:');
      debugPrint('[ChatService]   - messages: ${_conversationHistory.length}');
      debugPrint('[ChatService]   - maxTokens: $maxTokens (safe limit)');
      debugPrint('[ChatService]   - temperature: ${generationConfig.temperature}');
      debugPrint('[ChatService]   - topP: ${generationConfig.topP}');
      
      // Use the provided template override if available, otherwise use the setting
      final effectiveTemplate = template ?? _chatTemplate;
      
      // Log conversation history being sent to native layer
      debugPrint('[ChatService] ===== Conversation History Being Sent =====');
      debugPrint('[ChatService] Total messages: ${_conversationHistory.length}');
      for (int i = 0; i < _conversationHistory.length; i++) {
        final msg = _conversationHistory[i];
        final preview = msg.content.length > 50 
            ? '${msg.content.substring(0, 50)}...' 
            : msg.content;
        debugPrint('[ChatService]   [$i] ${msg.role}: "$preview"');
      }
      debugPrint('[ChatService] ==========================================');
      
      debugPrint('[ChatService] Calling generateChat()...');
      final stream = _llama!.generateChat(
        messages: _conversationHistory,
        maxTokens: maxTokens,
        temperature: generationConfig.temperature,
        topP: generationConfig.topP,
        topK: generationConfig.topK,
        repeatPenalty: generationConfig.repeatPenalty,
        seed: generationConfig.seed,
        template: effectiveTemplate,
      );

      
      debugPrint('[ChatService] ✓ generateChat() returned stream');
      
      final responseBuffer = StringBuffer();
      int tokenCount = 0;
      bool streamStarted = false;
      String lastToken = '';
      int repeatCount = 0;
      const maxConsecutiveRepeats = 5; // Max number of times a token can repeat consecutively
      
      debugPrint('[ChatService] Setting up stream listener...');
      
      // Use await for to properly handle stream completion
      debugPrint('[ChatService] Starting to listen to stream with await for...');
      debugPrint('[ChatService] Waiting for first token (timeout: 30 seconds)...');
      
      try {
        // Add timeout to detect if stream never starts
        final streamWithTimeout = stream.timeout(
          Duration(seconds: 30),
          onTimeout: (sink) {
            if (!streamStarted) {
              debugPrint('[ChatService] ⚠⚠⚠ STREAM TIMEOUT: No tokens received after 30 seconds');
              debugPrint('[ChatService] ⚠ This suggests the native code is not sending tokens');
              debugPrint('[ChatService] ⚠ Check native generation callback configuration');
            }
            sink.close();
          },
        );
        
        await for (final token in streamWithTimeout) {
          if (!streamStarted) {
            streamStarted = true;
            debugPrint('[ChatService] ✓ Stream started - first token arrived');
          }
          
          // Filter out replacement characters usually shown as <?>
          // logical-not-valid chars often appear in quantized models
          final cleanToken = token.replaceAll('\uFFFD', '');
          if (cleanToken.isEmpty) continue;
          
          debugPrint('[ChatService] TOKEN RECEIVED: "$cleanToken"');
          if (_isCancelled) {
            debugPrint('[ChatService] ⚠ Generation cancelled, breaking stream');
            break;
          }
          
          // Check for repetitive tokens to prevent infinite loops
          if (cleanToken == lastToken) {
            repeatCount++;
            if (repeatCount >= maxConsecutiveRepeats) {
              debugPrint('[ChatService] ⚠⚠⚠ DETECTED REPETITIVE TOKENS: "$cleanToken" repeated $repeatCount times');
              debugPrint('[ChatService] ⚠ Stopping generation to prevent infinite loop');
              await stopGeneration(); // Stop generation to prevent infinite loop
              break;
            }
          } else {
            repeatCount = 0; // Reset counter when token changes
          }
          
          // Check for specific patterns that might indicate KV cache issues
          // e.g., repeated tokens like "None", empty tokens, or other problematic patterns
          if (cleanToken == "None" || cleanToken == "" || cleanToken == "\nNone" || cleanToken == " None") {
            debugPrint('[ChatService] ⚠ DETECTED POTENTIAL KV CACHE ISSUE: Received problematic token "$cleanToken"');
            // Increment a counter for problematic tokens
            if (responseBuffer.toString().contains(cleanToken) && tokenCount > 10) {
              // If we see the same problematic token pattern multiple times, stop generation
              if (tokenCount > 50 && responseBuffer.toString().split(cleanToken).length > 10) {
                debugPrint('[ChatService] ⚠⚠⚠ TOO MANY PROBLEMATIC TOKENS - STOPPING GENERATION');
                await stopGeneration();
                break;
              }
            }
          }
          
          lastToken = cleanToken;
          
          tokenCount++;
          responseBuffer.write(cleanToken);
          if (tokenCount == 1) {
            debugPrint('[ChatService] ✓✓✓ FIRST TOKEN RECEIVED!');
          }
          if (tokenCount % 10 == 0) {
            debugPrint('[ChatService] Generated $tokenCount tokens so far...');
          }
          _messageStreamController.add(cleanToken);
        }
        
        // Stream completed - this executes AFTER the stream is done
        debugPrint('[ChatService] ===== Stream completed (await for finished) =====');
        debugPrint('[ChatService] Current time: ${DateTime.now()}');
        debugPrint('[ChatService] Total tokens received: $tokenCount');
        debugPrint('[ChatService] Stream ever started: $streamStarted');
        
        // Add assistant response to conversation history
        final assistantResponse = responseBuffer.toString();
        debugPrint('[ChatService] Assistant response length: ${assistantResponse.length} characters');
        
        // Check if stream completed without receiving any tokens
        if (!streamStarted && tokenCount == 0) {
          debugPrint('[ChatService] ⚠⚠⚠ CRITICAL: Stream completed but no tokens were received!');
          debugPrint('[ChatService] ⚠ Native code may have failed silently');
          debugPrint('[ChatService] ⚠ Or the stream is not properly connected to native callbacks');
          _messageStreamController.add("\n[Error: No response generated. The model may have encountered an issue.]\n");
        }
        
        if (assistantResponse.isNotEmpty && !_isCancelled) {
          _conversationHistory.add(ChatMessage(
            role: 'assistant',
            content: assistantResponse,
          ));
          debugPrint('[ChatService] ✓ Generation complete. Total tokens: $tokenCount');
          debugPrint('[ChatService] ✓ Assistant response added to history');
          debugPrint('[ChatService] ✓ Response content: "${assistantResponse.length > 50 ? "${assistantResponse.substring(0, 50)}..." : assistantResponse}"');
          debugPrint('[ChatService] ✓ Conversation now has ${_conversationHistory.length} messages');
          _messageStreamController.add("\n");
          
          // Update context info after generation
          await _broadcastContextInfo();
        } else if (_isCancelled) {
          debugPrint('[ChatService] ⚠ Generation was cancelled');
          if (assistantResponse.isNotEmpty) {
            // Add partial response to history
            _conversationHistory.add(ChatMessage(
              role: 'assistant',
              content: assistantResponse,
            ));
            debugPrint('[ChatService] ⚠ Partial response saved to history');
          } else {
            // Remove user message if no response generated
            if (_conversationHistory.isNotEmpty && _conversationHistory.last.role == 'user') {
              _conversationHistory.removeLast();
              debugPrint('[ChatService] Removed user message (no response)');
            }
          }
          _messageStreamController.add("\n[Generation stopped]\n");
        } else {
          debugPrint('[ChatService] ⚠ WARNING: Response buffer is empty!');
        }
        
        // CRITICAL: Update state
        _isGenerating = false;
        _generationSubscription = null;
        
        // Force state update to UI
        debugPrint('[ChatService] Broadcasting state update: isGenerating = false');
        _generatingStateController.add(false);
        
        debugPrint('[ChatService] ✓✓✓ State updated - generation flag cleared');
      } catch (streamError) {
        debugPrint('[ChatService] ✗✗✗ Stream error: $streamError');
        debugPrint('[ChatService] Error stack trace: ${StackTrace.current}');
        
        // Check if the error is due to decoding failure
        if (streamError.toString().contains('Failed to decode') || 
            streamError.toString().contains('decode')) {
          debugPrint('[ChatService] ⚠ DETECTED DECODING FAILURE - this might be related to KV cache shifting');
          _messageStreamController.add("\n[Error: Model encountered a decoding issue. The conversation may be too long for the context size. Consider unloading and reloading the model.]\n");
        } else {
          _messageStreamController.add("\nError: $streamError\n");
        }
      } finally {
        // CRITICAL: Update state immediately
        _isGenerating = false;
        _generationSubscription = null;
        
        // Force state broadcast
        debugPrint('[ChatService] Broadcasting error state: isGenerating = false');
        _generatingStateController.add(false);
        
        debugPrint('[ChatService] ✓ Set _isGenerating = false (error)');
        
        // Remove the user message if generation failed
        if (_conversationHistory.isNotEmpty && _conversationHistory.last.role == 'user') {
          _conversationHistory.removeLast();
          debugPrint('[ChatService] Removed failed user message from history');
        }
      }
    } catch (e) {
      debugPrint('[ChatService] ✗✗✗ Error during message generation: $e');
      debugPrint('[ChatService] Stack trace: ${StackTrace.current}');
      _messageStreamController.add("\nError: $e\n");
      
      // Remove the user message if generation failed
      if (_conversationHistory.isNotEmpty && _conversationHistory.last.role == 'user') {
        _conversationHistory.removeLast();
        debugPrint('[ChatService] Removed failed user message from history');
      }
      
      _isGenerating = false;
      _generatingStateController.add(false);
      _generationSubscription = null;
      debugPrint('[ChatService] Set _isGenerating = false (catch block)');
    } finally {
      // CRITICAL SAFETY NET: Always ensure state is cleared
      if (_isGenerating) {
        debugPrint('[ChatService] ⚠⚠⚠ CRITICAL: Finally block detected stuck generation state!');
        debugPrint('[ChatService] ⚠⚠⚠ Force-resetting to prevent UI lockup...');
        _isGenerating = false;
        _generationSubscription = null;
        _generatingStateController.add(false);
      }
    }
    
    debugPrint('[ChatService] ===== Message processing complete =====');
    debugPrint('[ChatService] final state: isGenerating = $_isGenerating');
  }
  
  Future<void> _sendMessageOnline(String message) async {
    _isGenerating = true;
    _isCancelled = false;
    _generatingStateController.add(true);
    
    // Add user message to history
    _conversationHistory.add(ChatMessage(role: 'user', content: message));
    _messageStreamController.add("User: $message\nAI: ");
    
    try {
      // Prepare history for Groq
      // Exclude the last message (current user message) as it is passed separately
      final historyList = _conversationHistory.sublist(0, _conversationHistory.length - 1);
      final history = <Map<String, String>>[];
      String? systemPrompt;
      
      for (final msg in historyList) {
        if (msg.role == 'system') {
          systemPrompt = msg.content;
        } else {
          history.add({'role': msg.role, 'content': msg.content});
        }
      }

      debugPrint('[ChatService] Sending request to Groq...');
      final stream = _groqService.sendMessageStream(
        message, 
        history, 
        systemMessage: systemPrompt
      );
      
      final responseBuffer = StringBuffer();
      
      await for (final token in stream) {
        if (_isCancelled) break;
        responseBuffer.write(token);
        _messageStreamController.add(token);
      }
      
      final response = responseBuffer.toString();
      
      if (!_isCancelled && response.isNotEmpty) {
        _conversationHistory.add(ChatMessage(role: 'assistant', content: response));
        _messageStreamController.add("\n");
        debugPrint('[ChatService] Groq response complete');
      } else if (_isCancelled) {
        _messageStreamController.add("\n[Stopped]\n");
      }
      
    } catch (e) {
       debugPrint('[ChatService] Groq Error: $e');
       _messageStreamController.add("\nError: $e\n");
       // Remove failed message
       if (_conversationHistory.isNotEmpty && _conversationHistory.last.role == 'user') {
         _conversationHistory.removeLast();
       }
    } finally {
      _isGenerating = false;
      _generatingStateController.add(false);
    }
  }
  
  /// Stop/Cancel ongoing generation
  Future<void> stopGeneration() async {
    debugPrint('[ChatService] ===== Stopping generation =====');
    
    if (!_isGenerating) {
      debugPrint('[ChatService] ⚠ No generation in progress');
      return;
    }
    
    try {
      _isCancelled = true;
      debugPrint('[ChatService] Set cancellation flag');
      
      // Cancel the stream subscription
      await _generationSubscription?.cancel();
      debugPrint('[ChatService] ✓ Stream subscription cancelled');
      
      // Stop the native generation
      if (_llama != null) {
        await _llama!.stop();
        debugPrint('[ChatService] ✓ Native generation stopped');
      }
      
      _isGenerating = false;
      _generatingStateController.add(false);
      _generationSubscription = null;
      
      debugPrint('[ChatService] ✓✓✓ Generation stopped successfully');
    } catch (e) {
      debugPrint('[ChatService] ✗ Error stopping generation: $e');
      _isGenerating = false;
      _generatingStateController.add(false);
      _generationSubscription = null;
    }
    
    debugPrint('[ChatService] ===== Stop generation complete =====');
  }
  
  /// Truncate conversation history to prevent context overflow
  /// Keeps system message and most recent messages within the context limit
  /// FLLAMA-inspired improved truncation that preserves more context
  void _truncateHistoryIfNeeded(int maxHistoryLength) {
    if (_conversationHistory.length <= maxHistoryLength) {
      return; // History is within acceptable length
    }
    
    debugPrint('[ChatService] Truncating history from ${_conversationHistory.length} to $maxHistoryLength messages');
    debugPrint('[ChatService] ⚠ FLLAMA-inspired context preservation: Attempting to preserve important context');
    
    // Find and preserve the system message (should be first, but check role to be safe)
    final systemMsg = _conversationHistory.firstWhere(
      (m) => m.role == 'system',
      orElse: () => ChatMessage(role: 'system', content: _settingsService.systemMessage),
    );
    
    // Get non-system messages
    final nonSystemMessages = _conversationHistory.where((m) => m.role != 'system').toList();
    
    // FLLAMA-inspired approach: Try to preserve important messages by analyzing content
    // For now, we'll keep the most recent messages but with a larger buffer
    final recentMessages = nonSystemMessages.skip(
      nonSystemMessages.length - (maxHistoryLength - 1) // -1 to account for system message
    ).toList();
    
    _conversationHistory.clear();
    _conversationHistory.add(systemMsg); // Always keep system message
    _conversationHistory.addAll(recentMessages);
    
    debugPrint('[ChatService] ✓ History truncated to ${_conversationHistory.length} messages (including system)');
    debugPrint('[ChatService] ✓ Preserved ${recentMessages.length} recent messages for context continuity');
  }
  
  /// Clear conversation history (keeps system message)
  void clearHistory() {
    debugPrint('[ChatService] Clearing conversation history...');
    
    // Find and preserve the system message (check role to be safe)
    final systemMsg = _conversationHistory.firstWhere(
      (m) => m.role == 'system',
      orElse: () => ChatMessage(role: 'system', content: _settingsService.systemMessage),
    );
    
    _conversationHistory.clear();
    _conversationHistory.add(systemMsg);
    debugPrint('[ChatService] ✓ History cleared, system message preserved: "${systemMsg.content.substring(0, systemMsg.content.length > 30 ? 30 : systemMsg.content.length)}..."');
    
    // Reset context size to default when chat is cleared
    resetContextSizeOnChatClear();
  }
  
  /// Update context size (requires model reload to take effect)
  Future<void> updateContextSize(int newSize) async {
    if (newSize < 128 || newSize > 8192) {
      throw ArgumentError('Context size must be between 128 and 8192 tokens');
    }
    
    _contextSize = newSize;
    await _settingsService.setContextSize(newSize);
    debugPrint('[ChatService] Context size updated to: $newSize');
  }
  
  /// Update chat template
  Future<void> updateChatTemplate(String template) async {
    final supportedTemplates = [
      'auto', 'chatml', 'llama3', 'llama2', 'phi', 
      'gemma', 'gemma2', 'gemma3', 'alpaca', 'vicuna',
      'mistral', 'mixtral', 'qwq', 
      'deepseek-r1', 'deepseek-v3', 'deepseek-coder'
    ];
    
    // Allow custom templates as well
    final isCustomTemplate = customTemplateNames.contains(template);
    
    if (!supportedTemplates.contains(template.toLowerCase()) && !isCustomTemplate) {
      throw ArgumentError('Unsupported chat template: $template');
    }
    
    _chatTemplate = template.toLowerCase();
    await _settingsService.setChatTemplate(template);
    debugPrint('[ChatService] Chat template updated to: $_chatTemplate');
  }
  
  /// Update auto-unload model setting
  Future<void> updateAutoUnloadModel(bool enabled) async {
    _autoUnloadModel = enabled;
    await _settingsService.setAutoUnloadModel(enabled);
    debugPrint('[ChatService] Auto-unload model setting updated to: $enabled');
    
    // If auto-unloading is disabled, cancel any pending timer
    if (!enabled) {
      _autoUnloadTimer?.cancel();
      _autoUnloadTimer = null;
    }
  }
  
  /// Update auto-unload timeout in seconds
  Future<void> updateAutoUnloadTimeout(int seconds) async {
    if (seconds < 10) {
      throw ArgumentError('Auto-unload timeout must be at least 10 seconds');
    }
    
    _autoUnloadTimeout = seconds;
    await _settingsService.setAutoUnloadTimeout(seconds);
    debugPrint('[ChatService] Auto-unload timeout updated to: $seconds seconds');
  }
  
  /// Update TTS enabled state
  Future<void> updateTtsEnabled(bool enabled) async {
    _ttsEnabled = enabled;
    await _settingsService.setTtsEnabled(enabled);
    debugPrint('[ChatService] TTS enabled updated to: $enabled');
  }

  /// Method to reset context size to default when chat is cleared
  void resetContextSizeOnChatClear() {
    _settingsService.resetContextSizeToDefault();
    _contextSize = SettingsService.defaultContextSize;
    debugPrint('[ChatService] Context size reset to default: ${SettingsService.defaultContextSize}');
  }
  
  /// Update system message
  Future<void> updateSystemMessage(String message) async {
    // Update the conversation history with the new system message
    if (_conversationHistory.isNotEmpty && _conversationHistory.first.role == 'system') {
      _conversationHistory[0] = ChatMessage(role: 'system', content: message);
    } else {
      _conversationHistory.insert(0, ChatMessage(role: 'system', content: message));
    }
    
    // Save to settings
    await _settingsService.setSystemMessage(message);
    debugPrint('[ChatService] System message updated and saved to settings');
  }
  
  /// Get current context size
  int get contextSize => _contextSize;
  
  /// Get current chat template
  String get chatTemplate => _chatTemplate;
  
  /// Get auto-unload model setting
  bool get autoUnloadModel => _autoUnloadModel;
  
  /// Get auto-unload timeout
  int get autoUnloadTimeout => _autoUnloadTimeout;
  
  /// Get the settings service for accessing settings directly
  SettingsService get settingsService => _settingsService;

  /// Get custom template names
  List<String> get customTemplateNames => _settingsService.customTemplateNames;

  /// Get all custom templates (name -> content)
  Map<String, String> get customTemplates => _settingsService.getAllCustomTemplates();

  /// Add a custom template with content
  /// Saves to SharedPreferences and registers with native layer
  Future<void> addCustomTemplate(String name, String content) async {
    // Save to persistent storage
    await _settingsService.addCustomTemplate(name, content);
    
    // Register with native layer immediately
    try {
      await _llama?.registerCustomTemplate(name, content);
      debugPrint('[ChatService] ✓ Custom template "$name" added and registered');
    } catch (e) {
      debugPrint('[ChatService] ✗ Failed to register custom template "$name": $e');
      // Template is still saved in settings, will be registered on next app launch
    }
  }

  /// Remove a custom template
  /// Removes from SharedPreferences and unregisters from native layer
  Future<void> removeCustomTemplate(String name) async {
    // Remove from persistent storage
    await _settingsService.removeCustomTemplate(name);
    
    // Unregister from native layer
    try {
      await _llama?.unregisterCustomTemplate(name);
      debugPrint('[ChatService] ✓ Custom template "$name" removed and unregistered');
    } catch (e) {
      debugPrint('[ChatService] ✗ Failed to unregister custom template "$name": $e');
      // Template is still removed from settings
    }
  }

  /// Reset all settings to default values
  Future<void> resetSettingsToDefault() async {
    await _settingsService.resetToDefault();
    
    // Update local variables to match defaults
    _contextSize = SettingsService.defaultContextSize;
    _chatTemplate = SettingsService.defaultChatTemplate;
    _autoUnloadModel = SettingsService.defaultAutoUnloadModel;
    _autoUnloadTimeout = SettingsService.defaultAutoUnloadTimeout;
    
    debugPrint('[ChatService] Settings reset to default values');
  }
  
  /// Reset the auto-unload timer when user activity occurs
  void _resetAutoUnloadTimer() {
    if (!_autoUnloadModel) {
      return; // Don't start timer if auto-unloading is disabled
    }
    
    // Cancel any existing timer
    _autoUnloadTimer?.cancel();
    
    // Start a new timer to unload the model after the specified timeout
    _autoUnloadTimer = Timer(Duration(seconds: _autoUnloadTimeout), () async {
      if (_llama != null && !isGenerating) {
        debugPrint('[ChatService] Auto-unloading model after $_autoUnloadTimeout seconds of inactivity');
        await unloadModel();
      }
    });
    
    debugPrint('[ChatService] Auto-unload timer reset (will unload in ${_autoUnloadTimeout}s if inactive)');
  }
  
  /// Cancel auto-unload timer (when model is unloaded manually)
  void _cancelAutoUnloadTimer() {
    _autoUnloadTimer?.cancel();
    _autoUnloadTimer = null;
  }
  
  /// Unload the current model to free memory
  Future<void> unloadModel() async {
    debugPrint('[ChatService] ===== Unloading model =====');
    
    // Cancel auto-unload timer since model is being unloaded
    _cancelAutoUnloadTimer();

    // Stop detection if necessary
    if (_isGenerating || _generationSubscription != null) {
      debugPrint('[ChatService] Stopping ongoing generation before unload...');
      try {
        await stopGeneration();
        // Give the native thread a moment to cease operations completely
        await Future.delayed(const Duration(seconds: 1)); // Increased delay
      } catch (e) {
        debugPrint('[ChatService] Error stopping generation during unload: $e');
      }
    }
    
    // Safety Force Stop - even if UI thinks generation stopped, cancel subscription
    // to ensure no dart side stream is holding us back.
    if (_generationSubscription != null) {
        try {
            await _generationSubscription?.cancel();
            _generationSubscription = null;
        } catch (e) { /* ignore */ }
    }
    
    // ADDED SAFETY: Call stop() on native controller directly before dispose, just in case
    // a background job is still running despite the stream ending.
    if (_llama != null) {
        try {
            debugPrint('[ChatService] Forcing native stop before dispose...');
            await _llama!.stop();
            await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
            debugPrint('[ChatService] Error during force stop: $e');
        }
    }

    if (_llama != null) {
      debugPrint('[ChatService] Disposing LlamaController...');
      try {
        // Dispose the controller
        await _llama!.dispose(); 
        
        // Critical: Add a small delay after dispose to ensure native memory is fully released
        // before we potentially load another model or exit.
        await Future.delayed(const Duration(milliseconds: 200));
        
        _llama = null;
        debugPrint('[ChatService] ✓ Model unloaded successfully');
      } catch (e) {
        debugPrint('[ChatService] ✗ Error unloading model: $e');
        _llama = null;
        // Don't rethrow here to prevent crashing the UI flow, just log it.
        // rethrow; 
      }
    } else {
      debugPrint('[ChatService] No model to unload');
    }
    
    // Notify UI that model has been unloaded
    _modelUnloadStreamController.add(true);
    
    debugPrint('[ChatService] ===== Unload complete =====');
  }
  
  /// Clear conversation context (keeps model loaded)
  Future<void> clearContext() async {
    debugPrint('[ChatService] Clearing context...');
    if (_llama != null) {
      await _llama!.clearContext();
      debugPrint('[ChatService] ✓ Context cleared at native level');
      await _broadcastContextInfo();
    }
  }
  
  /// Get current context information
  Future<ContextInfo?> getContextInfo() async {
    if (_llama == null) return null;
    try {
      return await _llama!.getContextInfo();
    } catch (e) {
      debugPrint('[ChatService] Error getting context info: $e');
      return null;
    }
  }
  
  /// Broadcast current context info to listeners
  Future<void> _broadcastContextInfo() async {
    final info = await getContextInfo();
    if (info != null) {
      _contextInfoStreamController.add(info);
    }
  }
  
  /// Calculate safe max tokens based on current usage (80% rule)
  Future<int> _calculateSafeMaxTokens() async {
    if (_contextHelper == null || _llama == null) {
      return generationConfig.maxTokens;
    }
    
    final info = await _llama!.getContextInfo();
    return _contextHelper!.calculateSafeMaxTokens(
      info.tokensUsed,
      generationConfig.maxTokens,
    );
  }
  
  /// Handle context overflow by trimming old messages
  /// FLLAMA-inspired improved context management that preserves more conversation history
  Future<void> _handleContextOverflow() async {
    debugPrint('[ChatService] ===== Handling context overflow =====');
    debugPrint('[ChatService] ⚠⚠⚠ CONTEXT OVERFLOW DETECTED - Implementing FLLAMA-inspired context preservation');
    
    if (_llama == null) return;
    
    // FLLAMA approach: Clear context at native level but preserve conversation history meaningfully
    await _llama!.clearContext();
    debugPrint('[ChatService] ✓ Native context cleared');
    
    // FLLAMA-inspired improved history preservation
    // Instead of just keeping recent messages, try to preserve conversation flow
    // ALWAYS preserve the system message - use current settings if not found
    final systemMsg = _conversationHistory.firstWhere(
      (m) => m.role == 'system',
      orElse: () => ChatMessage(role: 'system', content: _settingsService.systemMessage),
    );
    
    debugPrint('[ChatService] ✓ System message preserved: "${systemMsg.content.substring(0, systemMsg.content.length > 50 ? 50 : systemMsg.content.length)}..."');
    
    // FLLAMA approach: Increase max messages to keep for better context preservation
    final maxToKeep = (_contextHelper?.maxMessagesToKeep ?? 10) + 5; // Increase by 5 for better preservation
    debugPrint('[ChatService] FLLAMA-inspired approach: Keeping up to $maxToKeep messages instead of ${_contextHelper?.maxMessagesToKeep ?? 10}');
    
    // Preserve more recent messages for better context continuity
    final recentMsgs = _conversationHistory
        .where((m) => m.role != 'system')
        .toList()
        .reversed
        .take(maxToKeep)
        .toList()
        .reversed
        .toList();
    
    _conversationHistory.clear();
    _conversationHistory.add(systemMsg); // ALWAYS add system message back
    _conversationHistory.addAll(recentMsgs);
    
    debugPrint('[ChatService] ✓ Trimmed to ${_conversationHistory.length} messages');
    debugPrint('[ChatService] ✓ System message: "${systemMsg.content.substring(0, systemMsg.content.length > 30 ? 30 : systemMsg.content.length)}..."');
    debugPrint('[ChatService] ✓ Preserved conversation flow with ${recentMsgs.length} recent messages');
    await _broadcastContextInfo();
    
    // FLLAMA approach: Notify user about context management
    debugPrint('[ChatService] ℹ️ FLLAMA-inspired context management: Conversation history trimmed to preserve important context');
  }
  
  Future<void> dispose() async {
    debugPrint('[ChatService] Disposing ChatService...');
    
    // Cancel auto-unload timer
    _cancelAutoUnloadTimer();
    
    await _llama?.dispose();
    await _messageStreamController.close();
    await _generatingStateController.close();
    await _contextInfoStreamController.close();
    debugPrint('[ChatService] ✓ ChatService disposed');
  }
}