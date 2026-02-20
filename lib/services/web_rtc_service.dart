import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service to handle communication with ESP32 via local network polling.
/// Despite the file name, this service now uses HTTP polling instead of WebRTC
/// based on the user's requirements.
class WebRtcService {
  Timer? _pollingTimer;
  String? _esp32Url;
  final Function(String) onMessageReceived;
  bool _isPolling = false;
  
  // Track last message ID to avoid duplicates
  String? _lastMessageId;

  WebRtcService({required this.onMessageReceived});

  bool get isConnected => _pollingTimer != null && _pollingTimer!.isActive;

  /// Start polling the ESP32 for messages
  void connect(String url) {
    // Ensure URL has http scheme and no trailing slash
    if (!url.startsWith('http')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    _esp32Url = url;
    debugPrint('[WebRtcService] Starting poll to $_esp32Url');
    
    // Stop existing poll if any
    disconnect();

    // Start polling every 2 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _pollEsp32();
    });
  }

  /// Stop polling
  void disconnect() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('[WebRtcService] Stopped polling');
  }

  Future<void> _pollEsp32() async {
    if (_esp32Url == null || _isPolling) return; // simple mutex

    _isPolling = true;
    try {
      // Endpoint: /messages
      final uri = Uri.parse('$_esp32Url/messages');
      
      // Use short timeout for polling
      final response = await http.get(uri).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.isEmpty) return;

        try {
          final data = jsonDecode(body);
          
          // Check for message content
          // Support {"message": "Hello", "id": "123"} or simple {"message": "Hello"}
          if (data is Map && data.containsKey('message')) {
            final message = data['message'].toString();
            final id = data['id']?.toString() ?? message.hashCode.toString(); // Fallback ID

            // Only notify if new message
            if (_lastMessageId != id && message.isNotEmpty) {
               debugPrint('[WebRtcService] New message received: $message (ID: $id)');
               _lastMessageId = id;
               onMessageReceived(message);
            }
          }
        } catch (e) {
          // Silent catch for JSON errors during polling
        }
      }
    } catch (e) {
      // Silent catch for connection errors during polling
      // debugPrint('[WebRtcService] Polling error: $e'); 
    } finally {
      // Always release lock
      _isPolling = false;
    }
  }

  /// Send a response back to ESP32 (optional)
  Future<void> sendResponse(String responseText) async {
    if (_esp32Url == null) return;
    try {
      final uri = Uri.parse('$_esp32Url/response');
      await http.post(
        uri, 
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'response': responseText}),
      );
      debugPrint('[WebRtcService] Response sent back to ESP32: "${responseText.length > 20 ? responseText.substring(0, 20) + '...' : responseText}"');
    } catch (e) {
      debugPrint('[WebRtcService] Error sending response: $e');
    }
  }
}
