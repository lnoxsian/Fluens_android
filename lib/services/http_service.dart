import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service to handle communication with ESP32 via local network polling.
class HttpService {
  Timer? _pollingTimer;
  String? _esp32Url;
  final Function(String) onMessageReceived;
  bool _isPolling = false;
  
  // Track last message ID to avoid duplicates
  String? _lastMessageId;

  // Discovery vars
  RawDatagramSocket? _discoverySocket;
  final StreamController<String> _discoveredDeviceController = StreamController<String>.broadcast();
  Stream<String> get discoveredDeviceStream => _discoveredDeviceController.stream;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  HttpService({required this.onMessageReceived});

  bool get isConnected => _pollingTimer != null && _pollingTimer!.isActive;

  /// Start scanning for ESP32 devices via UDP
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    debugPrint('[HttpService] Starting UDP scan...');

    try {
      // Listen on any available port
      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _discoverySocket!.broadcastEnabled = true;

      _discoverySocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            String message = utf8.decode(datagram.data).trim();
            debugPrint('[HttpService] Received UDP broadcast: $message from ${datagram.address.address}');
            
            // Expected format from ESP32: "FLUENS_ESP32_HERE:8080"
            if (message.startsWith('FLUENS_ESP32_HERE')) {
              // Extract port if present
              String ip = datagram.address.address;
              String port = '80'; // default
              
              if (message.contains(':')) {
                port = message.split(':')[1];
              }

              // Found valid device
              String url = '$ip:$port';
              if (ip != '127.0.0.1') {
                 debugPrint('[HttpService] Found ESP32 at $url');
                 _discoveredDeviceController.add(url);
              }
            }
          }
        }
      });

      // Send broadcast query "FLUENS_DISCOVER" to port 12345 (discovery port)
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isScanning || _discoverySocket == null) {
          timer.cancel();
          return;
        }
        
        try {
          // Send broadcast packet to 255.255.255.255
          List<int> data = utf8.encode('FLUENS_DISCOVER');
          _discoverySocket!.send(data, InternetAddress('255.255.255.255'), 12345);
        } catch (e) {
          debugPrint('[HttpService] Error sending UDP packet: $e');
        }
      });

    } catch (e) {
      debugPrint('[HttpService] Error binding UDP socket: $e');
      _isScanning = false;
    }
  }
  
  /// Stop scanning
  void stopScan() {
    _isScanning = false;
    _discoverySocket?.close();
    _discoverySocket = null;
    debugPrint('[HttpService] Stopped scanning');
  }

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
    debugPrint('[HttpService] Starting poll to $_esp32Url');
    
    // Stop existing poll if any
    disconnect();

    // Start polling every 2 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _pollEsp32();
    });
  }

  void dispose() {
    disconnect();
    stopScan();
    _discoveredDeviceController.close();
  }

  /// Stop polling
  void disconnect() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('[HttpService] Stopped polling');
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
               debugPrint('[HttpService] New message received: $message (ID: $id)');
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
      // debugPrint('[HttpService] Polling error: $e'); 
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
      debugPrint('[HttpService] Response sent back to ESP32: "${responseText.length > 20 ? '${responseText.substring(0, 20)}...' : responseText}"');
    } catch (e) {
      debugPrint('[HttpService] Error sending response: $e');
    }
  }
}
