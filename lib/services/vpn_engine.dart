import 'dart:async';
import 'package:flutter/services.dart';
import '../models/server_config.dart';
import '../models/connection_info.dart';

class VpnEngine {
  static const String _channelName = 'com.ekromssh.app/vpn';
  static const MethodChannel _channel = MethodChannel(_channelName);

  static StreamController<ConnectionInfo>? _statusController;
  static StreamSubscription? _eventSub;

  static Stream<ConnectionInfo> get statusStream {
    _statusController ??= StreamController<ConnectionInfo>.broadcast();
    return _statusController!.stream;
  }

  static void _emitStatus(ConnectionInfo info) {
    _statusController?.add(info);
  }

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onStatusChanged':
          final args = call.arguments as Map?;
          if (args != null) {
            final status = ConnectionStatus.values.firstWhere(
              (e) => e.name == args['status'],
              orElse: () => ConnectionStatus.disconnected,
            );
            _emitStatus(ConnectionInfo(
              status: status,
              bytesSent: args['bytesSent'] as int? ?? 0,
              bytesReceived: args['bytesReceived'] as int? ?? 0,
              errorMessage: args['errorMessage'] as String?,
            ));
          }
          break;
        case 'onTrafficUpdate':
          final args = call.arguments as Map?;
          if (args != null) {
            _emitStatus(ConnectionInfo(
              status: ConnectionStatus.connected,
              bytesSent: args['bytesSent'] as int? ?? 0,
              bytesReceived: args['bytesReceived'] as int? ?? 0,
            ));
          }
          break;
      }
    });
  }

  /// Start Hysteria VPN connection
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
    } on PlatformException catch (e) {
      _emitStatus(ConnectionInfo(
        status: ConnectionStatus.error,
        errorMessage: e.message,
      ));
      return false;
    }
  }

  /// Start SSH WebSocket VPN connection
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
    } on PlatformException catch (e) {
      _emitStatus(ConnectionInfo(
        status: ConnectionStatus.error,
        errorMessage: e.message,
      ));
      return false;
    }
  }

  /// Stop VPN connection
  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopVpn');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Check if VPN is running
  static Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static void dispose() {
    _statusController?.close();
    _statusController = null;
    _eventSub?.cancel();
  }
}
