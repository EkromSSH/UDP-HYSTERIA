import 'package:flutter/material.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Configuration' : 'Add Configuration'),
      ),
      body: Container(
        color: const Color(0xFF0A0A0A),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Protocol (display only)
                _label('Protocol'),
                const SizedBox(height: 6),
                _darkBox(
                  child: Row(
                    children: [
                      const Icon(Icons.flash_on, color: Colors.white54, size: 18),
                      const SizedBox(width: 10),
                      const Text(
                        'UDP => HYSTERIA',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('UDP', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _label('Configuration'),
                const SizedBox(height: 6),

                _field(label: 'Config Name', hint: '239', ctrl: _nameCtrl),
                const SizedBox(height: 14),
                _field(label: 'UDP Host', hint: 'app.idavpn.win', ctrl: _hostCtrl),
                const SizedBox(height: 14),
                _field(label: 'UDP Port', hint: '10000-50000', ctrl: _portCtrl),
                const SizedBox(height: 14),
                _field(
                  label: 'AUTH',
                  hint: 'ida:ida',
                  ctrl: _authCtrl,
                  obscure: !_showAuth,
                  suffix: IconButton(
                    icon: Icon(_showAuth ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                    onPressed: () => setState(() => _showAuth = !_showAuth),
                  ),
                ),
                const SizedBox(height: 14),
                _field(
                  label: 'OBFS',
                  hint: 'admin',
                  ctrl: _obfsCtrl,
                  obscure: !_showObfs,
                  suffix: IconButton(
                    icon: Icon(_showObfs ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                    onPressed: () => setState(() => _showObfs = !_showObfs),
                  ),
                ),
                const SizedBox(height: 14),

                // UP SPEED & DOWN SPEED
                Row(
                  children: [
                    Expanded(child: _field(label: 'UP SPEED', hint: '10', ctrl: _upCtrl, numeric: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _field(label: 'DOWN SPEED', hint: '18', ctrl: _downCtrl, numeric: true)),
                  ],
                ),
                const SizedBox(height: 14),

                _field(label: 'UDP Window', hint: '196608', ctrl: _windowCtrl, numeric: true),

                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          )
                        : const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _darkBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    bool obscure = false,
    Widget? suffix,
    bool numeric = false,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF4444)),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        return null;
      },
    );
  }

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
}
