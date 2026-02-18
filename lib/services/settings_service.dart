import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app settings and preferences
class SettingsService {
  static const String _keyContextSize = 'context_size';
  static const String _keyChatTemplate = 'chat_template';
  static const String _keyAutoUnloadModel = 'auto_unload_model';
  static const String _keyAutoUnloadTimeout = 'auto_unload_timeout';
  static const String _keySystemMessage = 'system_message';
  static const String _keyCustomTemplates = 'custom_templates';
  static const String _keyThinkingMode = 'thinking_mode';

  static const int defaultContextSize = 2048;
  static const String defaultChatTemplate = 'auto';
  static const bool defaultAutoUnloadModel = true; // Changed to true (enabled by default)
  static const int defaultAutoUnloadTimeout = 60; // 60 seconds
  static const String defaultSystemMessage = 'You are a helpful AI assistant. Be concise and friendly.';
  static const bool defaultThinkingMode = false; // Thinking mode disabled by default

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Context Size Settings
  int get contextSize => _prefs?.getInt(_keyContextSize) ?? defaultContextSize;
  
  Future<bool> setContextSize(int size) {
    // Validate context size is within acceptable range (128 to 8192 tokens)
    if (size < 128 || size > 8192) {
      throw ArgumentError('Context size must be between 128 and 8192 tokens');
    }
    return _prefs!.setInt(_keyContextSize, size);
  }

  /// Chat Template Settings
  String get chatTemplate => _prefs?.getString(_keyChatTemplate) ?? defaultChatTemplate;

  Future<bool> setChatTemplate(String template) {
    // Validate template is supported (built-in or custom)
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
    return _prefs!.setString(_keyChatTemplate, template.toLowerCase());
  }

  /// Auto Unload Model Settings
  bool get autoUnloadModel => _prefs?.getBool(_keyAutoUnloadModel) ?? defaultAutoUnloadModel;

  Future<bool> setAutoUnloadModel(bool enabled) {
    return _prefs!.setBool(_keyAutoUnloadModel, enabled);
  }

  int get autoUnloadTimeout => _prefs?.getInt(_keyAutoUnloadTimeout) ?? defaultAutoUnloadTimeout;

  Future<bool> setAutoUnloadTimeout(int seconds) {
    if (seconds < 10) {
      throw ArgumentError('Auto-unload timeout must be at least 10 seconds');
    }
    return _prefs!.setInt(_keyAutoUnloadTimeout, seconds);
  }

  /// System Message Settings
  String get systemMessage => _prefs?.getString(_keySystemMessage) ?? defaultSystemMessage;

  Future<bool> setSystemMessage(String message) {
    return _prefs!.setString(_keySystemMessage, message);
  }

  /// Thinking Mode Settings (for reasoning models like QwQ, DeepSeek-R1)
  bool get thinkingMode => _prefs?.getBool(_keyThinkingMode) ?? defaultThinkingMode;

  Future<bool> setThinkingMode(bool enabled) {
    return _prefs!.setBool(_keyThinkingMode, enabled);
  }

  /// Custom template management - stores template names only (content stored separately)
  List<String> get customTemplateNames {
    final names = _prefs?.getStringList(_keyCustomTemplates) ?? [];
    return List.from(names);
  }

  Future<bool> setCustomTemplateNames(List<String> names) {
    return _prefs!.setStringList(_keyCustomTemplates, names);
  }

  /// Get content for a specific custom template
  String getCustomTemplateContent(String name) {
    return _prefs?.getString('${_keyCustomTemplates}_$name') ?? '';
  }

  /// Set content for a specific custom template
  Future<bool> setCustomTemplateContent(String name, String content) {
    return _prefs!.setString('${_keyCustomTemplates}_$name', content);
  }

  /// Get all custom templates with their content
  Map<String, String> getAllCustomTemplates() {
    final names = customTemplateNames;
    final result = <String, String>{};
    for (final name in names) {
      result[name] = getCustomTemplateContent(name);
    }
    return result;
  }

  /// Add a custom template with content
  Future<void> addCustomTemplate(String name, String content) async {
    final currentNames = customTemplateNames;
    if (!currentNames.contains(name)) {
      currentNames.add(name);
      await setCustomTemplateNames(currentNames);
    }
    await setCustomTemplateContent(name, content);
  }

  /// Remove a custom template
  Future<void> removeCustomTemplate(String name) async {
    final currentNames = customTemplateNames;
    currentNames.remove(name);
    await setCustomTemplateNames(currentNames);
    // Remove the content as well
    await _prefs!.remove('${_keyCustomTemplates}_$name');
  }

  /// Reset context size to default (used when chat is cleared)
  Future<void> resetContextSizeToDefault() async {
    await _prefs!.setInt(_keyContextSize, defaultContextSize);
  }

  /// Get all settings as a map
  Map<String, dynamic> getAllSettings() {
    return {
      'contextSize': contextSize,
      'chatTemplate': chatTemplate,
      'autoUnloadModel': autoUnloadModel,
      'autoUnloadTimeout': autoUnloadTimeout,
      'systemMessage': systemMessage,
      'customTemplates': getAllCustomTemplates(),
    };
  }

  /// Reset all settings to default values
  Future<void> resetToDefault() async {
    await _prefs!.setInt(_keyContextSize, defaultContextSize);
    await _prefs!.setString(_keyChatTemplate, defaultChatTemplate);
    await _prefs!.setBool(_keyAutoUnloadModel, defaultAutoUnloadModel);
    await _prefs!.setInt(_keyAutoUnloadTimeout, defaultAutoUnloadTimeout);
    await _prefs!.setString(_keySystemMessage, defaultSystemMessage);
    await _prefs!.setBool(_keyThinkingMode, defaultThinkingMode);
    await _prefs!.setStringList(_keyCustomTemplates, []); // Clear custom templates
  }
}