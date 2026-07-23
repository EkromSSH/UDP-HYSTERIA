enum ProtocolType { hysteria, sshWs }

enum ConnectionStatus { disconnected, connecting, connected, error }

class ServerConfig {
  final String id;
  String name;
  String host;
  ProtocolType protocol;

  // Hysteria fields
  int hysteriaPort;
  String hysteriaPassword;
  String hysteriaObfsPassword;
  String hysteriaAlpn;
  int hysteriaUploadMbps;
  int hysteriaDownloadMbps;

  // SSH WS fields
  int sshPort;
  String sshUsername;
  String sshPassword;
  String? sshKey;
  String wsPath;
  int wsPort;

  // Common
  String? remarks;
  DateTime createdAt;
  bool isActive;

  ServerConfig({
    String? id,
    this.name = '',
    this.host = '',
    this.protocol = ProtocolType.hysteria,
    this.hysteriaPort = 36712,
    this.hysteriaPassword = '',
    this.hysteriaObfsPassword = '',
    this.hysteriaAlpn = 'h3',
    this.hysteriaUploadMbps = 100,
    this.hysteriaDownloadMbps = 100,
    this.sshPort = 22,
    this.sshUsername = 'root',
    this.sshPassword = '',
    this.sshKey,
    this.wsPath = '/',
    this.wsPort = 8080,
    this.remarks,
    DateTime? createdAt,
    this.isActive = false,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'protocol': protocol.name,
        'hysteriaPort': hysteriaPort,
        'hysteriaPassword': hysteriaPassword,
        'hysteriaObfsPassword': hysteriaObfsPassword,
        'hysteriaAlpn': hysteriaAlpn,
        'hysteriaUploadMbps': hysteriaUploadMbps,
        'hysteriaDownloadMbps': hysteriaDownloadMbps,
        'sshPort': sshPort,
        'sshUsername': sshUsername,
        'sshPassword': sshPassword,
        'wsPath': wsPath,
        'wsPort': wsPort,
        'remarks': remarks,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      protocol: json['protocol'] == 'sshWs'
          ? ProtocolType.sshWs
          : ProtocolType.hysteria,
      hysteriaPort: json['hysteriaPort'] as int? ?? 36712,
      hysteriaPassword: json['hysteriaPassword'] as String? ?? '',
      hysteriaObfsPassword: json['hysteriaObfsPassword'] as String? ?? '',
      hysteriaAlpn: json['hysteriaAlpn'] as String? ?? 'h3',
      hysteriaUploadMbps: json['hysteriaUploadMbps'] as int? ?? 100,
      hysteriaDownloadMbps: json['hysteriaDownloadMbps'] as int? ?? 100,
      sshPort: json['sshPort'] as int? ?? 22,
      sshUsername: json['sshUsername'] as String? ?? 'root',
      sshPassword: json['sshPassword'] as String? ?? '',
      wsPath: json['wsPath'] as String? ?? '/',
      wsPort: json['wsPort'] as int? ?? 8080,
      remarks: json['remarks'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  String get displayProtocol {
    switch (protocol) {
      case ProtocolType.hysteria:
        return 'Hysteria';
      case ProtocolType.sshWs:
        return 'SSH WS';
    }
  }

  ServerConfig copy() => ServerConfig.fromJson(toJson());
}
