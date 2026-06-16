/// RDC — Módulo Mimo Agent (AI Agent) — Multi Chat
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/storage/chat_snapshot_service.dart';
import '../../core/theme/app_theme.dart';
import '../workspace/workspace_page.dart';
import 'ai_model_picker.dart';
import 'model_browser_page.dart';

// ── Modelo de mensagem do chat ───────────────────────────────────────────────

enum _MsgRole { user, ai, system, reasoning, block }

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

  Map<String, dynamic> toJson() => {
    'role': role.index,
    'text': text,
    'runId': runId,
    'filesChanged': filesChanged,
    'canApprove': canApprove,
  };

  factory _ChatMsg.fromJson(Map<String, dynamic> j) => _ChatMsg(
    role: _MsgRole.values[j['role'] ?? 0],
    text: j['text'] ?? '',
    runId: j['runId'],
    filesChanged: List<String>.from(j['filesChanged'] ?? []),
    canApprove: j['canApprove'] ?? false,
  );
}

// ── Modelo de sessão de chat ─────────────────────────────────────────────────

class _ChatSession {
  final String id;
  String title;
  final List<_ChatMsg> messages;
  final DateTime createdAt;

  _ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory _ChatSession.fromJson(Map<String, dynamic> j) => _ChatSession(
    id: j['id'] ?? '',
    title: j['title'] ?? 'Novo chat',
    messages: (j['messages'] as List? ?? []).map((m) => _ChatMsg.fromJson(m)).toList(),
    createdAt: DateTime.parse(j['createdAt'] ?? DateTime.now().toIso8601String()),
  );
}

// ── Página principal ─────────────────────────────────────────────────────────

class AntigravityPage extends StatefulWidget {
  final int projectId;
  const AntigravityPage({super.key, required this.projectId});

  @override
  State<AntigravityPage> createState() => _AntigravityPageState();
}

class _AntigravityPageState extends State<AntigravityPage> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  final _promptCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _running = false;
  bool _stopRequested = false;
  String _aiModelName = 'Nenhum modelo';

  // Drawer lateral
  bool _drawerOpen = false;
  late final AnimationController _drawerCtrl;
  late final Animation<Offset> _drawerAnim;

  // Sessões de chat
  final List<_ChatSession> _sessions = [];
  _ChatSession? _currentSession;

  // Mensagem da IA sendo construída ao vivo
  final _aiBuffer = StringBuffer();
  int? _liveRunId;

  // HTTP client para poder cancelar
  http_io.IOClient? _activeClient;

  List<_ChatMsg> get _msgs => _currentSession?.messages ?? [];

  StreamSubscription<String>? _promptSub;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _drawerAnim = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _drawerCtrl, curve: Curves.easeOutCubic));
    _loadModel();
    _loadSessions();

    _promptSub = WorkspaceEvents.agentPrompt.listen((prompt) {
      if (mounted) {
        // Se houver sessão, preencher o prompt e submeter, ou criar sessão
        if (_currentSession == null) {
          _newSession();
        }
        _promptCtrl.text = prompt;
        _runPrompt();
      }
    });
  }

  Future<void> _loadModel() async {
    final saved = await SecureStorage.getAiModel();
    if (saved != null && mounted) {
      final models = await fetchModelsFromApi();
      final found = models.where((m) => m.id == saved).firstOrNull;
      setState(() => _aiModelName = found?.name ?? saved.split('/').last);
    }
  }

  @override
  void dispose() {
    _promptSub?.cancel();
    _drawerCtrl.dispose();
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

  // ── Gerenciamento de sessões ──────────────────────────────────────────────

  Future<File> get _sessionsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/chat_sessions.json');
  }

  Future<void> _loadSessions() async {
    try {
      final file = await _sessionsFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        setState(() {
          _sessions.clear();
          _sessions.addAll(data.map((j) => _ChatSession.fromJson(j)));
          if (_sessions.isNotEmpty) {
            _currentSession = _sessions.last;
          }
        });
      }

      if (_sessions.isEmpty) {
        _newSession();
      } else {
        _loadHistoryForSession(_currentSession!);
      }
    } catch (_) {
      _newSession();
    }
  }

  Future<void> _saveSessions() async {
    try {
      final file = await _sessionsFile;
      await file.writeAsString(jsonEncode(_sessions.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }

  void _newSession() {
    final session = _ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Novo chat',
      messages: [],
      createdAt: DateTime.now(),
    );
    setState(() {
      _sessions.add(session);
      _currentSession = session;
    });
    _saveSessions();
  }

  void _switchSession(_ChatSession session) {
    setState(() {
      _currentSession = session;
    });
    session.messages.clear();
    _loadHistoryForSession(session);
    _scrollToBottom();
  }

  Future<void> _deleteSession(_ChatSession session) async {
    // Reverter todos os runs desta sessão
    for (final msg in session.messages) {
      if (msg.runId != null) {
        final snapshotService = ChatSnapshotService.instance;
        if (snapshotService.hasSnapshot(msg.runId!)) {
          try {
            await snapshotService.restoreSnapshot(msg.runId!);
          } catch (_) {}
        }
        try {
          await ApiClient.instance.delete('/api/mimo/run/${msg.runId}');
        } catch (_) {}
        await snapshotService.deleteSnapshot(msg.runId!);
      }
    }

    setState(() {
      _sessions.remove(session);
      if (_currentSession == session) {
        _currentSession = _sessions.isNotEmpty ? _sessions.last : null;
      }
    });
    _saveSessions();
    WorkspaceEvents.notifyFileChanges();
 
    if (_sessions.isEmpty) {
      _newSession();
    }
  }

  Future<void> _renameSession(_ChatSession session) async {
    final ctrl = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: const Text('Renomear chat', style: TextStyle(color: RdcTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: RdcTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Nome do chat'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty) {
      setState(() => session.title = newTitle);
      _saveSessions();
    }
  }

  Future<void> _loadHistoryForSession(_ChatSession session) async {
    if (session.messages.isNotEmpty) return;
    try {
      final res = await ApiClient.instance.get('/api/mimo/history/${widget.projectId}');
      if (res.statusCode == 200) {
        final List runs = res.data;
        runs.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

        int? activeRunId;

        for (var run in runs) {
          final runId = run['id'];
          final prompt = run['prompt'];
          final outputLog = run['output_log'] ?? '';
          final files = List<String>.from(run['files_changed'] ?? []);
          final status = run['status'];
          final elapsed = run['execution_time_s'];

          session.messages.add(_ChatMsg(role: _MsgRole.user, text: prompt, runId: runId));

          if (status == 'running') {
            activeRunId = runId;
            continue;
          }

          final lines = outputLog.toString().split('\n');
          final aiText = StringBuffer();
          for (var line in lines) {
            if (_isBlockLine(line)) {
              if (aiText.isNotEmpty) {
                session.messages.add(_ChatMsg(role: _MsgRole.ai, text: aiText.toString().trim()));
                aiText.clear();
              }
              session.messages.add(_ChatMsg(role: _MsgRole.block, text: line.trim()));
              continue;
            }
            if (line.trim().startsWith('{"tool_call"')) continue;
            aiText.write('$line\n');
          }

          if (aiText.isNotEmpty) {
            session.messages.add(_ChatMsg(role: _MsgRole.ai, text: aiText.toString().trim()));
          }

          if (status == 'approved') {
            session.messages.add(_ChatMsg(role: _MsgRole.system, text: 'Alteracoes aplicadas', runId: runId));
          } else if (status == 'rejected') {
            session.messages.add(_ChatMsg(role: _MsgRole.system, text: 'Alteracoes revertidas', runId: runId));
          } else if (files.isNotEmpty && status == 'success') {
            session.messages.add(_ChatMsg(
              role: _MsgRole.system,
              text: 'Concluido em ${elapsed}s | ${files.length} arquivo(s) modificado(s)',
              runId: runId,
              filesChanged: files,
              canApprove: true,
            ));
          } else if (status == 'error') {
            session.messages.add(_ChatMsg(role: _MsgRole.system, text: '[ERRO] Execucao', runId: runId));
          }
        }

        // Atualizar título com base na primeira mensagem
        if (session.messages.isNotEmpty && session.title == 'Novo chat') {
          final firstUserMsg = session.messages.firstWhere(
            (m) => m.role == _MsgRole.user,
            orElse: () => _ChatMsg(role: _MsgRole.user, text: ''),
          );
          if (firstUserMsg.text.isNotEmpty) {
            session.title = firstUserMsg.text.length > 40
                ? '${firstUserMsg.text.substring(0, 40)}...'
                : firstUserMsg.text;
            _saveSessions();
          }
        }

        if (mounted) {
          setState(() {});
          _scrollToBottom();
        }

        if (activeRunId != null) {
          _reconnectRun(activeRunId);
        }
      }
    } catch (_) {}
  }

  Future<void> _reconnectRun(int runId) async {
    if (_running) return;

    _stopRequested = false;
    setState(() {
      _running = true;
      _aiBuffer.clear();
      _liveRunId = runId;
    });

    _scrollToBottom();

    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';

      final request = http.Request('GET', Uri.parse('$agentUrl/api/mimo/run/$runId/stream'));
      request.headers['Authorization'] = 'Bearer $token';

      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      _activeClient = http_io.IOClient(httpClient);
      final response = await _activeClient!.send(request);

      int? _aiMsgIndex;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (_stopRequested) break;
        for (final line in chunk.split('\n')) {
          if (_stopRequested) break;
          if (!line.startsWith('data: ')) continue;
          try {
            final data = jsonDecode(line.substring(6));
            final type = data['type'];

            if (type == 'output') {
              final text = (data['line'] as String?)?.replaceAll('\\n', '\n') ?? '';
              if (text.trim().isEmpty) continue;

              final lower = text.toLowerCase();
              if (lower.contains('api key') || lower.contains('api_key') ||
                  lower.contains('chave') || lower.contains('configura') ||
                  lower.contains('selecionado') || lower.contains('grátis') ||
                  lower.contains('mimo engine') || lower.contains('modelo:') ||
                  lower.contains('projeto:')) continue;

              setState(() {
                if (_isBlockLine(text)) {
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.block, text: text.trim()));
                } else if (text.contains('[REASONING]') || text.contains('[PENSANDO]')) {
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.reasoning, text: text.replaceAll(RegExp(r'\[REASONING\]|\[PENSANDO\]'), '').trim()));
                } else if (text.startsWith('[ERRO]') || text.startsWith('[AVISO]')) {
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
                  _aiBuffer.write(text);
                  if (_aiMsgIndex == null) {
                    _msgs.add(_ChatMsg(role: _MsgRole.ai, text: ''));
                    _aiMsgIndex = _msgs.length - 1;
                  } else {
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
                  _msgs.removeAt(_aiMsgIndex!);
                  _aiMsgIndex = null;
                }

                final fileCount = files.length;
                final fileNames = fileCount > 0
                    ? files.map((f) => f.split(RegExp(r'[/\\]')).last).take(3).join(', ')
                    : '';
                String summary = 'Concluido em ${elapsed}s';
                if (fileCount > 0) {
                  summary += ' | $fileCount arquivo${fileCount > 1 ? "s" : ""} modificado${fileCount > 1 ? "s" : ""}';
                  if (fileCount <= 3) summary += '\n  $fileNames';
                  else if (fileCount > 3) summary += '\n  $fileNames... +${fileCount - 3}';
                }

                _msgs.add(_ChatMsg(
                  role: _MsgRole.system,
                  text: summary,
                  runId: runId,
                  filesChanged: files,
                  canApprove: files.isNotEmpty,
                ));
              });
              _saveSessions();
              _scrollToBottom();
              WorkspaceEvents.notifyFileChanges();

            } else if (type == 'error') {
              setState(() {
                _msgs.add(_ChatMsg(role: _MsgRole.system, text: '[ERRO] ${data['message']}'));
              });
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      setState(() {
        _msgs.add(_ChatMsg(role: _MsgRole.system, text: '[ERRO] Conexao: $e'));
      });
    } finally {
      _activeClient?.close();
      _activeClient = null;
      if (_aiBuffer.isNotEmpty && !_stopRequested) {
        setState(() {
          _msgs.add(_ChatMsg(role: _MsgRole.ai, text: _aiBuffer.toString().trim()));
          _aiBuffer.clear();
        });
      }
      setState(() => _running = false);
      _saveSessions();
      _scrollToBottom();
    }
  }

  // ── Parar agente ──────────────────────────────────────────────────────────

  void _stopAgent() {
    if (!_running) return;
    _stopRequested = true;
    _activeClient?.close();
    _activeClient = null;

    setState(() {
      _running = false;
      if (_aiBuffer.isNotEmpty) {
        _msgs.add(_ChatMsg(role: _MsgRole.ai, text: _aiBuffer.toString().trim()));
        _aiBuffer.clear();
      }
      _msgs.add(_ChatMsg(role: _MsgRole.system, text: 'Interrompido pelo usuario'));
    });
    _scrollToBottom();
  }

  // ── Undo: remove ultimo par user+ai e reverte alterações reais ─────────────

  Future<void> _undo() async {
    if (_running || _msgs.isEmpty) return;

    int? lastRunId;
    for (var m in _msgs.reversed) {
      if (m.runId != null) {
        lastRunId = m.runId;
        break;
      }
    }

    if (lastRunId != null) {
      final snapshotService = ChatSnapshotService.instance;
      try {
        await snapshotService.restoreSnapshot(lastRunId);
      } catch (_) {}

      try {
        await ApiClient.instance.post('/api/mimo/run/$lastRunId/approve', data: {'run_id': lastRunId, 'approve': false});
      } catch (_) {}

      try {
        await ApiClient.instance.delete('/api/mimo/run/$lastRunId');
      } catch (_) {}

      await snapshotService.deleteSnapshot(lastRunId);
    }

    setState(() {
      while (_msgs.isNotEmpty && _msgs.last.role != _MsgRole.user) {
        _msgs.removeLast();
      }
      if (_msgs.isNotEmpty && _msgs.last.role == _MsgRole.user) {
        _promptCtrl.text = _msgs.removeLast().text;
      }
    });
    _saveSessions();
    WorkspaceEvents.notifyFileChanges();
  }

  // ── Delete: remove chat inteiro do histórico ────────────────────────────────

  Future<void> _deleteChat(int runId) async {
    if (_running) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: const Text('Excluir interação', style: TextStyle(color: RdcTheme.textPrimary)),
        content: const Text('Deseja realmente excluir esta interação? As alterações serão revertidas.',
            style: TextStyle(color: RdcTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: RdcTheme.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final snapshotService = ChatSnapshotService.instance;
    if (snapshotService.hasSnapshot(runId)) {
      try {
        await snapshotService.restoreSnapshot(runId);
      } catch (_) {}
    }

    try {
      await ApiClient.instance.delete('/api/mimo/run/$runId');
    } catch (_) {}

    await snapshotService.deleteSnapshot(runId);

    setState(() {
      _msgs.removeWhere((m) => m.runId == runId);
    });
    _saveSessions();
    WorkspaceEvents.notifyFileChanges();
 
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interação excluída'), backgroundColor: RdcTheme.danger),
      );
    }
  }

  // ── Envio do prompt ─────────────────────────────────────────────────────────

  Future<void> _runPrompt() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _currentSession == null) return;
    _promptCtrl.clear();

    _stopRequested = false;
    setState(() {
      _running = true;
      _msgs.add(_ChatMsg(role: _MsgRole.user, text: prompt));
      _aiBuffer.clear();
      _liveRunId = null;
    });

    // Atualizar título se for a primeira mensagem
    if (_currentSession!.title == 'Novo chat') {
      setState(() {
        _currentSession!.title = prompt.length > 40 ? '${prompt.substring(0, 40)}...' : prompt;
      });
      _saveSessions();
    }

    _scrollToBottom();

    try {
      final agentUrl = await SecureStorage.getAgentUrl() ?? '';
      final token = await SecureStorage.getAccessToken() ?? '';
      final aiModel = await SecureStorage.getAiModel();
      final aiKey = await SecureStorage.getAiApiKey();

      // Salvar snapshot antes da run
      try {
        await ChatSnapshotService.instance.saveSnapshot(0, widget.projectId, [], '');
      } catch (_) {}

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
      _activeClient = http_io.IOClient(httpClient);
      final response = await _activeClient!.send(request);

      int? _aiMsgIndex;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (_stopRequested) break;
        for (final line in chunk.split('\n')) {
          if (_stopRequested) break;
          if (!line.startsWith('data: ')) continue;
          try {
            final data = jsonDecode(line.substring(6));
            final type = data['type'];

            if (type == 'start') {
              _liveRunId = data['run_id'];
              try {
                final snapshotService = ChatSnapshotService.instance;
                await snapshotService.updateRunId(0, _liveRunId!);
              } catch (_) {}

            } else if (type == 'output') {
              final text = (data['line'] as String?)?.replaceAll('\\n', '\n') ?? '';
              if (text.trim().isEmpty) continue;

              final lower = text.toLowerCase();
              if (lower.contains('api key') || lower.contains('api_key') ||
                  lower.contains('chave') || lower.contains('configura') ||
                  lower.contains('selecionado') || lower.contains('grátis') ||
                  lower.contains('mimo engine') || lower.contains('modelo:') ||
                  lower.contains('projeto:')) continue;

              setState(() {
                if (_isBlockLine(text)) {
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.block, text: text.trim()));
                } else if (text.contains('[REASONING]') || text.contains('[PENSANDO]')) {
                  if (_aiMsgIndex != null && _aiBuffer.isNotEmpty) {
                    final idx = _aiMsgIndex!;
                    if (idx < _msgs.length) {
                      _msgs[idx] = _msgs[idx].copyWith(text: _aiBuffer.toString().trim());
                    }
                    _aiBuffer.clear();
                    _aiMsgIndex = null;
                  }
                  _msgs.add(_ChatMsg(role: _MsgRole.reasoning, text: text.replaceAll(RegExp(r'\[REASONING\]|\[PENSANDO\]'), '').trim()));
                } else if (text.startsWith('[ERRO]') || text.startsWith('[AVISO]')) {
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
                  _aiBuffer.write(text);
                  if (_aiMsgIndex == null) {
                    _msgs.add(_ChatMsg(role: _MsgRole.ai, text: ''));
                    _aiMsgIndex = _msgs.length - 1;
                  } else {
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
                  _msgs.removeAt(_aiMsgIndex!);
                  _aiMsgIndex = null;
                }

                final fileCount = files.length;
                final fileNames = fileCount > 0
                    ? files.map((f) => f.split(RegExp(r'[/\\]')).last).take(3).join(', ')
                    : '';
                String summary = 'Concluido em ${elapsed}s';
                if (fileCount > 0) {
                  summary += ' | $fileCount arquivo${fileCount > 1 ? "s" : ""} modificado${fileCount > 1 ? "s" : ""}';
                  if (fileCount <= 3) summary += '\n  $fileNames';
                  else if (fileCount > 3) summary += '\n  $fileNames... +${fileCount - 3}';
                }

                _msgs.add(_ChatMsg(
                  role: _MsgRole.system,
                  text: summary,
                  runId: runId,
                  filesChanged: files,
                  canApprove: files.isNotEmpty,
                ));
              });
              _saveSessions();
              _scrollToBottom();
              WorkspaceEvents.notifyFileChanges();

            } else if (type == 'error') {
              setState(() {
                _msgs.add(_ChatMsg(role: _MsgRole.system, text: '[ERRO] ${data['message']}'));
              });
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      setState(() {
        _msgs.add(_ChatMsg(role: _MsgRole.system, text: '[ERRO] Conexao: $e'));
      });
    } finally {
      _activeClient?.close();
      _activeClient = null;
      if (_aiBuffer.isNotEmpty && !_stopRequested) {
        setState(() {
          _msgs.add(_ChatMsg(role: _MsgRole.ai, text: _aiBuffer.toString().trim()));
          _aiBuffer.clear();
        });
      }
      setState(() => _running = false);
      _saveSessions();
      _scrollToBottom();
    }
  }

  // ── Aprovar / Rejeitar ──────────────────────────────────────────────────────

  Future<void> _approve(int runId, bool approve) async {
    try {
      await ApiClient.instance.post('/api/mimo/run/$runId/approve',
          data: {'run_id': runId, 'approve': approve});
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
      _saveSessions();
      WorkspaceEvents.notifyFileChanges();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Alteracoes aplicadas' : 'Alteracoes revertidas'),
        backgroundColor: approve ? RdcTheme.success : RdcTheme.danger,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: RdcTheme.danger));
    }
  }

  // ── Detecção de blocos de ferramenta ────────────────────────────────────────

  static bool _isBlockLine(String text) {
    final t = text.trim();
    return t.startsWith('[READ]') ||
           t.startsWith('[WRITE]') ||
           t.startsWith('[EDIT]') ||
           t.startsWith('[RUN]') ||
           t.startsWith('[SEARCH]') ||
           t.startsWith('[AI-SEARCH]') ||
           t.startsWith('Executando:');
  }

  // ── Drawer de chats ─────────────────────────────────────────────────────────

  void _openChatsDrawer() {
    setState(() => _drawerOpen = true);
    _drawerCtrl.forward();
  }

  void _closeChatsDrawer() {
    _drawerCtrl.reverse().then((_) {
      if (mounted) setState(() => _drawerOpen = false);
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenW = MediaQuery.of(context).size.width;
    return Stack(children: [
      // ── Conteúdo principal ───────────────────────────────────────────
      Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: RdcTheme.bg800,
        child: Row(children: [
          // Botão de lista de chats
          GestureDetector(
            onTap: _openChatsDrawer,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: RdcTheme.bg700,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: RdcTheme.bg500),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 16, height: 2, color: RdcTheme.textMuted),
                  const SizedBox(height: 3),
                  Container(width: 16, height: 2, color: RdcTheme.textMuted),
                  const SizedBox(height: 3),
                  Container(width: 16, height: 2, color: RdcTheme.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _currentSession?.title ?? 'Novo chat',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Novo chat
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: RdcTheme.textMuted, size: 20),
            tooltip: 'Novo chat',
            onPressed: _newSession,
          ),
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
                  onDelete: (id) => _deleteChat(id),
                ),
              ),
      ),

      // Quick prompts
      if (!_running)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            _Chip('Adicionar testes', _promptCtrl, onSubmit: _runPrompt),
            _Chip('Refatorar código', _promptCtrl, onSubmit: _runPrompt),
            _Chip('Adicionar logging', _promptCtrl, onSubmit: _runPrompt),
            _Chip('Documentar funções', _promptCtrl, onSubmit: _runPrompt),
            _Chip('Listar arquivos', _promptCtrl, onSubmit: _runPrompt),
          ]),
        ),

      // Input bar
      Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        color: RdcTheme.bg800,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Modelo ativo
          if (_aiModelName != 'Nenhum modelo')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 12, color: RdcTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  _running ? 'Rodando com $_aiModelName...' : 'Usando $_aiModelName',
                  style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted),
                ),
                if (_running) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: RdcTheme.primary),
                  ),
                ],
              ]),
            ),
          Row(children: [
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
              onTap: _running ? _stopAgent : _runPrompt,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: _running ? null : RdcTheme.primaryGradient,
                  color: _running ? RdcTheme.danger.withOpacity(0.15) : null,
                  border: _running ? Border.all(color: RdcTheme.danger.withOpacity(0.5)) : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _running ? Icons.stop_rounded : Icons.send_rounded,
                  color: _running ? RdcTheme.danger : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ]),
        ]),
      ),
      // ── fim Column principal ─────────────────────────────────────────────
      ]),

      // ── Backdrop escuro quando drawer aberto ───────────────────────────────
      if (_drawerOpen)
        GestureDetector(
          onTap: _closeChatsDrawer,
          child: AnimatedBuilder(
            animation: _drawerCtrl,
            builder: (_, __) => Container(
              color: Colors.black.withValues(alpha: 0.5 * _drawerCtrl.value),
            ),
          ),
        ),

      // ── Drawer lateral animado ─────────────────────────────────────────────
      if (_drawerOpen)
        SlideTransition(
          position: _drawerAnim,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: screenW * 0.75,
              child: Material(
                color: Colors.transparent,
                child: _ChatsDrawer(
                  sessions: _sessions,
                  currentSession: _currentSession,
                  onSelect: (s) { _switchSession(s); _closeChatsDrawer(); },
                  onDelete: (s) async { await _deleteSession(s); _closeChatsDrawer(); },
                  onRename: _renameSession,
                  onNew: () { _newSession(); _closeChatsDrawer(); },
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ── Drawer de chats ─────────────────────────────────────────────────────────

class _ChatsDrawer extends StatelessWidget {
  final List<_ChatSession> sessions;
  final _ChatSession? currentSession;
  final void Function(_ChatSession) onSelect;
  final void Function(_ChatSession) onDelete;
  final void Function(_ChatSession) onRename;
  final VoidCallback onNew;

  const _ChatsDrawer({
    required this.sessions,
    required this.currentSession,
    required this.onSelect,
    required this.onDelete,
    required this.onRename,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: RdcTheme.bg800,
          borderRadius: const BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(5, 0),
            ),
          ],
        ),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Text('Chats', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, color: RdcTheme.primary, size: 22),
                tooltip: 'Novo chat',
                onPressed: onNew,
              ),
            ]),
          ),
          const Divider(height: 1, color: RdcTheme.bg500),

          // Lista de chats
          Expanded(
            child: sessions.isEmpty
              ? Center(child: Text('Nenhum chat', style: GoogleFonts.inter(color: RdcTheme.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sessions.length,
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final isSelected = s.id == currentSession?.id;
                    return ListTile(
                      leading: Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: isSelected ? RdcTheme.primary : RdcTheme.textMuted,
                      ),
                      title: Text(
                        s.title,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isSelected ? RdcTheme.textPrimary : RdcTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${s.messages.where((m) => m.role == _MsgRole.user).length} mensagem(s)',
                        style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        color: RdcTheme.textMuted,
                        tooltip: 'Excluir',
                        onPressed: () => onDelete(s),
                      ),
                      selected: isSelected,
                      selectedTileColor: RdcTheme.primary.withOpacity(0.1),
                      contentPadding: const EdgeInsets.only(left: 16, right: 4, top: 2, bottom: 2),
                      onTap: () => onSelect(s),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
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
  final VoidCallback? onSubmit;
  const _Chip(this.text, this.ctrl, {this.onSubmit});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          ctrl.text = text;
          onSubmit?.call();
        },
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
  final void Function(int)? onDelete;
  const _MessageBubble({required this.msg, required this.onApprove, required this.onReject, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == _MsgRole.user;
    final isSystem = msg.role == _MsgRole.system;
    final isReasoning = msg.role == _MsgRole.reasoning;
    final isBlock = msg.role == _MsgRole.block;

    if (isSystem) {
      return _SystemMsg(msg: msg, onApprove: onApprove, onReject: onReject, onDelete: onDelete);
    }
    if (isReasoning) {
      return _CollapsibleReasoning(text: msg.text);
    }
    if (isBlock) {
      return _CollapsibleBlock(rawText: msg.text);
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
          if (msg.filesChanged.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: msg.filesChanged.map((f) =>
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: f));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copiado: $f'), duration: const Duration(seconds: 1)),
                  );
                },
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
}

class _SystemMsg extends StatelessWidget {
  final _ChatMsg msg;
  final void Function(int) onApprove;
  final void Function(int) onReject;
  final void Function(int)? onDelete;
  const _SystemMsg({required this.msg, required this.onApprove, required this.onReject, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isError = msg.text.startsWith('[ERRO]');
    final isInterrupted = msg.text.contains('Interrompido');
    final isApplied = msg.text.contains('aplicadas');
    final isReverted = msg.text.contains('revertidas');
    final hasFiles = msg.filesChanged.isNotEmpty;

    final (icon, iconColor, bgColor, borderColor) = isError
        ? (Icons.error_outline, RdcTheme.danger, RdcTheme.danger.withOpacity(0.08), RdcTheme.danger.withOpacity(0.3))
        : isInterrupted
            ? (Icons.stop_circle_outlined, Colors.orange, Colors.orange.withOpacity(0.08), Colors.orange.withOpacity(0.3))
            : isApplied
                ? (Icons.check_circle_outline, RdcTheme.success, RdcTheme.success.withOpacity(0.08), RdcTheme.success.withOpacity(0.3))
                : isReverted
                    ? (Icons.undo_outlined, Colors.amber, Colors.amber.withOpacity(0.08), Colors.amber.withOpacity(0.3))
                    : (Icons.info_outline, RdcTheme.textMuted, RdcTheme.bg700.withOpacity(0.5), RdcTheme.bg500.withOpacity(0.5));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg.text,
              style: GoogleFonts.inter(fontSize: 12, color: isError ? RdcTheme.danger : RdcTheme.textSecondary),
            ),
          ),
        ]),
        if (hasFiles) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: msg.filesChanged.map((f) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: RdcTheme.bg600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.insert_drive_file_outlined, size: 10, color: RdcTheme.textMuted),
                const SizedBox(width: 3),
                Text(
                  f.split(RegExp(r'[/\\]')).last,
                  style: GoogleFonts.firaCode(fontSize: 10, color: RdcTheme.textSecondary),
                ),
              ]),
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
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Excluir interação',
                onPressed: () => onDelete!(msg.runId!),
                color: RdcTheme.textMuted,
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

// ── Reasoning colapsável ──────────────────────────────────────────────────────

class _CollapsibleReasoning extends StatefulWidget {
  final String text;
  const _CollapsibleReasoning({required this.text});

  @override
  State<_CollapsibleReasoning> createState() => _CollapsibleReasoningState();
}

class _CollapsibleReasoningState extends State<_CollapsibleReasoning> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: RdcTheme.primary.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lightbulb_outline, size: 13, color: RdcTheme.primary.withOpacity(0.7)),
            const SizedBox(width: 5),
            Text('Raciocínio interno',
                style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.primary.withOpacity(0.7), fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 14, color: RdcTheme.textMuted),
          ]),
          if (_expanded) ...[
            const SizedBox(height: 6),
            Text(widget.text,
                style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted, fontStyle: FontStyle.italic, height: 1.5)),
          ],
        ]),
      ),
    );
  }
}

// ── Bloco colapsável de ferramenta ─────────────────────────────────────────────

class _CollapsibleBlock extends StatefulWidget {
  final String rawText;
  const _CollapsibleBlock({required this.rawText});

  @override
  State<_CollapsibleBlock> createState() => _CollapsibleBlockState();
}

class _CollapsibleBlockState extends State<_CollapsibleBlock> {
  bool _expanded = false;

  static const _kRead     = 'READ';
  static const _kWrite    = 'WRITE';
  static const _kEdit     = 'EDIT';
  static const _kRun      = 'RUN';
  static const _kSearch   = 'SEARCH';
  static const _kAiSearch = 'AI-SEARCH';
  static const _kExec     = 'EXEC';

  // ── Parsing ────────────────────────────────────────────────────────────────

  ({String type, IconData icon, Color color, String label, String title, String body}) get _parsed {
    final raw = widget.rawText.trim();
    if (raw.startsWith('[READ]'))      return _make(_kRead,     raw.substring(6).trim());
    if (raw.startsWith('[WRITE]'))     return _make(_kWrite,    raw.substring(7).trim());
    if (raw.startsWith('[EDIT]'))      return _make(_kEdit,     raw.substring(6).trim());
    if (raw.startsWith('[RUN]'))       return _make(_kRun,      raw.substring(5).trim());
    if (raw.startsWith('[SEARCH]'))    return _make(_kSearch,   raw.substring(8).trim());
    if (raw.startsWith('[AI-SEARCH]')) return _make(_kAiSearch, raw.substring(11).trim());
    if (raw.startsWith('Executando:')) return _make(_kExec,     raw.substring(10).trim());
    return _make(_kRun, raw);
  }

  ({String type, IconData icon, Color color, String label, String title, String body}) _make(String type, String rest) {
    final (icon, color, label) = switch (type) {
      _kRead     => (Icons.insert_drive_file_outlined, const Color(0xFF4FC3F7), 'LER'),
      _kWrite    => (Icons.create_outlined,            const Color(0xFF81C784), 'ESCRITA'),
      _kEdit     => (Icons.edit_outlined,              const Color(0xFF69F0AE), 'EDIÇÃO'),
      _kRun || _kExec
                 => (Icons.terminal,                   const Color(0xFFFFB74D), type == _kExec ? 'EXEC' : 'EXECUTAR'),
      _kSearch   => (Icons.manage_search,              const Color(0xFFCE93D8), 'BUSCA'),
      _kAiSearch => (Icons.auto_awesome_outlined,      const Color(0xFF80DEEA), 'IA BUSCA'),
      _          => (Icons.build_outlined,             const Color(0xFF90A4AE), 'FERRAMENTA'),
    };
    final title = _extractTitle(type, rest);
    final body  = _extractBody(type, rest);
    return (type: type, icon: icon, color: color, label: label, title: title, body: body);
  }

  String _extractTitle(String type, String rest) {
    // Tenta extrair do XML <path>...</path>
    final pathM = RegExp(r'<path>(.*?)</path>').firstMatch(rest);
    if (pathM != null) {
      return pathM.group(1)!.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
    }
    // Primeiro token antes de espaço ou tag XML
    final clean = rest.replaceAll(RegExp(r'<[^>]+>.*'), '').trim();
    final token = (clean.isNotEmpty ? clean : rest).split(RegExp(r'[\s]')).first;
    return token.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? token;
  }

  String _extractBody(String type, String rest) {
    if (type == _kRead) {
      // Prioriza <entries>
      final entriesM = RegExp(r'<entries>(.*?)</entries>', dotAll: true).firstMatch(rest);
      if (entriesM != null) return entriesM.group(1)!.trim();
      // Remove tags XML e retorna conteúdo
      final noXml = rest.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      return noXml.isNotEmpty ? noXml : rest;
    }
    if (type == _kWrite || type == _kEdit) {
      // Remove primeiro token (path) e retorna o código
      final idx = rest.indexOf('\n');
      if (idx > 0) return rest.substring(idx + 1).trim();
      // sem quebra de linha — mostra tudo
      return rest;
    }
    return rest;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    final hasBody = p.body.isNotEmpty && p.body != p.title;

    return GestureDetector(
      onTap: hasBody ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 0),
        decoration: BoxDecoration(
          color: p.color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.color.withValues(alpha: 0.22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              // Ícone da ferramenta
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: p.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(p.icon, size: 15, color: p.color),
              ),
              const SizedBox(width: 10),
              // Label + título
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    p.label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: p.color,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    p.title,
                    style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ]),
              ),
              // Chevron expandir/colapsar
              if (hasBody)
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: p.color.withValues(alpha: 0.7),
                  ),
                ),
            ]),
          ),

          // ── Corpo expandido ─────────────────────────────────────────────────
          if (_expanded && hasBody)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Divider(height: 1, color: p.color.withValues(alpha: 0.15)),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: SelectableText(
                  p.body,
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: RdcTheme.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}
