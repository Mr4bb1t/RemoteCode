/// RDC — Tela de Configuração (conexão ao agente + desconexão)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  Future<void> _initState() async {
    final savedUrl = await SecureStorage.getAgentUrl();
    final loggedIn = await SecureStorage.isLoggedIn();

    if (mounted) {
      setState(() {
        if (savedUrl != null && savedUrl.isNotEmpty) _urlController.text = savedUrl;
        _isLoggedIn = loggedIn;
      });
    }

    if (loggedIn && savedUrl != null && savedUrl.isNotEmpty) {
      ApiClient.init(savedUrl);
      if (mounted) context.go('/dashboard');
    }
  }

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        _urlController.text.trim(),
        _passwordController.text,
      );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: Text('Desconectar', style: GoogleFonts.inter(color: RdcTheme.textPrimary)),
        content: Text(
          'Tem certeza que deseja desconectar?\nSua URL e configurações de IA serão mantidas.',
          style: GoogleFonts.inter(color: RdcTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: RdcTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.danger),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // ── Header ─────────────────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: RdcTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.developer_board, color: Colors.white, size: 40),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Remote Dev Control',
                        style: GoogleFonts.inter(
                            fontSize: 22, fontWeight: FontWeight.w800, color: RdcTheme.textPrimary)),
                    Text('Configurações',
                        style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textSecondary)),
                  ]),
                ),
              ]),

              const SizedBox(height: 36),

              // ── Conexão ────────────────────────────────────────────────────
              _SectionLabel('Conexão ao Agente'),
              const SizedBox(height: 12),

              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                enabled: !_isLoggedIn,
                style: const TextStyle(color: RdcTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'URL do Agente',
                  hintText: 'https://192.168.1.x:8765',
                  prefixIcon: Icon(Icons.link, color: RdcTheme.textMuted),
                ),
              ),
              const SizedBox(height: 12),

              if (!_isLoggedIn) ...[
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  style: const TextStyle(color: RdcTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    hintText: 'Senha do agente',
                    prefixIcon: const Icon(Icons.lock_outline, color: RdcTheme.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          color: RdcTheme.textMuted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _connect(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: RdcTheme.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: RdcTheme.danger.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: RdcTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: RdcTheme.danger, fontSize: 13))),
                    ]),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _connect,
                    icon: _loading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login),
                    label: Text(_loading ? 'Conectando...' : 'Conectar'),
                  ),
                ),
              ],

              // Status conectado
              if (_isLoggedIn)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: RdcTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RdcTheme.success.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: RdcTheme.success, size: 18),
                    const SizedBox(width: 8),
                    Text('Conectado ao agente',
                        style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.success)),
                  ]),
                ),

              const SizedBox(height: 28),

              // ── Desconectar ────────────────────────────────────────────────
              if (_isLoggedIn) ...[
                _SectionLabel('Sessão'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Desconectar do Agente'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RdcTheme.danger,
                      side: const BorderSide(color: RdcTheme.danger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ── Info ────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: RdcTheme.bg700,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: RdcTheme.bg500),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.info_outline, color: RdcTheme.info, size: 16),
                    const SizedBox(width: 8),
                    Text('Como conectar',
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600, color: RdcTheme.info)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '1. Inicie o agente no computador:\n   python main.py\n\n'
                    '2. Use o IP mostrado no painel GUI\n\n'
                    '3. Aceite o certificado quando solicitado',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: RdcTheme.textSecondary, height: 1.6),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: RdcTheme.textMuted,
          letterSpacing: 0.8,
        ),
      );
}
