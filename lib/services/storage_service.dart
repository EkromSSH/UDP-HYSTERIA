import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

class StorageService {
  static const String _serversKey = 'udp_hysteria_servers';
  static const String _settingsKey = 'udp_hysteria_settings';
  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  // ─── Servers ───────────────────────────────────────────────

  Future<List<ServerConfig>> getServers() async {
    final jsonStr = _prefs.getString(_serversKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((e) => ServerConfig.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveServers(List<ServerConfig> servers) async {
    final jsonStr = jsonEncode(servers.map((s) => s.toJson()).toList());
    await _prefs.setString(_serversKey, jsonStr);
  }

  Future<bool> addServer(ServerConfig server) async {
    final servers = await getServers();
    servers.add(server);
    await saveServers(servers);
    return true;
  }

  Future<bool> updateServer(ServerConfig server) async {
    final servers = await getServers();
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index == -1) return false;
    servers[index] = server;
    await saveServers(servers);
    return true;
  }

  Future<bool> deleteServer(String id) async {
    final servers = await getServers();
    servers.removeWhere((s) => s.id == id);
    await saveServers(servers);
    return true;
  }

  // ─── Settings ─────────────────────────────────────────────

  Future<bool> getAutoConnect() async {
    return _prefs.getBool('auto_connect') ?? false;
  }

  Future<void> setAutoConnect(bool value) async {
    await _prefs.setBool('auto_connect', value);
  }

  Future<bool> getStartOnBoot() async {
    return _prefs.getBool('start_on_boot') ?? false;
  }

  Future<void> setStartOnBoot(bool value) async {
    await _prefs.setBool('start_on_boot', value);
  }

  Future<String?> getLastServerId() async {
    return _prefs.getString('last_server_id');
  }

  Future<void> setLastServerId(String? id) async {
    if (id != null) {
      await _prefs.setString('last_server_id', id);
    } else {
      await _prefs.remove('last_server_id');
    }
  }

  // ─── Config Export/Import ─────────────────────────────────

  Future<String> exportConfigs() async {
    final servers = await getServers();
    final export = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'EkromSSH VPN',
      'servers': servers.map((s) => s.toJson()).toList(),
    };
    return jsonEncode(export);
  }

  Future<List<ServerConfig>> importConfig(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map || data['servers'] is! List) return [];
      final list = data['servers'] as List;
      return list
          .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
