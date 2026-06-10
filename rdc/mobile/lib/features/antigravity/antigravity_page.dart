/// RDC — Módulo Antigravity CLI
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

class AntigravityPage extends StatefulWidget {
  final int projectId;
  const AntigravityPage({super.key, required this.projectId});

  @override
  State<AntigravityPage> createState() => _AntigravityPageState();
}

class _AntigravityPageState extends State<AntigravityPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _promptCtrl = TextEditingController();
  List<dynamic> _history = [];
  bool _running = false;
  List<String> _liveOutput = [];
  int? _currentRunId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiClient.instance.get('/api/antigravity/history/${widget.projectId}');
      setState(() => _history = res.data ?? []);
    } catch (_) {}
  }

  Future<void> _runPrompt() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;

    setState(() { _running = true; _liveOutput = ['🚀 Iniciando Antigravity...\n']; });
    _tabs.animateTo(0); // Ir para aba de execução

    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';

      final request = http.Request('POST', Uri.parse('$agentUrl/api/antigravity/run'));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'project_id': widget.projectId, 'prompt': prompt});

      final client = http.Client();
      final response = await client.send(request);

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        // Parse SSE lines
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            try {
              final data = jsonDecode(line.substring(6));
              if (data['type'] == 'start') {
                _currentRunId = data['run_id'];
              } else if (data['type'] == 'output') {
                setState(() => _liveOutput.add(data['line'] ?? ''));
              } else if (data['type'] == 'done') {
                setState(() => _liveOutput.add('\n✅ Concluído em ${data['elapsed']}s\n'));
                _loadHistory();
              } else if (data['type'] == 'error') {
                setState(() => _liveOutput.add('\n❌ Erro: ${data['message']}\n'));
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      setState(() => _liveOutput.add('\n[Erro: $e]\n'));
    } finally {
      setState(() => _running = false);
      _promptCtrl.clear();
    }
  }

  Future<void> _approveRun(int runId, bool approve) async {
    await ApiClient.instance.post('/api/antigravity/run/$runId/approve',
        data: {'run_id': runId, 'approve': approve});
    _loadHistory();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(approve ? '✅ Alterações aplicadas' : '❌ Alterações rejeitadas'),
      backgroundColor: approve ? RdcTheme.success : RdcTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Prompt input
      Container(
        padding: const EdgeInsets.all(16),
        color: RdcTheme.bg800,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: RdcTheme.primaryGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Antigravity CLI', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _promptCtrl,
            maxLines: 3,
            style: GoogleFonts.inter(fontSize: 14, color: RdcTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Ex: "Adicionar autenticação JWT ao projeto"',
              hintStyle: TextStyle(color: RdcTheme.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          // Quick prompts
          Wrap(spacing: 8, runSpacing: 6, children: [
            _QuickPrompt('Adicionar testes', _promptCtrl),
            _QuickPrompt('Refatorar código', _promptCtrl),
            _QuickPrompt('Adicionar logging', _promptCtrl),
            _QuickPrompt('Documentar funções', _promptCtrl),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runPrompt,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_running ? 'Executando...' : 'Enviar para Antigravity'),
            ),
          ),
        ]),
      ),

      // Tabs: Execução | Histórico
      TabBar(
        controller: _tabs,
        labelColor: RdcTheme.primary,
        unselectedLabelColor: RdcTheme.textMuted,
        indicatorColor: RdcTheme.primary,
        tabs: const [Tab(text: 'Execução'), Tab(text: 'Histórico')],
      ),

      Expanded(
        child: TabBarView(controller: _tabs, children: [
          // Execução em tempo real
          Container(
            color: const Color(0xFF0A0A12),
            child: _liveOutput.isEmpty
                ? Center(child: Text('Envie um prompt para iniciar', style: GoogleFonts.inter(color: RdcTheme.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _liveOutput.length,
                    itemBuilder: (_, i) => Text(_liveOutput[i], style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFFD4D4D4), height: 1.4)),
                  ),
          ),

          // Histórico
          ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _history.length,
            itemBuilder: (ctx, i) => _RunHistoryCard(
              run: _history[i],
              onApprove: (id) => _approveRun(id, true),
              onReject: (id) => _approveRun(id, false),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _QuickPrompt extends StatelessWidget {
  final String text;
  final TextEditingController ctrl;
  const _QuickPrompt(this.text, this.ctrl);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => ctrl.text = text,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RdcTheme.bg600,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RdcTheme.bg500),
      ),
      child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textSecondary)),
    ),
  );
}

class _RunHistoryCard extends StatelessWidget {
  final Map<String, dynamic> run;
  final void Function(int) onApprove;
  final void Function(int) onReject;
  const _RunHistoryCard({required this.run, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final status = run['status'] ?? 'pending';
    final files = (run['files_changed'] as List? ?? []);
    final statusColor = switch (status) {
      'success' || 'approved' => RdcTheme.success,
      'error' => RdcTheme.danger,
      'rejected' => RdcTheme.textMuted,
      'running' => RdcTheme.warning,
      _ => RdcTheme.info,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RdcTheme.bg700,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(run['prompt'] ?? '', style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textPrimary, fontWeight: FontWeight.w500))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(status, style: GoogleFonts.inter(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
            ),
          ]),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: files.map<Widget>((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: RdcTheme.bg600, borderRadius: BorderRadius.circular(4)),
              child: Text(f.toString().split('/').last, style: GoogleFonts.firaCode(fontSize: 10, color: RdcTheme.textSecondary)),
            )).toList()),
          ],
          // Aprovação pendente
          if (status == 'success') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onReject(run['id']),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Rejeitar'),
                  style: OutlinedButton.styleFrom(foregroundColor: RdcTheme.danger, side: const BorderSide(color: RdcTheme.danger)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onApprove(run['id']),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Aplicar'),
                  style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.success),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
