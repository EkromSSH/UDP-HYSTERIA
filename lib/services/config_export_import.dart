import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/server_config.dart';

class ConfigExportImport {
  /// Export servers to a file
  static Future<String> exportToFile(List<ServerConfig> servers) async {
    final export = {
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'EkromSSH',
      'website': 'https://github.com/EkromSSH/UDP-HYSTERIA',
      'servers': servers.map((s) => s.toJson()).toList(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ekromssh_config_$timestamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(export),
    );
    return file.path;
  }

  /// Import servers from JSON string
  static Future<List<ServerConfig>> importFromString(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final serversRaw = data['servers'];
      if (serversRaw is! List) return [];

      return serversRaw
          .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Share config as text (for clipboard or share)
  static String exportAsText(List<ServerConfig> servers) {
    final buffer = StringBuffer();
    buffer.writeln('=== EkromSSH Config ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('');

    for (final server in servers) {
      buffer.writeln('── ${server.name} ──');
      buffer.writeln('Host: ${server.host}');
      buffer.writeln('Protocol: ${server.displayProtocol}');

      if (server.protocol == ProtocolType.hysteria) {
        buffer.writeln('Port: ${server.hysteriaPort}');
        buffer.writeln('Password: ${server.hysteriaPassword}');
        if (server.hysteriaObfsPassword.isNotEmpty) {
          buffer.writeln('Obfs: ${server.hysteriaObfsPassword}');
        }
        buffer.writeln('ALPN: ${server.hysteriaAlpn}');
      } else {
        buffer.writeln('SSH Port: ${server.sshPort}');
        buffer.writeln('Username: ${server.sshUsername}');
        buffer.writeln('WS Port: ${server.wsPort}');
        buffer.writeln('WS Path: ${server.wsPath}');
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }
}
