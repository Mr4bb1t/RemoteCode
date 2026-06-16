/// RDC — Preview Web com WebView e multi-dispositivo
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

class _DevicePreset {
  final String name;
  final IconData icon;
  final double width;
  final double scale;
  const _DevicePreset(this.name, this.icon, this.width, this.scale);
}

class PreviewPage extends StatefulWidget {
  final int projectId;
  const PreviewPage({super.key, required this.projectId});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _ports = [];
  int? _selectedPort;
  bool _loading = true;
  bool _webLoading = false;
  WebViewController? _webCtrl;
  String _currentUrl = '';
  String? _webError;

  static const _presets = [
    _DevicePreset('Mobile', Icons.phone_android, 375, 1.0),
    _DevicePreset('Tablet', Icons.tablet_android, 768, 0.85),
    _DevicePreset('Desktop', Icons.desktop_windows, 1280, 0.65),
  ];
  int _selectedPreset = 0;

  @override
  void initState() {
    super.initState();
    _loadPorts();
  }

  Future<void> _loadPorts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get('/api/preview/ports');
      setState(() { _ports = res.data ?? []; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _updateViewport() {
    if (_webCtrl == null) return;
    final preset = _presets[_selectedPreset];
    final js = '''
      var meta = document.querySelector("meta[name=viewport]");
      if (!meta) {
        meta = document.createElement("meta");
        meta.name = "viewport";
        document.head.appendChild(meta);
      }
      if ("${preset.name}" === "Mobile") {
        meta.setAttribute("content", "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0");
      } else {
        meta.setAttribute("content", "width=${preset.width}");
      }
    ''';
    _webCtrl!.runJavaScript(js);
  }

  Future<void> _selectPort(int port) async {
    setState(() { _selectedPort = port; _webError = null; _webLoading = true; _currentUrl = ''; });
    final agentUrl = await SecureStorage.getAgentUrl() ?? '';
    final token = await SecureStorage.getAccessToken() ?? '';

    final proxyUrl = '$agentUrl/api/preview/proxy/$port/';
    setState(() => _currentUrl = proxyUrl);

    try {
      // Buscar conteúdo via HTTP (que já tem SSL bypass)
      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final client = http_io.IOClient(httpClient);
      final response = await client.get(
        Uri.parse(proxyUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final content = response.body;
        final contentType = response.headers['content-type'] ?? 'text/html';

        final ctrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0xFF121212))
          ..setNavigationDelegate(NavigationDelegate(
            onWebResourceError: (error) {
              debugPrint('WebView Error: ${error.description}');
            },
            onPageStarted: (url) {
              if (mounted) setState(() => _webLoading = true);
            },
            onPageFinished: (url) {
              if (mounted) setState(() => _webLoading = false);
              _updateViewport();
            },
          ));

        if (contentType.contains('html')) {
          // Converter URLs relativas para absolutas
          String html = content;
          final baseUrl = '$agentUrl/api/preview/proxy/$port/';
          html = html.replaceAll('src="', 'src="$baseUrl');
          html = html.replaceAll("src='", "src='$baseUrl");
          html = html.replaceAll('href="', 'href="$baseUrl');
          html = html.replaceAll("href='", "href='$baseUrl");

          await ctrl.loadHtmlString(html, baseUrl: baseUrl);
        } else {
          await ctrl.loadHtmlString(
            '<pre style="color:#ccc;background:#121212;padding:16px;font-family:monospace;font-size:12px;white-space:pre-wrap;">$content</pre>',
          );
        }

        setState(() => _webCtrl = ctrl);
      } else {
        setState(() {
          _webError = 'Erro HTTP ${response.statusCode}';
          _webLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _webError = 'Falha ao carregar preview: $e';
        _webLoading = false;
      });
    }
  }

  void _openInBrowser() {
    if (_currentUrl.isNotEmpty) {
      launchUrl(Uri.parse(_currentUrl), mode: LaunchMode.externalApplication);
    }
  }

  void _showManualPortDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: RdcTheme.bg800,
        title: Text('Porta Manual', style: GoogleFonts.inter(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.firaCode(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ex: 3000',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar', style: TextStyle(color: RdcTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.primary),
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null) {
                if (!_ports.any((e) => e['port'] == p)) {
                  setState(() => _ports.add({'port': p, 'framework_hint': 'Manual'}));
                }
                _selectPort(p);
              }
              Navigator.pop(c);
            },
            child: const Text('Conectar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      // Toolbar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: RdcTheme.bg800,
        child: Column(children: [
          // URL bar
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: RdcTheme.bg600, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _currentUrl.isNotEmpty ? _currentUrl : 'Nenhum preview selecionado',
                  style: GoogleFonts.firaCode(fontSize: 11, color: _currentUrl.isNotEmpty ? RdcTheme.info : RdcTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _selectedPort != null ? () => _selectPort(_selectedPort!) : null, color: RdcTheme.textSecondary),
            IconButton(icon: const Icon(Icons.open_in_browser, size: 18), onPressed: _openInBrowser, color: RdcTheme.textSecondary, tooltip: 'Abrir no navegador'),
            IconButton(icon: const Icon(Icons.search, size: 18), onPressed: _loadPorts, color: RdcTheme.textSecondary),
          ]),
          const SizedBox(height: 8),
          // Port selector + Device selector
          Row(children: [
            // Portas detectadas
            Expanded(
              child: _loading
                  ? const LinearProgressIndicator()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_ports.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0, top: 8),
                              child: Text('Nenhum servidor detectado', style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
                            ),
                          ..._ports.map((p) {
                            final port = p['port'] as int;
                            final hint = p['framework_hint'] as String? ?? '';
                            final selected = port == _selectedPort;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _selectPort(port),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: selected ? RdcTheme.primary.withOpacity(0.2) : RdcTheme.bg600,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: selected ? RdcTheme.primary : RdcTheme.bg500),
                                  ),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Text(':$port', style: GoogleFonts.firaCode(fontSize: 12, color: selected ? RdcTheme.primary : RdcTheme.textPrimary, fontWeight: FontWeight.w700)),
                                    if (hint.isNotEmpty) Text(hint.split('/').first.trim(), style: GoogleFonts.inter(fontSize: 9, color: RdcTheme.textMuted)),
                                  ]),
                                ),
                              ),
                            );
                          }).toList(),
                          // Add manual port button
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            color: RdcTheme.primary,
                            tooltip: 'Adicionar porta manualmente',
                            onPressed: _showManualPortDialog,
                          )
                        ],
                      ),
                    ),
            ),
            // Device presets
            Row(
              children: _presets.asMap().entries.map((e) => IconButton(
                icon: Icon(e.value.icon, size: 18),
                color: _selectedPreset == e.key ? RdcTheme.primary : RdcTheme.textMuted,
                tooltip: e.value.name,
                onPressed: () {
                  setState(() => _selectedPreset = e.key);
                  _updateViewport();
                },
              )).toList(),
            ),
          ]),
        ]),
      ),

      // WebView area
      Expanded(
        child: _webCtrl == null
            ? _NoServerView(
                ports: _ports,
                loading: _loading,
                onRefresh: _loadPorts,
                onAddPort: _showManualPortDialog,
                onSelectPort: _selectPort,
              )
            : Stack(children: [
                LayoutBuilder(builder: (ctx, constraints) {
                  final preset = _presets[_selectedPreset];
                  if (preset.name == 'Mobile') {
                    return WebViewWidget(controller: _webCtrl!);
                  }
                  
                  final scale = constraints.maxWidth / preset.width;
                  final actualScale = scale < 1.0 ? scale : 1.0;
                  final webViewHeight = constraints.maxHeight / actualScale;
                  
                  return Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    color: const Color(0xFF0A0A0A),
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: preset.width,
                        height: webViewHeight,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: RdcTheme.bg500, width: 1), 
                              right: BorderSide(color: RdcTheme.bg500, width: 1),
                            )
                          ),
                          child: WebViewWidget(controller: _webCtrl!),
                        ),
                      ),
                    ),
                  );
                }),
                if (_webLoading)
                  const Positioned(
                    top: 0, left: 0, right: 0,
                    child: LinearProgressIndicator(color: RdcTheme.primary, backgroundColor: Colors.transparent),
                  ),
                if (_webError != null)
                  Positioned(
                    bottom: 16, left: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RdcTheme.danger.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          const Icon(Icons.error_outline, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_webError!, style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 16),
                            onPressed: () => setState(() => _webError = null),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openInBrowser,
                            icon: const Icon(Icons.open_in_browser, size: 14),
                            label: const Text('Abrir no navegador do celular'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                            ),
                           ),
                        ),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

// ── View quando nenhum servidor está rodando ───────────────────────────────

class _NoServerView extends StatelessWidget {
  final List<dynamic> ports;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onAddPort;
  final void Function(int) onSelectPort;

  const _NoServerView({
    required this.ports,
    required this.loading,
    required this.onRefresh,
    required this.onAddPort,
    required this.onSelectPort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RdcTheme.bg900,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ícone principal
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RdcTheme.bg700,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.preview_outlined, size: 48, color: RdcTheme.textMuted.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Text('Preview',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
          const SizedBox(height: 8),

          if (loading)
            const CircularProgressIndicator(color: RdcTheme.primary)
          else if (ports.isEmpty) ...[
            // Nenhum servidor encontrado
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RdcTheme.bg700,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RdcTheme.bg500),
              ),
              child: Column(children: [
                Icon(Icons.wifi_off, size: 32, color: RdcTheme.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text('Nenhum servidor detectado',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: RdcTheme.textSecondary)),
                const SizedBox(height: 6),
                Text('Inicie um servidor de desenvolvimento\nno seu computador para visualizar aqui.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
              ]),
            ),
            const SizedBox(height: 16),
            // Comandos rápidos
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RdcTheme.bg800,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RdcTheme.bg500),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Comandos comuns:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: RdcTheme.textSecondary)),
                const SizedBox(height: 8),
                _CommandTile('npm run dev', 'React / Next.js / Vite'),
                _CommandTile('python -m http.server 8000', 'Python HTTP'),
                _CommandTile('flask run --port 5000', 'Flask'),
                _CommandTile('php artisan serve', 'Laravel'),
              ]),
            ),
          ] else ...[
            // Portas encontradas — selecione uma
            Text('${ports.length} servidor(es) encontrado(s)',
                style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textMuted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ports.map((p) {
                final port = p['port'] as int;
                final hint = p['framework_hint'] as String? ?? '';
                return GestureDetector(
                  onTap: () => onSelectPort(port),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: RdcTheme.bg700,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: RdcTheme.primary.withOpacity(0.3)),
                    ),
                    child: Column(children: [
                      Text(':$port', style: GoogleFonts.firaCode(fontSize: 16, fontWeight: FontWeight.w700, color: RdcTheme.primary)),
                      if (hint.isNotEmpty)
                        Text(hint.split('/').first.trim(), style: GoogleFonts.inter(fontSize: 10, color: RdcTheme.textMuted)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 20),
          // Botões de ação
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Buscar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RdcTheme.primary,
                side: const BorderSide(color: RdcTheme.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onAddPort,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Porta manual'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RdcTheme.textSecondary,
                side: const BorderSide(color: RdcTheme.bg500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          // Banner de Dica de SSL/HTTPS
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RdcTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RdcTheme.info.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: RdcTheme.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dica: Se a página ficar em branco ou der erro de conexão, abra uma vez no "Navegador" e aceite o certificado auto-assinado no seu celular, ou inicie o agente com o argumento "--http".',
                  style: GoogleFonts.inter(fontSize: 10, color: RdcTheme.textSecondary, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  final String command;
  final String label;
  const _CommandTile(this.command, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(Icons.terminal, size: 12, color: RdcTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(command, style: GoogleFonts.firaCode(fontSize: 11, color: RdcTheme.primary)),
        ),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: RdcTheme.textMuted)),
      ]),
    );
  }
}
