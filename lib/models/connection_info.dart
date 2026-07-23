import 'package:flutter/foundation.dart';
import 'server_config.dart';

class ConnectionInfo {
  final ConnectionStatus status;
  final ServerConfig? activeServer;
  final DateTime? connectedSince;
  final int bytesSent;
  final int bytesReceived;
  final String? errorMessage;
  final ProtocolType? activeProtocol;

  ConnectionInfo({
    this.status = ConnectionStatus.disconnected,
    this.activeServer,
    this.connectedSince,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.errorMessage,
    this.activeProtocol,
  });

  String get elapsedTime {
    if (connectedSince == null) return '--:--:--';
    final diff = DateTime.now().difference(connectedSince!);
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String get formattedSent {
    return _formatBytes(bytesSent);
  }

  String get formattedReceived {
    return _formatBytes(bytesReceived);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ConnectionInfo copyWith({
    ConnectionStatus? status,
    ServerConfig? activeServer,
    DateTime? connectedSince,
    int? bytesSent,
    int? bytesReceived,
    String? errorMessage,
    ProtocolType? activeProtocol,
    bool clearServer = false,
    bool clearError = false,
    bool clearTime = false,
  }) {
    return ConnectionInfo(
      status: status ?? this.status,
      activeServer: clearServer ? null : (activeServer ?? this.activeServer),
      connectedSince:
          clearTime ? null : (connectedSince ?? this.connectedSince),
      bytesSent: bytesSent ?? this.bytesSent,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeProtocol: activeProtocol ?? this.activeProtocol,
    );
  }
}
