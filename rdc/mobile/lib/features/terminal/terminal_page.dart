/// RDC — Terminal interativo via WebSocket
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/ws_client.dart';
import '../../core/theme/app_theme.dart';

class TerminalPage extends StatefulWidget {
  final int projectId;
  const TerminalPage({super.key, required this.projectId});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _outputBuffer = StringBuffer();
  final _lines = <String>[];
  final _history = <String>[];
  int _historyIndex = -1;
  WsClient? _ws;
  bool _connected = false;
  String _selectedShell = 'powershell';
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4().substring(0, 8);
    _connect();
  }

  void _connect() {
    _ws?.disconnect();
    _ws = WsClient(
      path: '/ws/terminal/$_sessionId',
      queryParams: {'shell': _selectedShell},
      onMessage: (msg) {
        setState(() { _lines.add(msg); });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      },
      onError: (e) => setState(() { _lines.add('\r\n[Erro de conexão: $e]\r\n'); _connected = false; }),
      onDone: () => setState(() { _connected = false; }),
    );
    _ws!.connect().then((_) => setState(() => _connected = true));
  }

  void _send(String input) {
    if (input.isEmpty) return;
    _history.insert(0, input);
    _historyIndex = -1;
    _ws?.send(input + '\n');
    _inputController.clear();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _resize(int cols, int rows) {
    _ws?.sendJson({'type': 'resize', 'cols': cols, 'rows': rows});
  }

  @override
  void dispose() {
    _ws?.disconnect();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: RdcTheme.bg900,
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: _connected ? RdcTheme.success : RdcTheme.danger,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(_connected ? 'Conectado' : 'Desconectado',
                style: GoogleFonts.firaCode(fontSize: 11, color: _connected ? RdcTheme.success : RdcTheme.danger)),
            const SizedBox(width: 16),
            // Shell selector
            DropdownButton<String>(
              value: _selectedShell,
              dropdownColor: RdcTheme.bg700,
              style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.textSecondary),
              underline: const SizedBox(),
              items: ['powershell', 'cmd', 'bash'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() { _selectedShell = v; _lines.clear(); _sessionId = const Uuid().v4().substring(0, 8); });
                  _connect();
                }
              },
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.content_copy, size: 16, color: RdcTheme.textMuted),
              tooltip: 'Copiar output',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _lines.join('')));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Output copiado'), duration: Duration(seconds: 1)),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: RdcTheme.textMuted),
              tooltip: 'Limpar',
              onPressed: () => setState(() => _lines.clear()),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: RdcTheme.textMuted),
              tooltip: 'Reconectar',
              onPressed: _connect,
            ),
          ]),
        ),

        // Output do terminal
        Expanded(
          child: Container(
            color: const Color(0xFF0D0D14),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (ctx, i) => Text(
                _lines[i],
                style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFFD4D4D4), height: 1.4),
              ),
            ),
          ),
        ),

        // Input
        Container(
          color: RdcTheme.bg900,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Text('❯ ', style: GoogleFonts.firaCode(fontSize: 14, color: RdcTheme.accent)),
            Expanded(
              child: TextField(
                controller: _inputController,
                style: GoogleFonts.firaCode(fontSize: 13, color: RdcTheme.textPrimary),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                  hintText: 'Digite um comando...',
                  hintStyle: TextStyle(color: RdcTheme.textMuted, fontSize: 13),
                ),
                onSubmitted: _send,
              ),
            ),
            // Histórico
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 18, color: RdcTheme.textMuted),
              onPressed: () {
                if (_history.isEmpty) return;
                _historyIndex = (_historyIndex + 1).clamp(0, _history.length - 1);
                _inputController.text = _history[_historyIndex];
              },
            ),
            IconButton(
              icon: const Icon(Icons.send, size: 18, color: RdcTheme.primary),
              onPressed: () => _send(_inputController.text),
            ),
          ]),
        ),
      ],
    );
  }
}
