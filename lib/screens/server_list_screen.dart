import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/connection_provider.dart';
import '../models/server_config.dart';
import '../widgets/app_widgets.dart';
import '../services/storage_service.dart';
import 'add_server_screen.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  List<ServerConfig> _servers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    final storage = await StorageService.getInstance();
    setState(() {
      _servers = [];
    });
    final loaded = await storage.getServers();
    if (mounted) {
      setState(() {
        _servers = loaded;
        _loading = false;
      });
    }
  }

  Future<void> _deleteServer(ServerConfig server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Delete Server', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${server.name}"?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final storage = await StorageService.getInstance();
      await storage.deleteServer(server.id);
      _loadServers();
    }
  }

  void _connectTo(ServerConfig server) {
    final provider = context.read<ConnectionProvider>();
    provider.connect(server);
    // Switch to home tab
    if (mounted) {
      // We'll use a callback or just show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to ${server.name}...'),
          backgroundColor: AppTheme.primaryPurple,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              final result = await Navigator.push<ServerConfig>(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddServerScreen(),
                ),
              );
              if (result != null) {
                _loadServers();
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadServers,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _servers.length,
                    itemBuilder: (ctx, i) {
                      final server = _servers[i];
                      return ServerTile(
                        name: server.name,
                        host: server.host,
                        protocol: server.displayProtocol,
                        isActive: server.isActive,
                        onTap: () => _connectTo(server),
                        onDelete: () => _deleteServer(server),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.dns_outlined,
                size: 64,
                color: AppTheme.primaryPurple,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Servers Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first server to get started\nwith EkromSSH VPN',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<ServerConfig>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddServerScreen(),
                  ),
                );
                if (result != null) {
                  _loadServers();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Server'),
            ),
          ],
        ),
      ),
    );
  }
}
