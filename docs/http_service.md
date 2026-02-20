# HttpService

**File:** [`lib/services/http_service.dart`](../lib/services/http_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`HttpService` manages all communication between the Fluens app and the Fluens ESP32 hardware over a local Wi-Fi network. It has two distinct operational phases:

1. **Discovery** — UDP broadcast-based auto-discovery to locate the ESP32 without manual IP entry.
2. **Polling** — Periodic HTTP polling to receive messages from the ESP32 and send AI responses back.

---

## Class Definition

```dart
class HttpService {
  final Function(String) onMessageReceived;

  // State
  bool get isConnected;   // true when polling timer is active
  bool get isScanning;    // true during UDP discovery

  // Stream
  Stream<String> get discoveredDeviceStream; // emits "ip:port" strings
}
```

`onMessageReceived` is a required callback passed at construction. It is invoked every time a new, non-duplicate message arrives from the ESP32.

---

## UDP Auto-Discovery

### Protocol

```
App ──► [UDP broadcast 255.255.255.255:12345]  "FLUENS_DISCOVER"
ESP32 ◄── receives packet
ESP32 ──► [UDP unicast back to app]  "FLUENS_ESP32_HERE:<http_port>"
App ◄── receives response, extracts IP + port
```

The discovery port (`12345`) is fixed on both the app and ESP32 firmware.

### `startScan()`

```dart
Future<void> startScan()
```

1. Binds a `RawDatagramSocket` to `InternetAddress.anyIPv4` on any available port with `broadcastEnabled = true`.
2. Listens for incoming datagrams. On receiving a packet starting with `"FLUENS_ESP32_HERE"`, extracts the IP from `datagram.address.address` and the port from the message payload (defaults to `80`).
3. Emits the discovered `"ip:port"` string on `discoveredDeviceStream`.
4. Starts a `Timer.periodic` every 1 second that sends `"FLUENS_DISCOVER"` to `255.255.255.255:12345`.
5. Ignores `127.0.0.1` to avoid loopback false-positives.

> **Note:** Scanning is idempotent — calling `startScan()` when already scanning is a no-op.

### `stopScan()`

Cancels the periodic timer, closes and nullifies the socket, and sets `_isScanning = false`.

### `discoveredDeviceStream`

A broadcast `Stream<String>`. The UI listens to this stream to auto-populate the IP field and optionally auto-connect.

---

## HTTP Polling

### `connect(String url)`

```dart
void connect(String url)
```

Normalises the URL (adds `http://` if missing, strips trailing `/`), stores it in `_esp32Url`, and starts a `Timer.periodic` with a 2-second interval that calls `_pollEsp32()`.

Calls `disconnect()` first if a previous polling timer is active.

### `disconnect()`

Cancels the polling timer and sets it to `null`.

### `_pollEsp32()` (private)

```dart
Future<void> _pollEsp32()
```

A simple mutex (`_isPolling`) ensures concurrent poll cycles are skipped.

**Steps:**
1. `GET <esp32Url>/messages` with a 2-second timeout.
2. On HTTP 200, parses the JSON body.
3. Expects the format:

```json
{ "message": "Hello from ESP32", "id": "abc123" }
```

4. Compares `id` to `_lastMessageId` — only forwards new messages to the `onMessageReceived` callback.
5. Falls back to `message.hashCode.toString()` as the ID if the `id` field is absent.
6. All errors (network, JSON parse) are silently swallowed to prevent polling storm behaviour on unreachable hardware.

### `sendResponse(String responseText)`

```dart
Future<void> sendResponse(String responseText)
```

Sends the AI response back to the ESP32 after generation:

```
POST <esp32Url>/response
Content-Type: application/json

{ "response": "The AI reply..." }
```

Errors are logged but not rethrown. Called by the UI layer when a `"\n"` end-of-response sentinel is detected on `ChatService.messageStream`.

---

## State Properties

| Property | Type | Description |
|---|---|---|
| `isConnected` | `bool` | `true` when `_pollingTimer` is non-null and active |
| `isScanning` | `bool` | `true` when UDP discovery is in progress |

---

## Lifecycle

```dart
// Construction
final httpService = HttpService(onMessageReceived: (msg) { /* ... */ });

// Discovery
await httpService.startScan();
httpService.discoveredDeviceStream.listen((url) {
  httpService.stopScan();
  httpService.connect(url);
});

// When done
httpService.dispose();
```

### `dispose()`

Calls `disconnect()` + `stopScan()` and closes the `discoveredDeviceStream` controller. Must be called in `State.dispose()` to prevent resource leaks.

---

## ESP32 API Contract

The app expects the ESP32 (or mock server) to expose:

| Endpoint | Method | Request Body | Response Body |
|---|---|---|---|
| `/messages` | `GET` | — | `{}` (empty) or `{"message": "...", "id": "..."}` |
| `/response` | `POST` | `{"response": "..."}` | Any / ignored |

The discovery protocol listens on UDP port `12345` for `"FLUENS_DISCOVER"` and responds with `"FLUENS_ESP32_HERE:<http_port>"`.

---

## Mock Server

During development, use the Python mock server to simulate the ESP32:

```bash
cd scripts
pip install -r requirements.txt
python esp32_mock_server.py --port 8080
```

See [`scripts/esp32_mock_server.py`](../scripts/esp32_mock_server.py) for implementation details.

---

## Related Docs

- [ChatService](chat_service.md) — instantiates `HttpService` and handles `onMessageReceived`
- [Main / ChatScreen UI](main.md) — calls `connect()`, `disconnect()`, and `sendResponse()`
