/// RDC — Editor de código com syntax highlight
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../workspace/workspace_page.dart';

class EditorPage extends StatefulWidget {
  final int projectId;
  final String? filePath;
  final String? fileName;

  const EditorPage({
    super.key,
    required this.projectId,
    this.filePath,
    this.fileName,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _ctrl = TextEditingController();
  final _undoHistory = <String>[];
  String _previousText = '';
  String? _language;
  bool _loading = false;
  bool _modified = false;
  bool _readOnly = false;
  String? _error;
  String? _currentPath;
  Timer? _pollTimer;
  StreamSubscription? _fileChangeSub;

  @override
  void didUpdateWidget(EditorPage old) {
    super.didUpdateWidget(old);
    if (widget.filePath != old.filePath && widget.filePath != null) {
      _loadFile();
      _startPolling();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.filePath != null) {
      _loadFile();
      _startPolling();
    }
    _fileChangeSub = WorkspaceEvents.fileChanges.listen((_) {
      if (mounted && widget.filePath != null && !_modified && !_loading) {
        _loadFile();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _fileChangeSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _loading || widget.filePath == null || _readOnly) return;
      if (_modified) return; // Não sobrescreve se o usuário tiver rascunho modificado
      
      try {
        final res = await ApiClient.instance.get(
          '/api/files/${widget.projectId}/read',
          queryParameters: {'path': widget.filePath},
        );
        if (res.statusCode == 200 && mounted) {
          final newContent = res.data['content'] ?? '';
          if (newContent != _ctrl.text && !_modified) {
            setState(() {
              _ctrl.text = newContent;
              _previousText = newContent;
            });
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _loadFile() async {
    if (widget.filePath == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.instance.get(
        '/api/files/${widget.projectId}/read',
        queryParameters: {'path': widget.filePath},
      );
      if (res.statusCode == 200) {
        _undoHistory.clear();
        _ctrl.text = res.data['content'] ?? '';
        _previousText = _ctrl.text;
        setState(() {
          _language = res.data['language'];
          _currentPath = widget.filePath;
          _modified = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (e is DioException && e.response?.data != null) {
          setState(() { _error = 'Server Error: ${e.response?.data}'; _loading = false; });
        } else {
          setState(() { _error = e.toString(); _loading = false; });
        }
      }
    }
  }

  Future<void> _save() async {
    if (_currentPath == null) return;
    try {
      await ApiClient.instance.put(
        '/api/files/${widget.projectId}/write',
        data: {
          'project_id': widget.projectId,
          'relative_path': _currentPath,
          'content': _ctrl.text,
        },
      );
      setState(() => _modified = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Arquivo salvo'), backgroundColor: RdcTheme.success, duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: RdcTheme.danger));
      }
    }
  }

  void _onChanged(String val) {
    _undoHistory.add(_previousText);
    if (_undoHistory.length > 100) _undoHistory.removeAt(0);
    _previousText = val;
    setState(() => _modified = true);
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    final prev = _undoHistory.removeLast();
    _previousText = prev;
    _ctrl.value = TextEditingValue(text: prev, selection: TextSelection.collapsed(offset: prev.length));
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _ctrl.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ Código copiado'), backgroundColor: RdcTheme.success, duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.filePath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.touch_app_outlined, size: 64, color: RdcTheme.textMuted),
            const SizedBox(height: 16),
            Text('Selecione um arquivo na aba Arquivos', style: GoogleFonts.inter(color: RdcTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Erro: $_error', style: const TextStyle(color: RdcTheme.danger)));

    return Column(
      children: [
        // Toolbar do editor
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: RdcTheme.bg800,
          child: Row(children: [
            const Icon(Icons.insert_drive_file_outlined, size: 14, color: RdcTheme.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.fileName ?? _currentPath ?? '',
                style: GoogleFonts.firaCode(fontSize: 12, color: _modified ? RdcTheme.warning : RdcTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_modified) const Text('●', style: TextStyle(color: RdcTheme.warning, fontSize: 16)),
            const SizedBox(width: 8),
            _EditorBtn(icon: Icons.undo, tooltip: 'Desfazer', onTap: _undo),
            _EditorBtn(icon: Icons.content_copy, tooltip: 'Copiar', onTap: _copy),
            _EditorBtn(
              icon: _readOnly ? Icons.lock : Icons.lock_open,
              tooltip: _readOnly ? 'Modo Somente Leitura' : 'Modo Edição',
              onTap: () => setState(() => _readOnly = !_readOnly),
            ),
            _EditorBtn(icon: Icons.save_outlined, tooltip: 'Salvar (Ctrl+S)', onTap: _save, color: RdcTheme.primary),
          ]),
        ),
        const Divider(height: 1),

        // Área de edição
        Expanded(
          child: _readOnly
              ? _HighlightView(code: _ctrl.text, language: _language)
              : _EditableView(controller: _ctrl, language: _language, onChanged: _onChanged),
        ),
      ],
    );
  }
}

// ── Visualizador com syntax highlight ────────────────────────────────────────

class _HighlightView extends StatelessWidget {
  final String code;
  final String? language;
  const _HighlightView({required this.code, this.language});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: HighlightView(
        code,
        language: language ?? 'plaintext',
        theme: atomOneDarkTheme,
        padding: const EdgeInsets.all(16),
        textStyle: GoogleFonts.firaCode(fontSize: 13, height: 1.5),
      ),
    );
  }
}

// ── Editor editável com números de linha ──────────────────────────────────────

class _EditableView extends StatefulWidget {
  final TextEditingController controller;
  final String? language;
  final void Function(String) onChanged;

  const _EditableView({
    required this.controller,
    required this.onChanged,
    this.language,
  });

  @override
  State<_EditableView> createState() => _EditableViewState();
}

class _EditableViewState extends State<_EditableView> {
  final _scrollController = ScrollController();

  static const double _fontSize = 13.0;
  static const double _lineHeight = 1.5;
  static const double _lineHeightPx = _fontSize * _lineHeight; // 19.5
  static const double _verticalPadding = 16.0;
  static const double _gutterWidth = 44.0;
  static const double _dividerWidth = 1.0;

  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateLineCount);
    _updateLineCount();
  }

  @override
  void didUpdateWidget(covariant _EditableView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_updateLineCount);
      widget.controller.addListener(_updateLineCount);
      _updateLineCount();
    }
  }

  void _updateLineCount() {
    final count = '\n'.allMatches(widget.controller.text).length + 1;
    if (count != _lineCount && mounted) {
      setState(() => _lineCount = count);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateLineCount);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Calha dos números de linha ─────────────────────────────
        SizedBox(
          width: _gutterWidth,
          child: ScrollConfiguration(
            behavior: const _NoBounceScrollBehavior(),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const NeverScrollableScrollPhysics(), // escravo do scrollController
              padding: EdgeInsets.only(
                top: _verticalPadding,
                bottom: _verticalPadding,
                left: 4,
                right: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  _lineCount,
                  (i) => SizedBox(
                    height: _lineHeightPx,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.firaCode(
                        fontSize: _fontSize,
                        color: RdcTheme.textMuted,
                        height: _lineHeight,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        Container(width: _dividerWidth, color: RdcTheme.bg500),

        // ── Campo de texto ─────────────────────────────────────────
        Expanded(
          child: ScrollConfiguration(
            behavior: const _NoBounceScrollBehavior(),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(
                top: _verticalPadding,
                bottom: _verticalPadding,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: 3000, // Largura suficiente para evitar quebra de linha
                  child: IntrinsicHeight(
                    child: TextField(
                      controller: widget.controller,
                      maxLines: null,
                      // NÃO use expands: true aqui — conflita com SingleChildScrollView
                      onChanged: widget.onChanged,
                      keyboardType: TextInputType.multiline,
                      style: GoogleFonts.firaCode(
                        fontSize: _fontSize,
                        color: RdcTheme.textPrimary,
                        height: _lineHeight,
                      ),
                      strutStyle: const StrutStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                        forceStrutHeight: true, // <-- CRÍTICO: garante altura de linha exata
                      ),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoBounceScrollBehavior extends ScrollBehavior {
  const _NoBounceScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

class _EditorBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _EditorBtn({required this.icon, required this.tooltip, required this.onTap, this.color = RdcTheme.textSecondary});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 18, color: color)),
    ),
  );
}
