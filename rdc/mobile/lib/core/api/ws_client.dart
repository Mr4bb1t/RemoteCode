/// RDC — Cliente WebSocket com reconexão automática
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../storage/secure_storage.dart';

typedef OnMessage = void Function(String message);
typedef OnError = void Function(Object error);
typedef OnDone = void Function();

class WsClient {
  final String path;
  final Map<String, String> queryParams;
  final OnMessage onMessage;
  final OnError? onError;
  final OnDone? onDone;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _intentionalClose = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  WsClient({
    required this.path,
    this.queryParams = const {},
    required this.onMessage,
    this.onError,
    this.onDone,
  });

  Future<void> connect() async {
    _intentionalClose = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';

      // Montar URL WSS
      final baseUri = Uri.parse(agentUrl);
      final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final params = Map<String, String>.from(queryParams)..['token'] = token;
      final uri = Uri(
        scheme: wsScheme,
        host: baseUri.host,
        port: baseUri.port,
        path: path,
        queryParameters: params,
      );

      // Ignorar certificado auto-assinado
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final wsConn = await WebSocket.connect(
        uri.toString(),
        customClient: httpClient,
      );

      _channel = IOWebSocketChannel(wsConn);
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        (data) => onMessage(data.toString()),
        onError: (e) {
          onError?.call(e);
          _scheduleReconnect();
        },
        onDone: () {
          if (!_intentionalClose) {
            _scheduleReconnect();
          }
          onDone?.call();
        },
        cancelOnError: false,
      );
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void send(String data) {
    _channel?.sink.add(data);
  }

  void sendJson(Map<String, dynamic> data) {
    send(jsonEncode(data));
  }

  void _scheduleReconnect() {
    if (_intentionalClose || _reconnectAttempts >= _maxReconnectAttempts) return;
    _reconnectAttempts++;
    Future.delayed(_reconnectDelay, _doConnect);
  }

  Future<void> disconnect() async {
    _intentionalClose = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  bool get isConnected => _channel != null;
}
