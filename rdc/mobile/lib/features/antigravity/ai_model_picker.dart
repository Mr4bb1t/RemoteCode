/// RDC — Seletor de Modelo de IA (reutilizável)
/// Usado na tela de Configurações e no painel Antigravity do workspace
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

// ── Modelos disponíveis ───────────────────────────────────────────────────────

class AiModelInfo {
  final String id;          // litellm model id, ex: gemini/gemini-2.5-flash
  final String name;        // Nome amigável
  final String provider;    // Gemini, OpenAI, etc.
  final String logoAsset;   // emoji usado como ícone (sem asset externo)
  final Color  color;
  final String keyUrl;      // Link para pegar a chave
  final String keyHint;     // Placeholder do campo de chave

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.logoAsset,
    required this.color,
    required this.keyUrl,
    required this.keyHint,
  });
}

const List<AiModelInfo> kAiModels = [
  AiModelInfo(
    id: 'gemini/gemini-2.5-flash',
    name: 'Gemini 2.5 Flash',
    provider: 'Google',
    logoAsset: '✨',
    color: Color(0xFF4285F4),
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHint: 'AIzaSy...',
  ),
  AiModelInfo(
    id: 'gemini/gemini-2.5-pro',
    name: 'Gemini 2.5 Pro',
    provider: 'Google',
    logoAsset: '🔮',
    color: Color(0xFF34A853),
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHint: 'AIzaSy...',
  ),
  AiModelInfo(
    id: 'openai/gpt-4o',
    name: 'GPT-4o',
    provider: 'OpenAI',
    logoAsset: '🤖',
    color: Color(0xFF10A37F),
    keyUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-proj-...',
  ),
  AiModelInfo(
    id: 'openai/gpt-4o-mini',
    name: 'GPT-4o Mini',
    provider: 'OpenAI',
    logoAsset: '⚡',
    color: Color(0xFF10A37F),
    keyUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-proj-...',
  ),
  AiModelInfo(
    id: 'anthropic/claude-opus-4-5',
    name: 'Claude Opus',
    provider: 'Anthropic',
    logoAsset: '🧠',
    color: Color(0xFFD4A27F),
    keyUrl: 'https://console.anthropic.com/keys',
    keyHint: 'sk-ant-...',
  ),
  AiModelInfo(
    id: 'anthropic/claude-sonnet-4-5',
    name: 'Claude Sonnet',
    provider: 'Anthropic',
    logoAsset: '📝',
    color: Color(0xFFD4A27F),
    keyUrl: 'https://console.anthropic.com/keys',
    keyHint: 'sk-ant-...',
  ),
  AiModelInfo(
    id: 'deepseek/deepseek-chat',
    name: 'DeepSeek V3',
    provider: 'DeepSeek',
    logoAsset: '🐋',
    color: Color(0xFF4F6EF7),
    keyUrl: 'https://platform.deepseek.com/api_keys',
    keyHint: 'sk-...',
  ),
  AiModelInfo(
    id: 'deepseek/deepseek-reasoner',
    name: 'DeepSeek R1',
    provider: 'DeepSeek',
    logoAsset: '🧩',
    color: Color(0xFF4F6EF7),
    keyUrl: 'https://platform.deepseek.com/api_keys',
    keyHint: 'sk-...',
  ),
];

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final savedModel  = await SecureStorage.getAiModel();
    final savedKey    = await SecureStorage.getAiApiKey();
    if (savedModel != null) {
      final found = kAiModels.where((m) => m.id == savedModel).firstOrNull;
      setState(() { _selected = found; });
    }
    if (savedKey != null) _keyCtrl.text = savedKey;
  }

  Future<void> _save() async {
    if (_selected == null) {
      setState(() => _error = 'Selecione um modelo');
      return;
    }
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Informe a chave da API');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      // Persiste localmente
      await SecureStorage.setAiModel(_selected!.id);
      await SecureStorage.setAiApiKey(key);

      // Envia ao agente (endpoint de configuração)
      await ApiClient.instance.post('/api/settings/ai', data: {
        'ai_model':   _selected!.id,
        'ai_api_key': key,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Modelo de IA configurado!'),
          backgroundColor: RdcTheme.success,
        ));
      }
    } catch (e) {
      // Se o endpoint não existir ainda, salva só localmente
      await SecureStorage.setAiModel(_selected!.id);
      await SecureStorage.setAiApiKey(key);
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
            itemCount: kAiModels.length,
            itemBuilder: (_, i) {
              final m = kAiModels[i];
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

        // Campo de chave
        if (_selected != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('API Key — ${_selected!.provider}',
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textSecondary, fontWeight: FontWeight.w500)),
                const Spacer(),
                GestureDetector(
                  // Abre a URL para obter a chave (se tivesse url_launcher)
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
