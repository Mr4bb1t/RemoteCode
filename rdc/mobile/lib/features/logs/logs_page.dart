/// RDC — Logs em tempo real via WebSocket
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? _mainFile;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mainFile = prefs.getString('rdc_main_file_${widget.projectId}');
      _activeProcessId = prefs.getString('rdc_process_${widget.projectId}');
    });
    if (_activeProcessId != null) {
      _connectToProcess(_activeProcessId!);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_mainFile != null) prefs.setString('rdc_main_file_${widget.projectId}', _mainFile!);
    if (_activeProcessId != null) prefs.setString('rdc_process_${widget.projectId}', _activeProcessId!);
  }

  void _selectMainFile() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FilePickerDialog(projectId: widget.projectId),
    );
    if (result != null) {
      setState(() => _mainFile = result);
      _savePrefs();
    }
  }

  Future<void> _stopProcess() async {
    if (_activeProcessId == null) return;
    final processId = _activeProcessId;
    
    // Força limpeza do front-end independente do backend
    setState(() {
      _lines.add(const _LogLine('\r\n[Parando processo...]\r\n', LogLevel.warning));
      _activeProcessId = null;
    });
    _savePrefs();
    _ws?.disconnect();

    try {
      await ApiClient.instance.post('/api/processes/stop/$processId');
      setState(() {
        _lines.add(const _LogLine('\r\n[Sinal de parada confirmado]\r\n', LogLevel.info));
      });
    } catch (e) {
      setState(() {
        _lines.add(_LogLine('\r\n[Aviso: Não foi possível confirmar parada no servidor: $e]\r\n', LogLevel.error));
      });
    }
  }

  Future<void> _startProcess(String command) async {
    if (_activeProcessId != null) {
      await _stopProcess();
      await Future.delayed(const Duration(milliseconds: 500)); // Espera porta liberar
    }
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
      _savePrefs();
      _connectToProcess(processId);
    } catch (e) {
      setState(() => _lines.add(_LogLine('[Erro: $e]', LogLevel.error)));
    }
  }

  void _connectToProcess(String processId) {
    _ws?.disconnect();
    _ws = WsClient(
      path: '/ws/logs/$processId',
      autoReconnect: false,
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

  List<Widget> _buildQuickCommands() {
    final file = _mainFile ?? '';
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
          onPressed: () => _startProcess(cmd),
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
              Text(file.isEmpty ? 'Selecionar Arquivo Principal' : file, style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.primary)),
            ]),
          ),
        ),
      )
    );

    if (file.isEmpty) return btns;

    if (ext == 'dart') {
      btns.add(btn('▶ Run', 'flutter run -t $file', RdcTheme.success));
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
    return Column(children: [
      // Quick commands & File Picker
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: RdcTheme.bg800,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _buildQuickCommands()),
        ),
      ),

      // Status bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: RdcTheme.bg900,
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _connected ? RdcTheme.success : RdcTheme.textMuted, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_connected ? 'Processo: $_activeProcessId' : 'Inativo',
              style: GoogleFonts.firaCode(fontSize: 11, color: _connected ? RdcTheme.success : RdcTheme.textMuted)),
          const Spacer(),
          Row(children: [
            const Text('Auto', style: TextStyle(color: RdcTheme.textMuted, fontSize: 11)),
            Switch(value: _autoScroll, onChanged: (v) => setState(() => _autoScroll = v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ]),
          IconButton(
            icon: const Icon(Icons.stop_circle, size: 18, color: RdcTheme.danger),
            tooltip: 'Parar Processo',
            onPressed: _stopProcess,
          ),
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
                  Text('Selecione um arquivo principal e inicie um comando.', style: GoogleFonts.inter(color: RdcTheme.textMuted)),
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

class _FilePickerDialog extends StatefulWidget {
  final int projectId;
  const _FilePickerDialog({required this.projectId});
  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  String _currentPath = '';
  List<dynamic> _items = [];
  bool _loading = false;
  
  @override
  void initState() {
    super.initState();
    _load('');
  }
  
  Future<void> _load(String path) async {
    setState(() { _loading = true; _currentPath = path; });
    try {
      final res = await ApiClient.instance.get('/api/files/${widget.projectId}/tree', queryParameters: {'path': path});
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _items = res.data;
          // Ordena pastas primeiro
          _items.sort((a, b) {
            if (a['is_dir'] && !b['is_dir']) return -1;
            if (!a['is_dir'] && b['is_dir']) return 1;
            return a['name'].toString().compareTo(b['name'].toString());
          });
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: RdcTheme.bg800,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        children: [
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
             child: Row(children: [
               if (_currentPath.isNotEmpty)
                 IconButton(
                   icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                   onPressed: () {
                     final parts = _currentPath.split('/');
                     parts.removeLast();
                     _load(parts.join('/'));
                   },
                 ),
               Expanded(
                 child: Text(
                   _currentPath.isEmpty ? 'Raiz do Projeto' : _currentPath, 
                   style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
               IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
             ]),
           ),
           const Divider(height: 1, color: RdcTheme.bg500),
           Expanded(
             child: _loading 
               ? const Center(child: CircularProgressIndicator()) 
               : ListView.builder(
                 itemCount: _items.length,
                 itemBuilder: (ctx, i) {
                   final item = _items[i];
                   final bool isDir = item['is_dir'] == true;
                   return ListTile(
                     leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file, color: isDir ? RdcTheme.warning : RdcTheme.textMuted, size: 20),
                     title: Text(item['name'], style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13)),
                     onTap: () {
                       if (isDir) {
                         _load(item['path']);
                       } else {
                         Navigator.pop(context, item['path']);
                       }
                     },
                   );
                 },
               ),
           ),
        ],
      ),
    );
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
