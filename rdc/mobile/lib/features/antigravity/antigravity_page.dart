/// RDC — Módulo Mimo Agent (AI Agent)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';
import 'ai_model_picker.dart';
import 'model_browser_page.dart';

// ── Modelo de mensagem do chat ───────────────────────────────────────────────

enum _MsgRole { user, ai, tool, system, reasoning }

class _ChatMsg {
  final _MsgRole role;
  final String text;
  final int? runId;
  final List<String> filesChanged;
  final bool canApprove;

  _ChatMsg({
    required this.role,
    required this.text,
    this.runId,
    this.filesChanged = const [],
    this.canApprove = false,
  });

  _ChatMsg copyWith({String? text, int? runId, List<String>? filesChanged, bool? canApprove}) {
    return _ChatMsg(
      role: role,
      text: text ?? this.text,
      runId: runId ?? this.runId,
      filesChanged: filesChanged ?? this.filesChanged,
      canApprove: canApprove ?? this.canApprove,
    );
  }
}

// ── Página principal ─────────────────────────────────────────────────────────

class AntigravityPage extends StatefulWidget {
  final int projectId;
  const AntigravityPage({super.key, required this.projectId});

  @override
  State<AntigravityPage> createState() => _AntigravityPageState();
}

class _AntigravityPageState extends State<AntigravityPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _promptCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMsg> _msgs = [];
  bool _running = false;
  String _aiModelName = 'Nenhum modelo';

  // Mensagem da IA sendo construída ao vivo
  final _aiBuffer = StringBuffer();
  int? _liveRunId;
  List<String> _liveFiles = [];

  // Ferramentas disponíveis no Mimo
  List<Map<String, String>> _tools = [];

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadHistory();
    _loadTools();
  }

  Future<void> _loadModel() async {
    final saved = await SecureStorage.getAiModel();
    if (saved != null && mounted) {
      final models = await fetchModelsFromApi();
      final found = models.where((m) => m.id == saved).firstOrNull;
      setState(() => _aiModelName = found?.name ?? saved.split('/').last);
    }
  }

  Future<void> _loadTools() async {
    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';
      final uri = Uri.parse('$agentUrl/api/mimo/functions');

      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final client = http_io.IOClient(httpClient);
      final response = await client.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _tools = data.map<Map<String, String>>((e) => {
            'name': e['name'] ?? '',
            'description': e['description'] ?? '',
          }).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiClient.instance.get('/api/mimo/history/${widget.projectId}');
      if (res.statusCode == 200) {
        final List runs = res.data;
        // API returns newest first. Sort to oldest first.
        runs.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
        
        final List<_ChatMsg> historyMsgs = [];
        for (var run in runs) {
          final runId = run['id'];
          final prompt = run['prompt'];
          final outputLog = run['output_log'] ?? '';
          final files = List<String>.from(run['files_changed'] ?? []);
          final status = run['status'];
          final elapsed = run['execution_time_s'];

          historyMsgs.add(_ChatMsg(role: _MsgRole.user, text: prompt, runId: runId));
          
          final lines = outputLog.toString().split('\n');
          final aiText = StringBuffer();
          for (var line in lines) {
            if (line.trim().startsWith('{"tool_call"')) {
              try {
                final d = jsonDecode(line);
                historyMsgs.add(_ChatMsg(role: _MsgRole.tool, text: d['tool_call']['name'] ?? 'tool'));
              } catch (_) {}
            } else {
              aiText.write('$line\n');
            }
          }
          
          if (aiText.isNotEmpty) {
            historyMsgs.add(_ChatMsg(
              role: _MsgRole.ai, 
              text: aiText.toString().trim(),
            ));
          }
          
          if (status == 'approved') {
            historyMsgs.add(_ChatMsg(role: _MsgRole.system, text: '✅ Alterações aplicadas', runId: runId));
          } else if (status == 'rejected') {
            historyMsgs.add(_ChatMsg(role: _MsgRole.system, text: '🔄 Alterações revertidas', runId: runId));
          } else if (files.isNotEmpty && status == 'success') {
            historyMsgs.add(_ChatMsg(
              role: _MsgRole.system,
              text: '✅ Concluído em ${elapsed}s · ${files.length} arquivo(s) modificado(s)',
              runId: runId,
              filesChanged: files,
              canApprove: true,
            ));
          } else if (status == 'error') {
            historyMsgs.add(_ChatMsg(role: _MsgRole.system, text: '❌ Erro na execução', runId: runId));
          }
        }

        if (mounted) {
          setState(() {
            _msgs.addAll(historyMsgs);
          });
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  // ── Undo: remove último par user+ai ────────────────────────────────────────

  Future<void> _undo() async {
    if (_running || _msgs.isEmpty) return;

    // Buscar último runId antes de remover para reverter alterações no backend
    int? lastRunId;
    for (var m in _msgs.reversed) {
      if (m.runId != null) {
        lastRunId = m.runId;
        break;
      }
    }

    if (lastRunId != null) {
      try {
        await ApiClient.instance.post('/api/mimo/run/$lastRunId/approve', data: {'run_id': lastRunId, 'approve': false});
      } catch (_) {}
    }

    setState(() {
      // Remove mensagens até encontrar o último user
      while (_msgs.isNotEmpty && _msgs.last.role != _MsgRole.user) {
        _msgs.removeLast();
      }
      if (_msgs.isNotEmpty && _msgs.last.role == _MsgRole.user) {
        _promptCtrl.text = _msgs.removeLast().text;
      }
    });
  }

  // ── Envio do prompt ─────────────────────────────────────────────────────────

  Future<void> _runPrompt() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;
    _promptCtrl.clear();

    setState(() {
      _running = true;
      _msgs.add(_ChatMsg(role: _MsgRole.user, text: prompt));
      _aiBuffer.clear();
      _liveFiles = [];
      _liveRunId = null;
    });
    _scrollToBottom();

    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';
      final aiModel = await SecureStorage.getAiModel();
      final aiKey = await SecureStorage.getAiApiKey();

      final request = http.Request('POST', Uri.parse('$agentUrl/api/mimo/run'));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'project_id': widget.projectId,
        'prompt': prompt,
        'model': aiModel,
        'api_key': aiKey,
      });

      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final client = http_io.IOClient(httpClient);
      final response = await client.send(request);

      // Índice da mensagem AI atual (para atualizar in-place)
      int? _aiMsgIndex;
      int? _toolMsgIndex;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          try {
            final data = jsonDecode(line.substring(6));
            final type = data['type'];

            if (type == 'start') {
              _liveRunId = data['run_id'];

            } else if (type == 'output') {
              final text = (data['line'] as String?)?.replaceAll('\\n', '\n') ?? '';
              if (text.trim().isEmpty) continue;

              setState(() {
                // Tool call — mensagem separada
                if (text.contains('Executando:') || text.contains('🔍') || text.contains('📄') || text.contains('✏️') || text.contains('⚙️') || text.contains('🧠')) {
                  // Finalizar msg AI anterior se existir
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.tool, text: text.trim()));
                  _toolMsgIndex = _msgs.length - 1;
                } else if (text.startsWith('💭')) {
                  // Reasoning — mensagem separada
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.reasoning, text: text.replaceFirst('💭', '').trim()));
                } else if (text.startsWith('❌') || text.startsWith('⚠️')) {
                  // Erro/aviso — mensagem de sistema
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.system, text: text.trim()));
                } else {
                  // Texto da IA — acumular no buffer e atualizar in-place
                  _aiBuffer.write(text);
                  if (_aiMsgIndex == null) {
                    _msgs.add(_ChatMsg(role: _MsgRole.ai, text: ''));
                    _aiMsgIndex = _msgs.length - 1;
                  } else {
                    // Atualizar mensagem existente
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                  }
                }
              });
              _scrollToBottom();

            } else if (type == 'done') {
              final files = List<String>.from(data['files_changed'] ?? []);
              final elapsed = data['elapsed'];
              final runId = _liveRunId;

              setState(() {
                // Finalizar msg AI se buffer tiver conteúdo
                if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                  final idx = _aiMsgIndex!;
                  if (idx < _msgs.length) {
                    _msgs[idx] = _msgs[idx].copyWith(
                      text: _aiBuffer.toString().trim(),
                      runId: runId,
                      filesChanged: files,
                      canApprove: files.isNotEmpty,
                    );
                  }
                  _aiBuffer.clear();
                  _aiMsgIndex = null;
                } else if (_aiMsgIndex != null) {
                  // AI msg vazia — remover
                  _msgs.removeAt(_aiMsgIndex!);
                  _aiMsgIndex = null;
                }

                // Resumo final limpo
                final fileCount = files.length;
                final fileNames = fileCount > 0
                    ? files.map((f) => f.split(RegExp(r'[/\\]')).last).take(3).join(', ')
                    : '';
                String summary = '✅ Concluído em ${elapsed}s';
                if (fileCount > 0) {
                  summary += ' · $fileCount arquivo${fileCount > 1 ? "s" : ""} modificado${fileCount > 1 ? "s" : ""}';
                  if (fileCount <= 3) summary += '\n📄 $fileNames';
                  else if (fileCount > 3) summary += '\n📄 $fileNames... +${fileCount - 3}';
                }

                _msgs.add(_ChatMsg(
                  role: _MsgRole.system,
                  text: summary,
                  runId: runId,
                  filesChanged: files,
                  canApprove: files.isNotEmpty,
                ));
              });
              _scrollToBottom();

            } else if (type == 'error') {
              setState(() {
                _msgs.add(_ChatMsg(role: _MsgRole.system, text: '❌ ${data['message']}'));
              });
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      setState(() {
        _msgs.add(_ChatMsg(role: _MsgRole.system, text: '❌ Erro de conexão: $e'));
      });
    } finally {
      // Flush buffer
      if (_aiBuffer.isNotEmpty) {
        setState(() {
          _msgs.add(_ChatMsg(role: _MsgRole.ai, text: _aiBuffer.toString().trim()));
          _aiBuffer.clear();
        });
      }
      setState(() => _running = false);
      _scrollToBottom();
    }
  }

  // ── Aprovar / Rejeitar ──────────────────────────────────────────────────────

  Future<void> _approve(int runId, bool approve) async {
    try {
      await ApiClient.instance.post('/api/mimo/run/$runId/approve',
          data: {'run_id': runId, 'approve': approve});
      // Atualiza canApprove da msg correspondente
      setState(() {
        for (int i = 0; i < _msgs.length; i++) {
          if (_msgs[i].runId == runId) {
            _msgs[i] = _ChatMsg(
              role: _msgs[i].role,
              text: _msgs[i].text,
              runId: runId,
              filesChanged: _msgs[i].filesChanged,
              canApprove: false,
            );
          }
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? '✅ Alterações aplicadas' : '🔄 Alterações revertidas'),
        backgroundColor: approve ? RdcTheme.success : RdcTheme.danger,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: RdcTheme.danger));
    }
  }

  // ── Ferramentas disponíveis ────────────────────────────────────────────────────

  void _showToolsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RdcTheme.bg800,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: RdcTheme.bg500, borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: RdcTheme.primaryGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.build, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Text('Ferramentas Mimo', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
            const Spacer(),
            Text('${_tools.length} disponíveis', style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
          ]),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _tools.length,
              itemBuilder: (_, i) {
                final tool = _tools[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RdcTheme.bg700,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RdcTheme.bg500),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: RdcTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_toolIcon(tool['name'] ?? ''), size: 14, color: RdcTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tool['name'] ?? '',
                            style: GoogleFonts.firaCode(fontSize: 13, fontWeight: FontWeight.w600, color: RdcTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(tool['description'] ?? '',
                            style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  IconData _toolIcon(String name) {
    switch (name) {
      case 'read': return Icons.visibility_outlined;
      case 'write': return Icons.edit_outlined;
      case 'edit': return Icons.tune;
      case 'glob': return Icons.folder_open;
      case 'grep': return Icons.search;
      case 'bash': return Icons.terminal;
      case 'codesearch': return Icons.psychology;
      case 'websearch': return Icons.language;
      case 'webfetch': return Icons.download;
      case 'actor': return Icons.smart_toy;
      case 'skill': return Icons.extension;
      case 'memory': return Icons.memory;
      case 'task': return Icons.checklist;
      case 'history': return Icons.history;
      default: return Icons.build;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: RdcTheme.bg800,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: RdcTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Mimo Agent',
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
          const Spacer(),
          if (_msgs.isNotEmpty && !_running)
            IconButton(
              icon: const Icon(Icons.undo, color: RdcTheme.textMuted, size: 20),
              tooltip: 'Desfazer última mensagem',
              onPressed: _undo,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: RdcTheme.textMuted, size: 20),
            tooltip: 'Configurar modelo de IA',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ModelBrowserPage())),
          ),
          if (_tools.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.build_outlined, color: RdcTheme.textMuted, size: 20),
              tooltip: 'Ferramentas disponíveis',
              onPressed: () => _showToolsSheet(context),
            ),
          if (_running)
            const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: RdcTheme.primary)),
        ]),
      ),

      // Chat
      Expanded(
        child: _msgs.isEmpty
            ? _EmptyState()
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _MessageBubble(
                  msg: _msgs[i],
                  onApprove: (id) => _approve(id, true),
                  onReject: (id) => _approve(id, false),
                ),
              ),
      ),

      // Quick prompts
      if (!_running)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            _Chip('Adicionar testes', _promptCtrl),
            _Chip('Refatorar código', _promptCtrl),
            _Chip('Adicionar logging', _promptCtrl),
            _Chip('Documentar funções', _promptCtrl),
            _Chip('Listar arquivos', _promptCtrl),
          ]),
        ),

      // Input bar
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        color: RdcTheme.bg800,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _promptCtrl,
              maxLines: 4,
              minLines: 1,
              style: GoogleFonts.inter(fontSize: 14, color: RdcTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Descreva o que quer fazer...',
                hintStyle: const TextStyle(color: RdcTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: RdcTheme.bg700,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _running ? null : _runPrompt(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _running ? null : _runPrompt,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: _running ? null : RdcTheme.primaryGradient,
                color: _running ? RdcTheme.bg600 : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 48, color: RdcTheme.textMuted.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('Mimo Agent',
              style: GoogleFonts.inter(fontSize: 16, color: RdcTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Descreva uma tarefa e a IA irá ler,\nentender e modificar seu código.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textMuted.withOpacity(0.6))),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final TextEditingController ctrl;
  const _Chip(this.text, this.ctrl);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => ctrl.text = text,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: RdcTheme.bg600,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RdcTheme.bg500),
          ),
          child: Text(text,
              style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textSecondary)),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final _ChatMsg msg;
  final void Function(int) onApprove;
  final void Function(int) onReject;
  const _MessageBubble({required this.msg, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == _MsgRole.user;
    final isTool = msg.role == _MsgRole.tool;
    final isSystem = msg.role == _MsgRole.system;
    final isReasoning = msg.role == _MsgRole.reasoning;

    if (isSystem) {
      return _SystemMsg(msg: msg, onApprove: onApprove, onReject: onReject);
    }

    if (isReasoning) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RdcTheme.primary.withOpacity(0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lightbulb_outline, size: 14, color: RdcTheme.primary.withOpacity(0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg.text,
                style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted, fontStyle: FontStyle.italic)),
          ),
        ]),
      );
    }

    if (isTool) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: RdcTheme.bg700,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RdcTheme.bg500),
        ),
        child: Row(children: [
          Expanded(
            child: Text(msg.text,
                style: GoogleFonts.firaCode(fontSize: 11, color: RdcTheme.textSecondary)),
          ),
        ]),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isUser ? RdcTheme.primaryGradient : null,
          color: isUser ? null : RdcTheme.bg700,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          isUser 
            ? SelectableText(
                msg.text,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.5,
                ),
              )
            : MarkdownBody(
                data: msg.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textPrimary, height: 1.5),
                  h1: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: RdcTheme.textPrimary),
                  h2: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: RdcTheme.textPrimary),
                  h3: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: RdcTheme.textPrimary),
                  code: GoogleFonts.firaCode(fontSize: 12, backgroundColor: Colors.transparent, color: RdcTheme.primary),
                  codeblockDecoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                  codeblockPadding: const EdgeInsets.all(12),
                ),
              ),
          // Arquivos modificados
          if (msg.filesChanged.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: msg.filesChanged.map((f) =>
              GestureDetector(
                onTap: () => _copyToClipboard(context, f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: RdcTheme.primary.withOpacity(0.5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.insert_drive_file, size: 10, color: RdcTheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      f.split('/').last,
                      style: GoogleFonts.firaCode(fontSize: 10, color: RdcTheme.primary),
                    ),
                  ]),
                ),
              ),
            ).toList()),
          ],
          // Botões de aprovação
          if (msg.canApprove && msg.runId != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onReject(msg.runId!),
                  icon: const Icon(Icons.undo, size: 13),
                  label: const Text('Reverter', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RdcTheme.danger,
                    side: const BorderSide(color: RdcTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onApprove(msg.runId!),
                  icon: const Icon(Icons.check, size: 13),
                  label: const Text('Aplicar', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RdcTheme.success,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado: $text'), duration: const Duration(seconds: 1)),
    );
  }
}

class _SystemMsg extends StatelessWidget {
  final _ChatMsg msg;
  final void Function(int) onApprove;
  final void Function(int) onReject;
  const _SystemMsg({required this.msg, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final isError = msg.text.startsWith('❌');
    final hasFiles = msg.filesChanged.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isError ? RdcTheme.danger.withOpacity(0.1) : RdcTheme.bg700.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError ? RdcTheme.danger.withOpacity(0.3) : RdcTheme.bg500.withOpacity(0.5),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg.text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isError ? RdcTheme.danger : RdcTheme.textMuted,
            )),
        if (hasFiles) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: msg.filesChanged.map((f) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: RdcTheme.bg600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(f, style: GoogleFonts.firaCode(fontSize: 10, color: RdcTheme.textSecondary)),
            ),
          ).toList()),
        ],
        if (msg.canApprove && msg.runId != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onReject(msg.runId!),
                icon: const Icon(Icons.undo, size: 13),
                label: const Text('Reverter', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RdcTheme.danger,
                  side: const BorderSide(color: RdcTheme.danger),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => onApprove(msg.runId!),
                icon: const Icon(Icons.check, size: 13),
                label: const Text('Aplicar', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RdcTheme.success,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
