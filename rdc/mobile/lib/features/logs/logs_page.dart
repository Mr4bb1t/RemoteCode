/// RDC — Logs em tempo real via WebSocket
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/ws_client.dart';
import '../../core/theme/app_theme.dart';

class LogsPage extends StatefulWidget {
  final int projectId;
  const LogsPage({super.key, required this.projectId});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  final _lines = <_LogLine>[];
  WsClient? _ws;
  bool _connected = false;
  bool _autoScroll = true;
  String _cmdCtrl = '';
  String? _activeProcessId;

  // Comandos pré-definidos comuns
  static const _quickCommands = [
    ('npm run dev', 'Vite/React'),
    ('npm start', 'Node/React'),
    ('python main.py', 'Python'),
    ('uvicorn main:app --reload', 'FastAPI'),
    ('python manage.py runserver', 'Django'),
    ('flask run', 'Flask'),
    ('npm test', 'Jest'),
    ('pytest', 'Pytest'),
  ];

  Future<void> _startProcess(String command) async {
    final processId = const Uuid().v4().substring(0, 8);
    try {
      final parts = command.split(' ');
      await ApiClient.instance.post('/api/processes/start', data: {
        'process_id': processId,
        'command': parts,
        'cwd': '',
        'project_id': widget.projectId,
      });
      setState(() { _activeProcessId = processId; _lines.clear(); });
      _connectToProcess(processId);
    } catch (e) {
      setState(() => _lines.add(_LogLine('[Erro: $e]', LogLevel.error)));
    }
  }

  void _connectToProcess(String processId) {
    _ws?.disconnect();
    _ws = WsClient(
      path: '/ws/logs/$processId',
      onMessage: (msg) {
        final level = _detectLevel(msg);
        setState(() => _lines.add(_LogLine(msg, level)));
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
          });
        }
      },
      onDone: () => setState(() => _connected = false),
    );
    _ws!.connect().then((_) => setState(() => _connected = true));
  }

  LogLevel _detectLevel(String line) {
    final l = line.toLowerCase();
    if (l.contains('error') || l.contains('exception') || l.contains('traceback')) return LogLevel.error;
    if (l.contains('warning') || l.contains('warn')) return LogLevel.warning;
    if (l.contains('info') || l.contains('started') || l.contains('listening')) return LogLevel.info;
    return LogLevel.normal;
  }

  @override
  void dispose() {
    _ws?.disconnect();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      // Quick commands
      Container(
        height: 44,
        color: RdcTheme.bg800,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: _quickCommands.map((cmd) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => _startProcess(cmd.$1),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: RdcTheme.bg600,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: RdcTheme.bg500),
                ),
                child: Row(children: [
                  Text(cmd.$2, style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Text(cmd.$1, style: GoogleFonts.firaCode(fontSize: 11, color: RdcTheme.textSecondary)),
                ]),
              ),
            ),
          )).toList(),
        ),
      ),

      // Status bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: RdcTheme.bg900,
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _connected ? RdcTheme.success : RdcTheme.textMuted, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_connected ? 'Processo ativo: $_activeProcessId' : 'Inativo',
              style: GoogleFonts.firaCode(fontSize: 11, color: _connected ? RdcTheme.success : RdcTheme.textMuted)),
          const Spacer(),
          Row(children: [
            const Text('Auto-scroll', style: TextStyle(color: RdcTheme.textMuted, fontSize: 11)),
            Switch(value: _autoScroll, onChanged: (v) => setState(() => _autoScroll = v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ]),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 16, color: RdcTheme.textMuted),
            onPressed: () => Clipboard.setData(ClipboardData(text: _lines.map((l) => l.text).join(''))),
          ),
          IconButton(
            icon: const Icon(Icons.clear, size: 16, color: RdcTheme.textMuted),
            onPressed: () => setState(() => _lines.clear()),
          ),
        ]),
      ),

      // Área de logs
      Expanded(
        child: Container(
          color: const Color(0xFF0A0A12),
          child: _lines.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.receipt_long, size: 48, color: RdcTheme.textMuted),
                  const SizedBox(height: 12),
                  Text('Selecione um comando acima para iniciar', style: GoogleFonts.inter(color: RdcTheme.textMuted)),
                ]))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _LogTile(line: _lines[i]),
                ),
        ),
      ),

      // Input de comando customizado
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: RdcTheme.bg900,
        child: Row(children: [
          Text('\$ ', style: GoogleFonts.firaCode(fontSize: 14, color: RdcTheme.accent)),
          Expanded(
            child: TextField(
              onChanged: (v) => _cmdCtrl = v,
              style: GoogleFonts.firaCode(fontSize: 13, color: RdcTheme.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                isDense: true, contentPadding: EdgeInsets.zero, filled: false,
                hintText: 'Comando customizado...', hintStyle: TextStyle(color: RdcTheme.textMuted),
              ),
              onSubmitted: _startProcess,
            ),
          ),
          IconButton(icon: const Icon(Icons.play_arrow, color: RdcTheme.primary), onPressed: () => _startProcess(_cmdCtrl)),
        ]),
      ),
    ]);
  }
}

enum LogLevel { normal, info, warning, error }

class _LogLine {
  final String text;
  final LogLevel level;
  const _LogLine(this.text, this.level);
}

class _LogTile extends StatelessWidget {
  final _LogLine line;
  const _LogTile({required this.line});

  @override
  Widget build(BuildContext context) {
    final color = switch (line.level) {
      LogLevel.error => RdcTheme.danger,
      LogLevel.warning => RdcTheme.warning,
      LogLevel.info => RdcTheme.info,
      LogLevel.normal => const Color(0xFFD4D4D4),
    };
    return Text(line.text, style: GoogleFonts.firaCode(fontSize: 12, color: color, height: 1.4));
  }
}
