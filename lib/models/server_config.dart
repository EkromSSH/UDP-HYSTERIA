enum ProtocolType { hysteria, sshWs }

enum ConnectionStatus { disconnected, connecting, connected, error }

class ServerConfig {
  final String id;
  String name;
  String host;
  ProtocolType protocol;

  // Hysteria fields (matching the user's config format)
  String hysteriaPort;           // port range e.g. "10000-50000"
  String hysteriaAuth;           // AUTH: username:password e.g. "ida:ida"
  String hysteriaObfsPassword;   // OBFS
  int hysteriaUpSpeed;           // UP SPEED (Mbps)
  int hysteriaDownSpeed;         // DOWN SPEED (Mbps)
  int hysteriaUdpWindow;         // UDP Window

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
    this.hysteriaPort = '36712',
    this.hysteriaAuth = '',
    this.hysteriaObfsPassword = '',
    this.hysteriaUpSpeed = 100,
    this.hysteriaDownSpeed = 100,
    this.hysteriaUdpWindow = 196608,
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

  String get displayProtocol {
    switch (protocol) {
      case ProtocolType.hysteria:
        return 'UDP => HYSTERIA';
      case ProtocolType.sshWs:
        return 'SSH WS';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'protocol': protocol.name,
        'hysteriaPort': hysteriaPort,
        'hysteriaAuth': hysteriaAuth,
        'hysteriaObfsPassword': hysteriaObfsPassword,
        'hysteriaUpSpeed': hysteriaUpSpeed,
        'hysteriaDownSpeed': hysteriaDownSpeed,
        'hysteriaUdpWindow': hysteriaUdpWindow,
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
      hysteriaPort: json['hysteriaPort'] as String? ?? '36712',
      hysteriaAuth: json['hysteriaAuth'] as String? ?? '',
      hysteriaObfsPassword: json['hysteriaObfsPassword'] as String? ?? '',
      hysteriaUpSpeed: json['hysteriaUpSpeed'] as int? ?? 100,
      hysteriaDownSpeed: json['hysteriaDownSpeed'] as int? ?? 100,
      hysteriaUdpWindow: json['hysteriaUdpWindow'] as int? ?? 196608,
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

  ServerConfig copy() => ServerConfig(
        id: id,
        name: name,
        host: host,
        protocol: protocol,
        hysteriaPort: hysteriaPort,
        hysteriaAuth: hysteriaAuth,
        hysteriaObfsPassword: hysteriaObfsPassword,
        hysteriaUpSpeed: hysteriaUpSpeed,
        hysteriaDownSpeed: hysteriaDownSpeed,
        hysteriaUdpWindow: hysteriaUdpWindow,
        sshPort: sshPort,
        sshUsername: sshUsername,
        sshPassword: sshPassword,
        sshKey: sshKey,
        wsPath: wsPath,
        wsPort: wsPort,
        remarks: remarks,
        createdAt: createdAt,
        isActive: isActive,
      );
}
