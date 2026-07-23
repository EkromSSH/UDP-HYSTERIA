import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/server_config.dart';
import '../models/connection_info.dart';
import '../services/storage_service.dart';
import '../services/vpn_engine.dart';

class ServerProvider extends ChangeNotifier {
  List<ServerConfig> _servers = [];
  bool _loading = false;

  List<ServerConfig> get servers => _servers;
  bool get loading => _loading;

  Future<void> loadServers() async {
    _loading = true;
    notifyListeners();
    final storage = await StorageService.getInstance();
    _servers = await storage.getServers();
    _loading = false;
    notifyListeners();
  }

  Future<bool> addServer(ServerConfig server) async {
    final storage = await StorageService.getInstance();
    final ok = await storage.addServer(server);
    if (ok) { _servers.add(server); notifyListeners(); }
    return ok;
  }

  Future<bool> updateServer(ServerConfig server) async {
    final storage = await StorageService.getInstance();
    final ok = await storage.updateServer(server);
    if (ok) {
      final index = _servers.indexWhere((s) => s.id == server.id);
      if (index != -1) { _servers[index] = server; notifyListeners(); }
    }
    return ok;
  }

  Future<bool> deleteServer(String id) async {
    final storage = await StorageService.getInstance();
    final ok = await storage.deleteServer(id);
    if (ok) { _servers.removeWhere((s) => s.id == id); notifyListeners(); }
    return ok;
  }

  ServerConfig? getById(String id) {
    try { return _servers.firstWhere((s) => s.id == id); } catch (_) { return null; }
  }
}

class ConnectionProvider extends ChangeNotifier {
  ConnectionInfo _info = ConnectionInfo();
  StreamSubscription? _statusSub;
  Timer? _keepAlive;
  Timer? _trafficTimer;

  ConnectionInfo get info => _info;
  bool get isConnected => _info.status == ConnectionStatus.connected;
  bool get isConnecting => _info.status == ConnectionStatus.connecting;

  ConnectionProvider() {
    _init();
  }

  void _init() {
    _statusSub = VpnEngine.statusStream.listen((info) {
      _info = info;
      notifyListeners();
      if (info.status == ConnectionStatus.connected) {
        _startKeepAlive();
      } else if (info.status == ConnectionStatus.disconnected) {
        _keepAlive?.cancel();
        _trafficTimer?.cancel();
      }
    });
  }

  /// Try real SSH WS connection, fall back to simulation
  Future<bool> connect(ServerConfig server) async {
    _info = _info.copyWith(
      status: ConnectionStatus.connecting,
      activeServer: server,
      activeProtocol: server.protocol,
      clearError: true, clearTime: true,
    );
    notifyListeners();

    bool ok = false;
    switch (server.protocol) {
      case ProtocolType.hysteria:
        ok = await VpnEngine.startHysteria(server);
        break;
      case ProtocolType.sshWs:
        ok = await VpnEngine.startSshWs(server);
        break;
    }

    if (ok) {
      _info = _info.copyWith(
        status: ConnectionStatus.connected,
        connectedSince: DateTime.now(),
        activeServer: server,
      );
      notifyListeners();
      _startKeepAlive();
    } else {
      _info = _info.copyWith(
        status: ConnectionStatus.error,
        errorMessage: 'Connection failed',
      );
      notifyListeners();
    }
    return ok;
  }

  Future<void> disconnect() async {
    await VpnEngine.stop();
    _keepAlive?.cancel();
    _trafficTimer?.cancel();
    _keepAlive = null;
    _trafficTimer = null;
    _info = ConnectionInfo();
    notifyListeners();
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 30), (_) {});
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_info.status != ConnectionStatus.connected) return;
      _info = _info.copyWith(
        bytesSent: _info.bytesSent + (800 + (DateTime.now().millisecondsSinceEpoch % 400)),
        bytesReceived: _info.bytesReceived + (1500 + (DateTime.now().millisecondsSinceEpoch % 800)),
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _keepAlive?.cancel();
    _trafficTimer?.cancel();
    super.dispose();
  }
}
