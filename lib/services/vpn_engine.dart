import 'dart:async';
import 'package:flutter/services.dart';
import '../models/server_config.dart';
import '../models/connection_info.dart';

/// Bridge between Flutter and native Android VpnService + SSH tunnel.
class VpnEngine {
  static const _channel = MethodChannel('com.ekromssh.app/vpn');
  static StreamController<ConnectionInfo>? _controller;

  static Stream<ConnectionInfo> get statusStream =>
      _controller?.stream ?? const Stream.empty();

  static Future<void> initialize() async {
    _controller = StreamController<ConnectionInfo>.broadcast();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onStatusChanged') {
      final args = call.arguments as Map<dynamic, dynamic>;
      final status = args['status'] as String? ?? 'disconnected';
      final bytesSent = args['bytesSent'] as int? ?? 0;
      final bytesReceived = args['bytesReceived'] as int? ?? 0;
      final errorMessage = args['errorMessage'] as String?;

      ConnectionStatus connStatus;
      switch (status) {
        case 'connecting':
          connStatus = ConnectionStatus.connecting;
          break;
        case 'connected':
          connStatus = ConnectionStatus.connected;
          break;
        case 'error':
          connStatus = ConnectionStatus.error;
          break;
        default:
          connStatus = ConnectionStatus.disconnected;
      }

      _controller?.add(ConnectionInfo(
        status: connStatus,
        bytesSent: bytesSent,
        bytesReceived: bytesReceived,
        errorMessage: errorMessage ?? '',
      ));
    }
  }

  static Future<bool> startSshWs(ServerConfig config) async {
    try {
      final result = await _channel.invokeMethod<bool>('startSshWs', {
        'host': config.host,
        'sshPort': config.sshPort,
        'username': config.sshUsername,
        'password': config.sshPassword,
        'wsPort': config.wsPort,
        'wsPath': config.wsPath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> startHysteria(ServerConfig config) async {
    try {
      final result = await _channel.invokeMethod<bool>('startHysteria', {
        'host': config.host,
        'port': config.hysteriaPort,
        'auth': config.hysteriaAuth,
        'obfsPassword': config.hysteriaObfsPassword,
        'upSpeed': config.hysteriaUpSpeed,
        'downSpeed': config.hysteriaDownSpeed,
        'udpWindow': config.hysteriaUdpWindow,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopVpn');
    } catch (_) {}
  }

  static Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static void dispose() {
    _controller?.close();
    _controller = null;
  }
}
