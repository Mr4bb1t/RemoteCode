/// RDC — Preview Web com WebView e multi-dispositivo
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  WebViewController? _webCtrl;
  String _currentUrl = '';

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

  Future<void> _selectPort(int port) async {
    setState(() => _selectedPort = port);
    final agentUrl = await SecureStorage.getAgentUrl() ?? '';
    final token = await SecureStorage.getAccessToken() ?? '';

    // URL do proxy do agente
    final proxyUrl = '$agentUrl/api/preview/proxy/$port';
    setState(() => _currentUrl = proxyUrl);

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) => debugPrint('WebView Error: ${error.description}'),
      ))
      ..loadRequest(Uri.parse(proxyUrl), headers: {'Authorization': 'Bearer $token'});

    setState(() => _webCtrl = ctrl);
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
            IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: () => _webCtrl?.reload(), color: RdcTheme.textSecondary),
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
                onPressed: () => setState(() => _selectedPreset = e.key),
              )).toList(),
            ),
          ]),
        ]),
      ),

      // WebView area
      Expanded(
        child: _webCtrl == null
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.preview_outlined, size: 64, color: RdcTheme.textMuted),
                  const SizedBox(height: 16),
                  Text('Selecione uma porta para visualizar', style: GoogleFonts.inter(color: RdcTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadPorts,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar servidores'),
                  ),
                ]),
              )
            : WebViewWidget(controller: _webCtrl!),
      ),
    ]);
  }
}
