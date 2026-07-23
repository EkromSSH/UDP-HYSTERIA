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
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _authCtrl = TextEditingController();
  final _obfsCtrl = TextEditingController();
  final _upCtrl = TextEditingController();
  final _downCtrl = TextEditingController();
  final _windowCtrl = TextEditingController();
  bool _saving = false;
  bool _showAuth = false;
  bool _showObfs = false;

  @override
  void initState() {
    super.initState();
    final s = widget.editServer;
    if (s != null) {
      _nameCtrl.text = s.name;
      _hostCtrl.text = s.host;
      _portCtrl.text = s.hysteriaPort;
      _authCtrl.text = s.hysteriaAuth;
      _obfsCtrl.text = s.hysteriaObfsPassword;
      _upCtrl.text = s.hysteriaUpSpeed.toString();
      _downCtrl.text = s.hysteriaDownSpeed.toString();
      _windowCtrl.text = s.hysteriaUdpWindow.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _authCtrl.dispose();
    _obfsCtrl.dispose();
    _upCtrl.dispose();
    _downCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editServer != null;
    final isSsh = widget.editServer?.protocol == ProtocolType.sshWs;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Configuration' : 'Add Configuration'),
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
              // Protocol selector
              _buildSectionHeader('Protocol'),
              const SizedBox(height: 8),
              _buildProtocolSelector(),

              const SizedBox(height: 20),
              _buildSectionHeader('Configuration'),
              const SizedBox(height: 8),

              // Config Name
              _field(
                label: 'Config Name',
                hint: '239',
                icon: Icons.label_outline,
                ctrl: _nameCtrl,
              ),
              const SizedBox(height: 12),

              // UDP Host
              _field(
                label: 'UDP Host',
                hint: 'app.idavpn.win',
                icon: Icons.language,
                ctrl: _hostCtrl,
              ),
              const SizedBox(height: 12),

              // UDP Port
              _field(
                label: 'UDP Port',
                hint: '10000-50000',
                icon: Icons.router,
                ctrl: _portCtrl,
              ),
              const SizedBox(height: 12),

              // AUTH
              _field(
                label: 'AUTH',
                hint: 'ida:ida',
                icon: Icons.lock_outline,
                ctrl: _authCtrl,
                obscure: !_showAuth,
                suffix: IconButton(
                  icon: Icon(_showAuth ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _showAuth = !_showAuth),
                ),
              ),
              const SizedBox(height: 12),

              // OBFS
              _field(
                label: 'OBFS',
                hint: 'admin',
                icon: Icons.shuffle,
                ctrl: _obfsCtrl,
                obscure: !_showObfs,
                suffix: IconButton(
                  icon: Icon(_showObfs ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _showObfs = !_showObfs),
                ),
              ),
              const SizedBox(height: 12),

              // UP SPEED & DOWN SPEED
              Row(
                children: [
                  Expanded(
                    child: _field(
                      label: 'UP SPEED',
                      hint: '10',
                      icon: Icons.arrow_upward,
                      ctrl: _upCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      label: 'DOWN SPEED',
                      hint: '18',
                      icon: Icons.arrow_downward,
                      ctrl: _downCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // UDP Window
              _field(
                label: 'UDP Window',
                hint: '196608',
                icon: Icons.dashboard,
                ctrl: _windowCtrl,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 32),

              // Save button
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
                  label: Text(isEditing ? 'Update' : 'Save'),
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

  // ─── Protocol Selector ────────────────────────────

  Widget _buildProtocolSelector() {
    final isHysteria = widget.editServer?.protocol != ProtocolType.sshWs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.flash_on, color: AppTheme.primaryPurple, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isHysteria ? 'UDP => HYSTERIA' : 'SSH WS',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                isHysteria ? 'UDP/QUIC protocol' : 'SSH over WebSocket',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          Icon(
            isHysteria ? Icons.bolt : Icons.terminal,
            color: AppTheme.primaryPurple,
            size: 20,
          ),
        ],
      ),
    );
  }

  // ─── Reusable Field ──────────────────────────────

  Widget _field({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController ctrl,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
        suffixIcon: suffix,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        return null;
      },
    );
  }

  Widget _buildSectionHeader(String title) {
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

  // ─── Save ─────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final config = ServerConfig(
      id: widget.editServer?.id,
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      protocol: ProtocolType.hysteria,
      hysteriaPort: _portCtrl.text.trim(),
      hysteriaAuth: _authCtrl.text.trim(),
      hysteriaObfsPassword: _obfsCtrl.text.trim(),
      hysteriaUpSpeed: int.tryParse(_upCtrl.text.trim()) ?? 10,
      hysteriaDownSpeed: int.tryParse(_downCtrl.text.trim()) ?? 18,
      hysteriaUdpWindow: int.tryParse(_windowCtrl.text.trim()) ?? 196608,
      createdAt: widget.editServer?.createdAt,
    );

    final storage = await StorageService.getInstance();
    if (widget.editServer != null) {
      await storage.updateServer(config);
    } else {
      await storage.addServer(config);
    }

    if (mounted) {
      Navigator.pop(context, config);
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
