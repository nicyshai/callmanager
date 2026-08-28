import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logger.dart';

enum SocketConnectionState { disconnected, connecting, connected }

/// In-app local WebSocket Server to simulate the signaling server
class SignalingServer {
  HttpServer? _server;
  final List<WebSocket> _connections = [];
  final Map<String, WebSocket> _userSocketMap = {};

  bool get isRunning => _server != null;

  Future<void> start({int port = 3000}) async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      AppLogger.socket("Signaling Server started on ws://localhost:$port");

      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleConnection(socket);
          });
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      }, onError: (err) {
        AppLogger.error("Signaling Server listening error: $err");
      });
    } catch (e) {
      AppLogger.error("Failed to start Signaling Server: $e");
    }
  }

  void _handleConnection(WebSocket socket) {
    _connections.add(socket);
    AppLogger.socket("Server: Client connected (total: ${_connections.length})");

    String? registeredUserId;

    socket.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          final event = data['event'] as String?;
          final from = data['from'] as String?;
          final to = data['to'] as String?;

          if (event == 'register' && from != null) {
            registeredUserId = from;
            _userSocketMap[from] = socket;
            AppLogger.socket("Server: Client registered as '$from'");
            socket.add(jsonEncode({'event': 'registered', 'userId': from}));
            return;
          }

          // Forward to target user
          if (to != null && _userSocketMap.containsKey(to)) {
            final targetSocket = _userSocketMap[to]!;
            if (targetSocket.readyState == WebSocket.open) {
              targetSocket.add(message);
              AppLogger.socket("Server: Forwarded '$event' from '$from' to '$to'");
            } else {
              AppLogger.error("Server: Cannot forward to '$to' (socket closed)");
              socket.add(jsonEncode({
                'event': 'error',
                'message': 'Recipient offline',
                'call_id': data['call_id'] ?? ''
              }));
            }
          } else {
            AppLogger.socket("Server: Target '$to' is offline/not registered");
          }
        } catch (e) {
          AppLogger.error("Server message parsing error: $e");
        }
      },
      onDone: () {
        _connections.remove(socket);
        if (registeredUserId != null) {
          _userSocketMap.remove(registeredUserId);
          AppLogger.socket("Server: Client '$registeredUserId' disconnected");
        }
      },
      onError: (err) {
        _connections.remove(socket);
        if (registeredUserId != null) {
          _userSocketMap.remove(registeredUserId);
          AppLogger.socket("Server: Client '$registeredUserId' error: $err");
        }
      },
    );
  }

  Future<void> stop() async {
    for (final socket in List.from(_connections)) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _connections.clear();
    _userSocketMap.clear();
    await _server?.close(force: true);
    _server = null;
    AppLogger.socket("Signaling Server stopped");
  }
}

/// Signaling Client connecting to the local server
class SignalingClient {
  final String userId;
  WebSocket? _socket;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<SocketConnectionState>.broadcast();
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  final int _port;

  SignalingClient(this.userId, {int port = 3000}) : _port = port;

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<SocketConnectionState> get onConnectionStateChanged => _stateController.stream;
  SocketConnectionState get connectionState => _connectionState;

  void _updateState(SocketConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _stateController.add(newState);
      AppLogger.socket("Client '$userId': Connection state is ${newState.name}");
    }
  }

  Future<void> connect() async {
    if (_connectionState == SocketConnectionState.connected ||
        _connectionState == SocketConnectionState.connecting) {
      return;
    }

    _shouldReconnect = true;
    _updateState(SocketConnectionState.connecting);

    try {
      final wsUrl = 'ws://127.0.0.1:$_port';
      AppLogger.socket("Client '$userId': Connecting to $wsUrl...");
      _socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));

      _updateState(SocketConnectionState.connected);
      _reconnectTimer?.cancel();

      // Register connection
      _sendRaw({
        'event': 'register',
        'from': userId,
      });

      _socket!.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _messageController.add(data);
          } catch (e) {
            AppLogger.error("Client '$userId' message decode failed: $e");
          }
        },
        onDone: () {
          AppLogger.socket("Client '$userId' connection closed");
          _handleDisconnect();
        },
        onError: (err) {
          AppLogger.error("Client '$userId' connection error: $err");
          _handleDisconnect();
        },
      );
    } catch (e) {
      AppLogger.error("Client '$userId' connection failed: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _socket = null;
    _updateState(SocketConnectionState.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_shouldReconnect) {
        AppLogger.socket("Client '$userId' attempting auto-reconnect...");
        connect();
      }
    });
  }

  void disconnect() {
    AppLogger.socket("Client '$userId' disconnecting...");
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _updateState(SocketConnectionState.disconnected);
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(data));
    } else {
      AppLogger.error("Client '$userId' cannot send message. Socket not connected.");
    }
  }

  void sendEvent({
    required String to,
    required String event,
    required String callId,
    Map<String, dynamic>? extra,
  }) {
    final payload = {
      'event': event,
      'from': userId,
      'to': to,
      'call_id': callId,
      if (extra != null) ...extra,
    };
    _sendRaw(payload);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}

/// Provider for the single Signaling Server instance
final signalingServerProvider = Provider<SignalingServer>((ref) {
  final server = SignalingServer();
  ref.onDispose(() async {
    await server.stop();
  });
  return server;
});

/// Provider for User 001 (This Device) signaling client
final localSignalingClientProvider = Provider<SignalingClient>((ref) {
  final client = SignalingClient('user_001');
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

/// Provider for User 002 (Remote Simulation) signaling client
final remoteSignalingClientProvider = Provider<SignalingClient>((ref) {
  final client = SignalingClient('user_002');
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});
