/// RDC — Tela de Configuração (conexão ao agente)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _urlController = TextEditingController(text: 'https://192.168.1.100:8765');
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    final auth = await ref.read(authProvider.future);
    if (auth == AuthState.loggedIn && mounted) {
      context.go('/dashboard');
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
              // Logo / Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: RdcTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.developer_board, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                'Remote Dev Control',
                style: GoogleFonts.inter(
                  fontSize: 28, fontWeight: FontWeight.w800, color: RdcTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Conecte ao seu agente desktop para começar',
                style: GoogleFonts.inter(fontSize: 14, color: RdcTheme.textSecondary),
              ),
              const SizedBox(height: 48),

              // URL do Agente
              Text('URL do Agente', style: _labelStyle),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: RdcTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'https://192.168.1.x:8765',
                  prefixIcon: Icon(Icons.link, color: RdcTheme.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              // Senha
              Text('Senha', style: _labelStyle),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                style: const TextStyle(color: RdcTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Senha do agente',
                  prefixIcon: const Icon(Icons.lock_outline, color: RdcTheme.textMuted),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: RdcTheme.textMuted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _connect(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RdcTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RdcTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: RdcTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: RdcTheme.danger, fontSize: 13))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botão Conectar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _connect,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Conectar'),
                ),
              ),

              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: RdcTheme.bg700,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: RdcTheme.bg500),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline, color: RdcTheme.info, size: 16),
                      const SizedBox(width: 8),
                      Text('Como conectar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: RdcTheme.info)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      '1. Inicie o agente no computador:\n   python main.py\n\n'
                      '2. Use o IP mostrado no terminal\n\n'
                      '3. Aceite o certificado quando solicitado',
                      style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textSecondary, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w500, color: RdcTheme.textSecondary,
  );
}
