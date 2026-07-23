import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/connection_provider.dart';
import '../services/storage_service.dart';
import '../services/config_export_import.dart';
import '../models/server_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StorageService? _storage;
  bool _autoConnect = false;
  bool _startOnBoot = false;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = await StorageService.getInstance();
    setState(() {
      _autoConnect = false;
    });
    final autoConnect = await _storage!.getAutoConnect();
    final startOnBoot = await _storage!.getStartOnBoot();
    if (mounted) {
      setState(() {
        _autoConnect = autoConnect;
        _startOnBoot = startOnBoot;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ─── Connection ──────────────────────────────────
          const _SectionHeader2(title: 'CONNECTION'),
          _SettingsTile(
            icon: Icons.wifi_tethering,
            title: 'Auto Connect',
            subtitle: 'Auto-connect to last server on app start',
            trailing: Switch(
              value: _autoConnect,
              onChanged: (v) {
                setState(() => _autoConnect = v);
                _storage?.setAutoConnect(v);
              },
              activeColor: AppTheme.primaryBlue,
            ),
          ),
          _SettingsTile(
            icon: Icons.power_settings_new,
            title: 'Start on Boot',
            subtitle: 'Auto-start VPN after device reboot',
            trailing: Switch(
              value: _startOnBoot,
              onChanged: (v) {
                setState(() => _startOnBoot = v);
                _storage?.setStartOnBoot(v);
              },
              activeColor: AppTheme.primaryBlue,
            ),
          ),
          const Divider(color: AppTheme.borderColor),

          // ─── Network ─────────────────────────────────────
          const _SectionHeader2(title: 'NETWORK'),
          _SettingsTile(
            icon: Icons.tune,
            title: 'MTU',
            subtitle: 'Default: 1500',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () => _showMtuDialog(),
          ),
          _SettingsTile(
            icon: Icons.dns,
            title: 'DNS',
            subtitle: 'Default: 8.8.8.8, 1.1.1.1',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () => _showDnsDialog(),
          ),
          const Divider(color: AppTheme.borderColor),

          // ─── Config ──────────────────────────────────────
          const _SectionHeader2(title: 'CONFIGURATION'),
          _SettingsTile(
            icon: Icons.file_upload_outlined,
            title: 'Export Config',
            subtitle: 'Save server configs to file',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: _exportConfig,
          ),
          _SettingsTile(
            icon: Icons.file_download_outlined,
            title: 'Import Config',
            subtitle: 'Import servers from config file',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: _importConfig,
          ),
          _SettingsTile(
            icon: Icons.share_outlined,
            title: 'Share Config as Text',
            subtitle: 'Copy server configs to clipboard',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: _shareConfigText,
          ),
          const Divider(color: AppTheme.borderColor),

          // ─── About ───────────────────────────────────────
          const _SectionHeader2(title: 'ABOUT'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: 'v$_appVersion',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () => _showAbout(),
          ),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'EkromSSH',
            subtitle: 'Hysteria + SSH WebSocket Client',
          ),
          const SizedBox(height: 32),

          // ─── Footer ──────────────────────────────────────
          Center(
            child: Column(
              children: [
                Text(
                                    'EkromSSH',
                                    style: TextStyle(
                                      color: AppTheme.primaryBlue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Secure Tunnel',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dialogs & Actions ────────────────────────────────────

  void _showMtuDialog() {
    _showEditDialog(
      title: 'MTU Settings',
      fieldLabel: 'MTU Value',
      initialValue: '1500',
      hint: 'Default: 1500',
      onSave: (v) {},
    );
  }

  void _showDnsDialog() {
    _showEditDialog(
      title: 'DNS Settings',
      fieldLabel: 'DNS 1',
      initialValue: '8.8.8.8',
      hint: 'Primary DNS',
      onSave: (v) {},
    );
  }

  void _showEditDialog({
    required String title,
    required String fieldLabel,
    required String initialValue,
    String? hint,
    required ValueChanged<String> onSave,
  }) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: fieldLabel,
            hintText: hint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig() async {
    final storage = await StorageService.getInstance();
    final servers = await storage.getServers();
    if (servers.isEmpty) {
      _showSnackbar('No servers to export');
      return;
    }
    final path = await ConfigExportImport.exportToFile(servers);
    if (mounted) {
      _showSnackbar('Exported to: $path');
    }
  }

  Future<void> _importConfig() async {
    _showSnackbar('Paste JSON config or open file (coming soon)');
  }

  Future<void> _shareConfigText() async {
    final storage = await StorageService.getInstance();
    final servers = await storage.getServers();
    if (servers.isEmpty) {
      _showSnackbar('No servers to share');
      return;
    }
    final text = ConfigExportImport.exportAsText(servers);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showSnackbar('Config copied to clipboard!');
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'EkromSSH',
      applicationVersion: 'v$_appVersion',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryBlue, AppTheme.primaryBlue],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.shield, color: Colors.white, size: 28),
      ),
      children: [
        const Text(
          'Hysteria + SSH WebSocket VPN Client\n'
          'For all your secure tunneling needs.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryBlue),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _SectionHeader2 extends StatelessWidget {
  final String title;
  const _SectionHeader2({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryBlue,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
