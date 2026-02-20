import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    // Default settings
    await _flutterTts.setLanguage("en-US"); 
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    // Attempt to await speak completion on iOS and Android
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
      debugPrint("[TtsService] Speaking started");
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      debugPrint("[TtsService] Speaking completed");
    });
    
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      debugPrint("[TtsService] Error: $msg");
    });
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      // Clean up text if needed (remove emojis or weird chars if they cause issues, 
      // but usually TTS handles them or ignores them)
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("[TtsService] Error speaking: $e");
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
    } catch (e) {
      debugPrint("[TtsService] Error stopping: $e");
    }
  }
}
