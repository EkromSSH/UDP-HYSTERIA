import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/server_config.dart';
import '../models/connection_info.dart';

/// Pure Dart VPN simulation — no native VpnService.
/// Just simulates connection state changes for UI prototype.
class VpnEngine {
  static StreamController<ConnectionInfo>? _controller;
  static Timer? _trafficTimer;
  static bool _isRunning = false;

  static Stream<ConnectionInfo> get statusStream =>
      _controller?.stream ??
      (StreamController<ConnectionInfo>.broadcast()..add(ConnectionInfo())).stream;

  static Future<void> initialize() async {
    _controller = StreamController<ConnectionInfo>.broadcast();
    _isRunning = false;
  }

  static Future<bool> startHysteria(ServerConfig config) async {
    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 2));

    _isRunning = true;
    _startTrafficSimulation();
    return true;
  }

  static Future<bool> startSshWs(ServerConfig config) async {
    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 2));

    _isRunning = true;
    _startTrafficSimulation();
    return true;
  }

  static Future<void> stop() async {
    _trafficTimer?.cancel();
    _trafficTimer = null;
    _isRunning = false;
  }

  static void _startTrafficSimulation() {
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // Just keep-alive — traffic is managed by ConnectionProvider.simulateTraffic
    });
  }

  static void dispose() {
    _trafficTimer?.cancel();
    _controller?.close();
    _controller = null;
    _isRunning = false;
  }
}
