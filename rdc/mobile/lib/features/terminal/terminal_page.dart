/// RDC — Terminal interativo via WebSocket
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/ws_client.dart';
import '../../core/theme/app_theme.dart';

class TerminalPage extends StatefulWidget {
  final int projectId;
  const TerminalPage({super.key, required this.projectId});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _outputBuffer = StringBuffer();
  final _lines = <String>[];
  final _history = <String>[];
  int _historyIndex = -1;
  WsClient? _ws;
  bool _connected = false;
  String _selectedShell = 'cmd';
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4().substring(0, 8);
    _connect();
  }

  Future<void> _connect() async {
    _ws?.disconnect();
    
    String? cwd;
    try {
      final res = await ApiClient.instance.get('/api/projects/${widget.projectId}');
      if (res.statusCode == 200) {
        cwd = res.data['path'] as String?;
      }
    } catch (_) {}

    final queryParams = {'shell': _selectedShell};
    if (cwd != null && cwd.isNotEmpty) {
      queryParams['cwd'] = cwd;
    }

    _ws = WsClient(
      path: '/ws/terminal/$_sessionId',
      queryParams: queryParams,
      onMessage: (msg) {
        // Strip ANSI escape codes
        final cleanMsg = msg.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
        setState(() { _lines.add(cleanMsg); });
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
    _ws?.send(input + '\r\n');
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

  String? _mainFile;

  void _selectMainFile() {
    final ctrl = TextEditingController(text: _mainFile);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: RdcTheme.bg800,
        title: Text('Arquivo Principal', style: GoogleFonts.inter(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'ex: lib/main.dart ou app.py', 
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: RdcTheme.bg500)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: RdcTheme.primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.primary),
            onPressed: () {
              setState(() => _mainFile = ctrl.text.trim());
              Navigator.pop(c);
            },
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickCommands() {
    final file = _mainFile!;
    final ext = file.split('.').last.toLowerCase();
    
    List<Widget> btns = [];
    
    Widget btn(String label, String cmd, Color color) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            minimumSize: const Size(0, 26),
          ),
          onPressed: () => _send(cmd),
          child: Text(label, style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
    }

    btns.add(
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: InkWell(
          onTap: _selectMainFile,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(children: [
              const Icon(Icons.edit_document, size: 14, color: RdcTheme.primary),
              const SizedBox(width: 6),
              Text(file.isEmpty ? 'Definir' : file, style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.primary)),
            ]),
          ),
        ),
      )
    );

    if (file.isEmpty) return btns;

    if (ext == 'dart') {
      btns.add(btn('▶ Run', 'flutter run -t $file', RdcTheme.success));
      btns.add(btn('⚡ Reload', 'r', RdcTheme.info));
      btns.add(btn('🔄 Restart', 'R', RdcTheme.warning));
      btns.add(btn('🛑 Stop', 'q', RdcTheme.danger));
    } else if (ext == 'py') {
      btns.add(btn('▶ Run', 'python $file', RdcTheme.success));
      btns.add(btn('📦 reqs', 'pip install -r requirements.txt', RdcTheme.info));
    } else if (ext == 'js' || ext == 'ts') {
      final isTs = ext == 'ts';
      btns.add(btn('▶ Run', isTs ? 'npx ts-node $file' : 'node $file', RdcTheme.success));
      btns.add(btn('📦 install', 'npm install', RdcTheme.info));
      btns.add(btn('▶ start', 'npm start', RdcTheme.warning));
    } else {
      btns.add(btn('▶ Run', './$file', RdcTheme.success));
    }

    return btns;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

        // Comandos Específicos
        if (_mainFile != null && _mainFile!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: RdcTheme.bg800,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildQuickCommands()),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: RdcTheme.bg800,
            child: GestureDetector(
              onTap: _selectMainFile,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: RdcTheme.warning),
                  const SizedBox(width: 8),
                  Text('Nenhum arquivo principal selecionado. Toque para definir.', 
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.warning)),
                ],
              ),
            ),
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
