import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/server_config.dart';
import '../services/storage_service.dart';

class AddServerScreen extends StatefulWidget {
  final ServerConfig? editServer;
  const AddServerScreen({super.key, this.editServer});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  late ServerConfig _config;
  bool _saving = false;
  bool _showPassword = false;
  bool _showSshPassword = false;
  bool _showObfs = false;

  @override
  void initState() {
    super.initState();
    _config = widget.editServer?.copy() ?? ServerConfig();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editServer != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Server' : 'Add Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _showQrInfo,
            tooltip: 'Scan QR Code',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Basic Info ──────────────────────────────
              _SectionHeader(title: 'Basic Information'),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Server Name',
                hint: 'My Server 1',
                icon: Icons.label_outline,
                initialValue: _config.name,
                onChanged: (v) => _config.name = v,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Host / IP Address',
                hint: 'server.example.com',
                icon: Icons.language,
                initialValue: _config.host,
                onChanged: (v) => _config.host = v,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ─── Protocol Selector ───────────────────────
              _SectionHeader(title: 'Protocol'),
              const SizedBox(height: 12),
              _buildProtocolSelector(),
              const SizedBox(height: 8),
              _buildProtocolFields(),

              const SizedBox(height: 12),
              _buildTextField(
                label: 'Remarks (optional)',
                hint: 'For personal notes',
                icon: Icons.notes,
                initialValue: _config.remarks ?? '',
                onChanged: (v) => _config.remarks = v,
              ),
              const SizedBox(height: 32),

              // ─── Save Button ─────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(isEditing ? 'Update Server' : 'Save Server'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Protocol Fields ──────────────────────────────────────

  Widget _buildProtocolSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _config.protocol = ProtocolType.hysteria),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _config.protocol == ProtocolType.hysteria
                      ? AppTheme.primaryPurple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bolt,
                      color: _config.protocol == ProtocolType.hysteria ? Colors.white : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hysteria',
                      style: TextStyle(
                        color: _config.protocol == ProtocolType.hysteria ? Colors.white : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _config.protocol = ProtocolType.sshWs),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _config.protocol == ProtocolType.sshWs
                      ? AppTheme.primaryPurple
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.terminal,
                      color: _config.protocol == ProtocolType.sshWs ? Colors.white : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SSH WS',
                      style: TextStyle(
                        color: _config.protocol == ProtocolType.sshWs ? Colors.white : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolFields() {
    switch (_config.protocol) {
      case ProtocolType.hysteria:
        return _buildHysteriaFields();
      case ProtocolType.sshWs:
        return _buildSshWsFields();
    }
  }

  Widget _buildHysteriaFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'Port',
                hint: '36712',
                icon: Icons.router,
                keyboardType: TextInputType.number,
                initialValue: _config.hysteriaPort.toString(),
                onChanged: (v) => _config.hysteriaPort = int.tryParse(v) ?? 36712,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: 'ALPN',
                hint: 'h3',
                icon: Icons.tune,
                initialValue: _config.hysteriaAlpn,
                onChanged: (v) => _config.hysteriaAlpn = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'Password',
          hint: 'hysteria password',
          icon: Icons.lock_outline,
          obscure: !_showPassword,
          initialValue: _config.hysteriaPassword,
          onChanged: (v) => _config.hysteriaPassword = v,
          suffix: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'Upload Mbps',
                hint: '100',
                icon: Icons.arrow_upward,
                keyboardType: TextInputType.number,
                initialValue: _config.hysteriaUploadMbps.toString(),
                onChanged: (v) => _config.hysteriaUploadMbps = int.tryParse(v) ?? 100,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: 'Download Mbps',
                hint: '100',
                icon: Icons.arrow_downward,
                keyboardType: TextInputType.number,
                initialValue: _config.hysteriaDownloadMbps.toString(),
                onChanged: (v) => _config.hysteriaDownloadMbps = int.tryParse(v) ?? 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'Obfs Password (optional)',
          hint: 'salamander password',
          icon: Icons.shuffle,
          obscure: !_showObfs,
          initialValue: _config.hysteriaObfsPassword,
          onChanged: (v) => _config.hysteriaObfsPassword = v,
          suffix: IconButton(
            icon: Icon(_showObfs ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary),
            onPressed: () => setState(() => _showObfs = !_showObfs),
          ),
        ),
      ],
    );
  }

  Widget _buildSshWsFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'SSH Port',
                hint: '22',
                icon: Icons.router,
                keyboardType: TextInputType.number,
                initialValue: _config.sshPort.toString(),
                onChanged: (v) => _config.sshPort = int.tryParse(v) ?? 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: 'WS Port',
                hint: '8080',
                icon: Icons.web,
                keyboardType: TextInputType.number,
                initialValue: _config.wsPort.toString(),
                onChanged: (v) => _config.wsPort = int.tryParse(v) ?? 8080,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'SSH Username',
          hint: 'root',
          icon: Icons.person,
          initialValue: _config.sshUsername,
          onChanged: (v) => _config.sshUsername = v,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'SSH Password',
          hint: 'password',
          icon: Icons.lock_outline,
          obscure: !_showSshPassword,
          initialValue: _config.sshPassword,
          onChanged: (v) => _config.sshPassword = v,
          suffix: IconButton(
            icon: Icon(_showSshPassword ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary),
            onPressed: () => setState(() => _showSshPassword = !_showSshPassword),
          ),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          label: 'WebSocket Path',
          hint: '/',
          icon: Icons.link,
          initialValue: _config.wsPath,
          onChanged: (v) => _config.wsPath = v,
        ),
      ],
    );
  }

  // ─── Helper Widgets ───────────────────────────────────────

  Widget _buildTextField({
    required String label,
    String? hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    String? initialValue,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      initialValue: initialValue,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
        suffixIcon: suffix,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final storage = await StorageService.getInstance();
    if (widget.editServer != null) {
      await storage.updateServer(_config);
    } else {
      await storage.addServer(_config);
    }

    if (mounted) {
      Navigator.pop(context, _config);
    }
  }

  void _showQrInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('QR Scan', style: TextStyle(color: Colors.white)),
        content: const Text(
          'QR Code scanning will be available in the next update.\n\n'
          'You can import config via JSON file from Settings.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
