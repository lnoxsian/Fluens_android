import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class GroqService {
  final SettingsService _settingsService;
  final http.Client _client = http.Client();
  
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  
  GroqService({SettingsService? settingsService}) 
      : _settingsService = settingsService ?? SettingsService();

  Future<void> initialize() async {
    // Ensure settings are initialized if we created our own instance
    // Ideally this is passed in already initialized
  }

  Stream<String> sendMessageStream(
    String message, 
    List<Map<String, String>> history, 
    {String? systemMessage}
  ) async* {
    final apiKey = _settingsService.groqApiKey;
    if (apiKey.isEmpty) {
      throw Exception('Groq API Key not set. Please adding it in Settings.');
    }

    // Prepare messages
    final messages = <Map<String, String>>[];
    
    if (systemMessage != null && systemMessage.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemMessage});
    }
    
    // Add history (ensure proper format)
    messages.addAll(history);
    
    // Add current message
    messages.add({'role': 'user', 'content': message});

    final request = http.Request('POST', Uri.parse(_baseUrl));
    request.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    });
    
    request.body = jsonEncode({
      'model': 'llama-3.3-70b-versatile',
      'messages': messages,
      'stream': true,
      'temperature': 1,
      'max_completion_tokens': 1024,
      'top_p': 1,
    });

    try {
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        try {
          final errorJson = jsonDecode(body);
          throw Exception(errorJson['error']['message'] ?? body);
        } catch (_) {
          throw Exception('Groq API Error: ${response.statusCode} - $body');
        }
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') break;
          
          try {
            final json = jsonDecode(data);
            final content = json['choices'][0]['delta']['content'];
            if (content != null) {
              yield content;
            }
          } catch (e) {
            // Ignore parse errors for partial chunks
          }
        }
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }
  
  /// Get available models from Groq
  Future<List<String>> getModels() async {
    final apiKey = _settingsService.groqApiKey;
    if (apiKey.isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> models = data['data'];
        return models.map((m) => m['id'] as String).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
