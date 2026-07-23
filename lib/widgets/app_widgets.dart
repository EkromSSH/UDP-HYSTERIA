import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProtocolBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const ProtocolBadge({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? AppTheme.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bgColor.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: bgColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;

  const StatusIndicator({
    super.key,
    this.isConnected = false,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    if (isConnected) {
      color = AppTheme.successGreen;
      label = 'Connected';
      icon = Icons.vpn_lock;
    } else if (isConnecting) {
      color = AppTheme.warningOrange;
      label = 'Connecting...';
      icon = Icons.sync;
    } else {
      color = AppTheme.errorRed;
      label = 'Disconnected';
      icon = Icons.vpn_lock;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isConnecting) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ],
    );
  }
}

class TrafficDisplay extends StatelessWidget {
  final String sent;
  final String received;

  const TrafficDisplay({
    super.key,
    required this.sent,
    required this.received,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TrafficItem(
          icon: Icons.arrow_upward,
          label: 'Upload',
          value: sent,
          color: AppTheme.warningOrange,
        ),
        const SizedBox(width: 48),
        _TrafficItem(
          icon: Icons.arrow_downward,
          label: 'Download',
          value: received,
          color: AppTheme.successGreen,
        ),
      ],
    );
  }
}

class _TrafficItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TrafficItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class ServerTile extends StatelessWidget {
  final String name;
  final String host;
  final String protocol;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ServerTile({
    super.key,
    required this.name,
    required this.host,
    required this.protocol,
    this.isActive = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                isActive ? AppTheme.successGreen : AppTheme.primaryBlue,
                isActive ? AppTheme.successGreen.withOpacity(0.7) : AppTheme.primaryBlue,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            protocol == 'Hysteria' ? Icons.bolt : Icons.terminal,
            color: Colors.white,
            size: 24,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              host,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            ProtocolBadge(label: protocol),
          ],
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }
}
