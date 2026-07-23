import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/connection_provider.dart';
import '../models/server_config.dart';
import '../services/storage_service.dart';
import '../widgets/app_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  Timer? _trafficTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _trafficTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        context.read<ConnectionProvider>().simulateTraffic();
      }
    });
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, provider, _) {
        final info = provider.info;
        final isConnected = provider.isConnected;
        final isConnecting = provider.isConnecting;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // ─── App Bar ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryBlue, AppTheme.primaryBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.shield,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EkromSSH',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                                          'UDP Hysteria',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      StatusIndicator(
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ─── Main Connection Card ───────────────────
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: isConnected ? _pulseAnimation.value : 1.0,
                          child: child,
                        );
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Glowing circle
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  if (isConnected)
                                    AppTheme.successGreen.withOpacity(0.3)
                                  else if (isConnecting)
                                    AppTheme.warningOrange.withOpacity(0.2)
                                  else
                                    AppTheme.primaryBlue.withOpacity(0.2),
                                  AppTheme.backgroundColor,
                                ],
                                center: Alignment.center,
                                radius: 0.8,
                              ),
                            ),
                            child: Center(
                              child: GestureDetector(
                                onTap: () {
                                  if (isConnected || isConnecting) {
                                    provider.disconnect();
                                  } else {
                                    _showServerPicker(context);
                                  }
                                },
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: isConnected
                                          ? [AppTheme.successGreen, const Color(0xFF00B050)]
                                          : isConnecting
                                              ? [AppTheme.warningOrange, AppTheme.warningOrange.withOpacity(0.7)]
                                              : [AppTheme.primaryBlue, AppTheme.primaryBlue],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isConnected
                                            ? AppTheme.successGreen.withOpacity(0.3)
                                            : AppTheme.primaryBlue.withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: isConnecting
                                        ? const SizedBox(
                                            width: 40,
                                            height: 40,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : Icon(
                                            isConnected ? Icons.vpn_lock : Icons.power_settings_new,
                                            color: Colors.white,
                                            size: 48,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Status text
                          Text(
                            isConnected
                                ? 'VPN Connected'
                                : isConnecting
                                    ? 'Connecting...'
                                    : 'Tap to Connect',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isConnected
                                  ? AppTheme.successGreen
                                  : isConnecting
                                      ? AppTheme.warningOrange
                                      : Colors.white,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Server info
                          if (info.activeServer != null) ...[
                            Text(
                              info.activeServer!.name,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              '${info.activeServer!.host} | ${info.activeServer!.displayProtocol}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),

                          // Traffic
                          if (isConnected)
                            TrafficDisplay(
                              sent: info.formattedSent,
                              received: info.formattedReceived,
                            ),

                          if (isConnected) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.timer, size: 14, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  info.elapsedTime,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Error message
                          if (info.status == ConnectionStatus.error && info.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 40),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.errorRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.errorRed.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      info.errorMessage!,
                                      style: const TextStyle(color: AppTheme.errorRed, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // ─── Quick Connect Bar ──────────────────────
                if (!isConnected && !isConnecting)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showServerPicker(context),
                        icon: const Icon(Icons.language),
                        label: const Text('Select Server & Connect'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),

                if (isConnected)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => provider.disconnect(),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorRed,
                          side: const BorderSide(color: AppTheme.errorRed),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showServerPicker(BuildContext context) async {
    final storage = await StorageService.getInstance();
    final servers = await storage.getServers();

    if (!mounted) return;

    if (servers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a server first in the Servers tab'),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<ServerConfig>(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Server',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a server to connect',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: servers.length > 4 ? 300 : servers.length * 72.0,
                child: ListView.separated(
                  itemCount: servers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderColor),
                  itemBuilder: (ctx, i) {
                    final s = servers[i];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          s.protocol == ProtocolType.hysteria
                              ? Icons.flash_on
                              : Icons.wifi,
                          color: AppTheme.primaryBlue,
                          size: 20,
                        ),
                      ),
                      title: Text(s.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${s.host} | ${s.displayProtocol}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, s),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      context.read<ConnectionProvider>().connect(selected);
    }
  }
}
