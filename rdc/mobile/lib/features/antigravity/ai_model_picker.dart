/// RDC — Seletor de Modelo de IA (reutilizável)
/// Usado na tela de Configurações e no painel Mimo Agent do workspace
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/io_client.dart' as http_io;
import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

// ── Modelos disponíveis (carregados dinamicamente da API) ────────────────────

class AiModelInfo {
  final String id;
  final String name;
  final String provider;
  final String logoAsset;
  final Color  color;
  final String keyUrl;
  final String keyHint;
  final String category;
  final bool toolCall;
  final bool reasoning;

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.logoAsset,
    required this.color,
    required this.keyUrl,
    required this.keyHint,
    this.category = 'api',
    this.toolCall = true,
    this.reasoning = false,
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      provider: json['provider'] ?? '',
      logoAsset: json['logoAsset'] ?? '🤖',
      color: _parseColor(json['color'] ?? '#10A37F'),
      keyUrl: json['keyUrl'] ?? '',
      keyHint: json['keyHint'] ?? 'API Key',
      category: json['category'] ?? 'api',
      toolCall: json['toolCall'] ?? true,
      reasoning: json['reasoning'] ?? false,
    );
  }

  static Color _parseColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// MiMo Auto gratuito — sempre aparece no topo, nunca pede API key
const _mimoAutoModel = AiModelInfo(
  id: 'mimo/mimo-auto',
  name: 'MiMo Auto',
  provider: 'MiMo',
  logoAsset: '✨',
  color: Color(0xFF8A2BE2),
  keyUrl: '',
  keyHint: '',  // vazio = gratuito
  category: 'mimo',
);

Future<List<AiModelInfo>> fetchModelsFromApi() async {
  List<AiModelInfo> apiModels = [];
  try {
    final agentUrl = await SecureStorage.getAgentUrl() ?? '';
    final token = await SecureStorage.getAccessToken() ?? '';
    final uri = Uri.parse('$agentUrl/api/mimo/models');

    final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    final client = http_io.IOClient(httpClient);
    final response = await client.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      apiModels = data.map((e) => AiModelInfo.fromJson(e)).toList();
    }
  } catch (_) {}

  // Fallback se API falhou
  if (apiModels.isEmpty) {
    apiModels = [
      AiModelInfo(id: 'google/gemini-2.5-flash', name: 'Gemini 2.5 Flash', provider: 'Google', logoAsset: '🔮', color: const Color(0xFF4285F4), keyUrl: 'https://aistudio.google.com/apikey', keyHint: 'AIzaSy...'),
      AiModelInfo(id: 'google/gemini-2.5-pro', name: 'Gemini 2.5 Pro', provider: 'Google', logoAsset: '🌟', color: const Color(0xFF34A853), keyUrl: 'https://aistudio.google.com/apikey', keyHint: 'AIzaSy...'),
      AiModelInfo(id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini', provider: 'OpenAI', logoAsset: '⚡', color: const Color(0xFF10A37F), keyUrl: 'https://platform.openai.com/api-keys', keyHint: 'sk-proj-...'),
    ];
  }

  // Remove qualquer mimo-auto que a API possa ter retornado (evita duplicata)
  final others = apiModels.where((m) => m.id != 'mimo/mimo-auto').toList();

  // mimo-auto SEMPRE primeiro
  return [_mimoAutoModel, ...others];
}

// ── Bottom Sheet de seleção ───────────────────────────────────────────────────

Future<void> showAiModelPicker(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AiModelPickerSheet(),
  );
}

class _AiModelPickerSheet extends StatefulWidget {
  const _AiModelPickerSheet();

  @override
  State<_AiModelPickerSheet> createState() => _AiModelPickerSheetState();
}

class _AiModelPickerSheetState extends State<_AiModelPickerSheet> {
  AiModelInfo? _selected;
  final _keyCtrl = TextEditingController();
  bool _saving  = false;
  bool _obscure = true;
  String? _error;
  List<AiModelInfo> _models = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final models = await fetchModelsFromApi();
    final savedModel = await SecureStorage.getAiModel();
    final savedKey   = await SecureStorage.getAiApiKey();

    AiModelInfo? found;
    if (savedModel != null) {
      found = models.where((m) => m.id == savedModel).firstOrNull;
    }
    // Se nenhum modelo salvo, pré-seleciona mimo-auto (gratuito)
    found ??= models.firstOrNull;

    setState(() {
      _models = models;
      _loading = false;
      _selected = found;
    });
    if (savedKey != null && !(_isFreeModelFor(found))) _keyCtrl.text = savedKey;
  }

  /// Verifica se um modelo específico é gratuito
  bool _isFreeModelFor(AiModelInfo? m) =>
      m != null && m.category == 'mimo' && m.keyHint.isEmpty;

  /// Modelo gratuito não precisa de API key
  bool get _isFreeModel =>
      _selected != null &&
      (_selected!.category == 'mimo' && _selected!.keyHint.isEmpty);

  Future<void> _save() async {
    if (_selected == null) {
      setState(() => _error = 'Selecione um modelo');
      return;
    }
    final key = _keyCtrl.text.trim();
    if (key.isEmpty && !_isFreeModel) {
      setState(() => _error = 'Informe a chave da API');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      // Persiste localmente
      await SecureStorage.setAiModel(_selected!.id);
      if (!_isFreeModel) await SecureStorage.setAiApiKey(key);

      // Envia ao agente (endpoint de configuração)
      await ApiClient.instance.post('/api/settings/ai', data: {
        'ai_model':   _selected!.id,
        'ai_api_key': _isFreeModel ? '' : key,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isFreeModel
              ? '✅ MiMo Auto (gratuito) configurado!'
              : '✅ Modelo de IA configurado!'),
          backgroundColor: RdcTheme.success,
        ));
      }
    } catch (e) {
      // Se o endpoint não existir ainda, salva só localmente
      await SecureStorage.setAiModel(_selected!.id);
      if (!_isFreeModel) await SecureStorage.setAiApiKey(key);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Configuração salva localmente.'),
          backgroundColor: RdcTheme.success,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: RdcTheme.bg800,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40, height: 4,
          decoration: BoxDecoration(color: RdcTheme.bg500, borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: RdcTheme.primaryGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Text('Modelo de IA', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
          ]),
        ),

        // Grid de modelos
        if (_loading)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator(color: RdcTheme.primary)),
          )
        else
          SizedBox(
            height: 200,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.55,
              ),
              itemCount: _models.length,
              itemBuilder: (_, i) {
                final m = _models[i];
                final isSelected = _selected?.id == m.id;
              return GestureDetector(
                onTap: () => setState(() => _selected = m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected ? m.color.withOpacity(0.2) : RdcTheme.bg700,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? m.color : RdcTheme.bg500,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(m.logoAsset, style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 6),
                    Text(m.name,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: isSelected ? m.color : RdcTheme.textPrimary,
                        )),
                    Text(m.provider,
                        style: GoogleFonts.inter(fontSize: 10, color: RdcTheme.textMuted)),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.check_circle, size: 14, color: m.color),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),

        // Campo de chave — oculto para modelos gratuitos
        if (_selected != null && !_isFreeModel) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('API Key — ${_selected!.provider}',
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textSecondary, fontWeight: FontWeight.w500)),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
                  child: Text('Obter chave →',
                      style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.primary)),
                ),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: _keyCtrl,
                obscureText: _obscure,
                style: GoogleFonts.firaCode(fontSize: 13, color: RdcTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: _selected!.keyHint,
                  hintStyle: const TextStyle(color: RdcTheme.textMuted),
                  prefixIcon: const Icon(Icons.key, color: RdcTheme.textMuted, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: RdcTheme.textMuted, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ]),
          ),
        ] else if (_selected != null && _isFreeModel) ...[
          // Badge gratuito
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF8A2BE2).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8A2BE2).withOpacity(0.4)),
              ),
              child: Row(children: [
                const Text('✨', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text('Modelo gratuito — sem API Key necessária',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF8A2BE2), fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ],

        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(_error!, style: const TextStyle(color: RdcTheme.danger, fontSize: 12)),
          ),

        // Botão salvar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar Configuração'),
            ),
          ),
        ),
      ]),
    );
  }
}
