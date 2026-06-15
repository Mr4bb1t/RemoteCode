/// RDC — Tela de Browser de Modelos de IA
/// Destaque MiMo V2.5, barra de provedores, categorias e busca
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';
import 'ai_model_picker.dart';

// ── Categorias ──────────────────────────────────────────────────────────────

enum ModelCategory { all, saved, mimo, popular, local, api }

const Map<ModelCategory, String> _categoryLabels = {
  ModelCategory.all: 'Todos',
  ModelCategory.saved: 'Salvos',
  ModelCategory.mimo: 'MiMo',
  ModelCategory.popular: 'Popular',
  ModelCategory.local: 'Local',
  ModelCategory.api: 'API',
};

const Map<ModelCategory, IconData> _categoryIcons = {
  ModelCategory.all: Icons.grid_view,
  ModelCategory.saved: Icons.bookmark,
  ModelCategory.mimo: Icons.bolt,
  ModelCategory.popular: Icons.star_outline,
  ModelCategory.local: Icons.computer,
  ModelCategory.api: Icons.cloud_outlined,
};

// ── Provedores em destaque para a nav bar ───────────────────────────────────

const List<Map<String, String>> _featuredProviders = [
  {'name': 'Xiaomi', 'emoji': '🔶', 'color': '#FF6900'},
  {'name': 'Anthropic', 'emoji': '🧠', 'color': '#D4A27F'},
  {'name': 'Google', 'emoji': '🔮', 'color': '#4285F4'},
  {'name': 'OpenAI', 'emoji': '🤖', 'color': '#10A37F'},
  {'name': 'xAI', 'emoji': '⚡', 'color': '#1DA1F2'},
  {'name': 'DeepSeek', 'emoji': '🐋', 'color': '#4F6EF7'},
  {'name': 'Meta', 'emoji': '🦙', 'color': '#0668E1'},
  {'name': 'Mistral', 'emoji': '🌀', 'color': '#FF7000'},
  {'name': 'Qwen', 'emoji': '🔮', 'color': '#6C5CE7'},
];

// ── Página principal ────────────────────────────────────────────────────────

class ModelBrowserPage extends StatefulWidget {
  const ModelBrowserPage({super.key});

  @override
  State<ModelBrowserPage> createState() => _ModelBrowserPageState();
}

class _ModelBrowserPageState extends State<ModelBrowserPage> {
  List<AiModelInfo> _allModels = [];
  List<AiModelInfo> _filtered = [];
  List<SavedModel> _savedModels = [];
  bool _loading = true;
  String _search = '';
  ModelCategory _category = ModelCategory.all;
  String? _selectedModelId;
  String? _navProvider;

  // IDs dos modelos que têm API key salva
  Set<String> _savedIds = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _loading = true);
    final models = await fetchModelsFromApi();
    final saved = await SecureStorage.getAiModel();
    final savedConfigs = await SecureStorage.getSavedModels();
    if (mounted) {
      setState(() {
        _allModels = models;
        _selectedModelId = saved;
        _savedModels = savedConfigs;
        _savedIds = savedConfigs.where((m) => m.apiKey.isNotEmpty).map((m) => m.id).toSet();
        _loading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    var list = List<AiModelInfo>.from(_allModels);

    if (_category == ModelCategory.saved) {
      list = list.where((m) => _savedIds.contains(m.id)).toList();
    } else if (_category != ModelCategory.all) {
      list = list.where((m) => m.category == _category.name).toList();
    }

    if (_navProvider != null) {
      list = list.where((m) => m.provider.toLowerCase().contains(_navProvider!.toLowerCase())).toList();
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) =>
        m.name.toLowerCase().contains(q) ||
        m.provider.toLowerCase().contains(q) ||
        m.id.toLowerCase().contains(q)
      ).toList();
    }

    list.sort((a, b) {
      // Salvos primeiro
      final aSaved = _savedIds.contains(a.id) ? 0 : 1;
      final bSaved = _savedIds.contains(b.id) ? 0 : 1;
      if (aSaved != bSaved) return aSaved - bSaved;
      if (a.category == 'mimo' && b.category != 'mimo') return -1;
      if (b.category == 'mimo' && a.category != 'mimo') return 1;
      if (a.category == 'popular' && b.category != 'popular') return -1;
      if (b.category == 'popular' && a.category != 'popular') return 1;
      final cmp = a.provider.compareTo(b.provider);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });

    setState(() => _filtered = list);
  }

  void _selectModel(AiModelInfo model) async {
    final hasSavedKey = _savedIds.contains(model.id);

    if (hasSavedKey) {
      // Já tem key salva — seleciona direto
      final saved = await SecureStorage.getSavedModel(model.id);
      await SecureStorage.setAiModel(model.id);
      if (saved != null && saved.apiKey.isNotEmpty) {
        await SecureStorage.setAiApiKey(saved.apiKey);
      }
      if (mounted) {
        setState(() => _selectedModelId = model.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${model.name} selecionado!'),
          backgroundColor: RdcTheme.success,
          duration: const Duration(seconds: 1),
        ));
      }
      return;
    }

    final needsKey = model.category != 'mimo' && model.category != 'local';

    if (needsKey) {
      final key = await _showApiKeyDialog(model);
      if (key == null) return;
      await SecureStorage.setAiModel(model.id);
      await SecureStorage.setAiApiKey(key);
      // Salvar permanentemente
      await SecureStorage.saveModelConfig(SavedModel(
        id: model.id, name: model.name, provider: model.provider,
        logoAsset: model.logoAsset,
        colorHex: '#${model.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        keyUrl: model.keyUrl, keyHint: model.keyHint,
        category: model.category, apiKey: key,
      ));
      if (mounted) {
        setState(() {
          _selectedModelId = model.id;
          _savedIds.add(model.id);
        });
        _applyFilter();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${model.name} configurado e salvo!'),
          backgroundColor: RdcTheme.success,
          duration: const Duration(seconds: 2),
        ));
      }
    } else {
      await SecureStorage.setAiModel(model.id);
      if (mounted) {
        setState(() => _selectedModelId = model.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${model.name} selecionado — modelo gratuito!'),
          backgroundColor: RdcTheme.success,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  void _removeSaved(String modelId) async {
    await SecureStorage.removeSavedModel(modelId);
    final saved = await SecureStorage.getSavedModels();
    if (mounted) {
      setState(() {
        _savedModels = saved;
        _savedIds = saved.where((m) => m.apiKey.isNotEmpty).map((m) => m.id).toSet();
      });
      _applyFilter();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Modelo removido dos salvos'),
        backgroundColor: RdcTheme.danger,
        duration: Duration(seconds: 1),
      ));
    }
  }

  Future<String?> _showApiKeyDialog(AiModelInfo model) async {
    final ctrl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RdcTheme.bg800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: model.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(model.logoAsset, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(model.name,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
                Text(model.provider,
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
              ]),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Insira a API Key para usar este modelo:',
                style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autofocus: true,
              style: GoogleFonts.firaCode(fontSize: 13, color: RdcTheme.textPrimary),
              decoration: InputDecoration(
                hintText: model.keyHint,
                hintStyle: const TextStyle(color: RdcTheme.textMuted),
                prefixIcon: const Icon(Icons.key, color: RdcTheme.textMuted, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                      color: RdcTheme.textMuted, size: 18),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
                filled: true,
                fillColor: RdcTheme.bg700,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (model.keyUrl.isNotEmpty)
              GestureDetector(
                onTap: () {},
                child: Text('Obter chave em: ${model.keyUrl}',
                    style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.primary)),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.inter(color: RdcTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final key = ctrl.text.trim();
                if (key.isEmpty) return;
                Navigator.pop(ctx, key);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: model.color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Salvar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<AiModelInfo>> _groupByProvider(List<AiModelInfo> models) {
    final map = <String, List<AiModelInfo>>{};
    for (final m in models) {
      map.putIfAbsent(m.provider, () => []).add(m);
    }
    return map;
  }

  List<AiModelInfo> get _mimoModels => _allModels.where((m) => m.category == 'mimo').toList();

  AiModelInfo? get _mimoV25 {
    try {
      return _allModels.firstWhere((m) => m.id.contains('mimo-v2.5') && !m.id.contains('tts'));
    } catch (_) {
      return _mimoModels.isNotEmpty ? _mimoModels.first : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByProvider(_filtered);
    final providers = grouped.keys.toList()..sort();
    final featured = _mimoV25;
    final mimoCount = _allModels.where((m) => m.category == 'mimo').length;
    final popularCount = _allModels.where((m) => m.category == 'popular').length;
    final localCount = _allModels.where((m) => m.category == 'local').length;

    return Scaffold(
      backgroundColor: RdcTheme.bg900,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: RdcTheme.bg800,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: RdcTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Modelos de IA',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
          ),

          // Busca
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: RdcTheme.bg800,
              child: TextField(
                style: GoogleFonts.inter(fontSize: 14, color: RdcTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar modelo ou provedor...',
                  hintStyle: const TextStyle(color: RdcTheme.textMuted),
                  prefixIcon: const Icon(Icons.search, color: RdcTheme.textMuted, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: RdcTheme.textMuted, size: 18),
                          onPressed: () { setState(() => _search = ''); _applyFilter(); },
                        )
                      : null,
                  filled: true,
                  fillColor: RdcTheme.bg700,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (v) { _search = v; _applyFilter(); },
              ),
            ),
          ),

          // Categorias
          SliverToBoxAdapter(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: RdcTheme.bg800,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _categoryChip(ModelCategory.all, _allModels.length),
                  _categoryChip(ModelCategory.saved, _savedIds.length),
                  _categoryChip(ModelCategory.mimo, mimoCount),
                  _categoryChip(ModelCategory.popular, popularCount),
                  _categoryChip(ModelCategory.local, localCount),
                  _categoryChip(ModelCategory.api, _allModels.where((m) => m.category == 'api').length),
                ],
              ),
            ),
          ),

          // Barra de provedores
          SliverToBoxAdapter(
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: RdcTheme.bg900,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _providerNavChip(null, 'Todos', '📋', '#888888'),
                  ..._featuredProviders.map((p) =>
                    _providerNavChip(p['name']!, p['name']!, p['emoji']!, p['color']!)),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: Divider(height: 1, color: RdcTheme.bg600)),

          // Hero MiMo V2.5
          if (featured != null && _navProvider == null && _search.isEmpty && _category != ModelCategory.saved)
            SliverToBoxAdapter(child: _HeroMiMoCard(
              model: featured,
              isSelected: _selectedModelId == featured.id,
              isSaved: _savedIds.contains(featured.id),
              onTap: () => _selectModel(featured),
              allMimo: _mimoModels,
              onExplore: () {
                setState(() { _category = ModelCategory.mimo; _navProvider = null; });
                _applyFilter();
              },
            )),

          // Loading / Lista
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: RdcTheme.primary)),
            )
          else if (_filtered.isEmpty)
            SliverFillRemaining(child: _EmptySearch())
          else
            SliverToBoxAdapter(
              child: Column(
                children: providers.map((provider) => _ProviderSection(
                  provider: provider,
                  models: grouped[provider]!,
                  accentColor: grouped[provider]!.first.color,
                  selectedId: _selectedModelId,
                  savedIds: _savedIds,
                  onSelect: _selectModel,
                  onRemoveSaved: _removeSaved,
                )).toList(),
              ),
            ),

          // Contador
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: RdcTheme.bg800,
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: RdcTheme.textMuted),
                const SizedBox(width: 6),
                Text('${_filtered.length} modelos encontrados',
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
                const Spacer(),
                if (_selectedModelId != null)
                  Text('Selecionado: ${_allModels.where((m) => m.id == _selectedModelId).map((m) => m.name).firstOrNull ?? "—"}',
                      style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.primary)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(ModelCategory cat, int count) {
    final isSelected = _category == cat;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_categoryIcons[cat], size: 14,
              color: isSelected ? Colors.white : RdcTheme.textMuted),
          const SizedBox(width: 4),
          Text(_categoryLabels[cat]!,
              style: GoogleFonts.inter(fontSize: 12,
                  color: isSelected ? Colors.white : RdcTheme.textSecondary)),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white24 : RdcTheme.bg600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: GoogleFonts.inter(fontSize: 10,
                    color: isSelected ? Colors.white : RdcTheme.textMuted)),
          ),
        ]),
        selectedColor: cat == ModelCategory.saved ? const Color(0xFFFF6900) : RdcTheme.primary,
        backgroundColor: RdcTheme.bg700,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (_) {
          setState(() { _category = cat; _navProvider = null; });
          _applyFilter();
        },
      ),
    );
  }

  Widget _providerNavChip(String? value, String label, String emoji, String colorHex) {
    final isSelected = _navProvider == value;
    final color = Color(int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onTap: () {
          setState(() => _navProvider = value);
          _applyFilter();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : RdcTheme.bg800,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? color : RdcTheme.bg600, width: isSelected ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isSelected ? color : RdcTheme.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

// ── Hero card MiMo V2.5 ───────────────────────────────────────────────────

class _HeroMiMoCard extends StatelessWidget {
  final AiModelInfo model;
  final bool isSelected;
  final bool isSaved;
  final VoidCallback onTap;
  final List<AiModelInfo> allMimo;
  final VoidCallback onExplore;

  const _HeroMiMoCard({
    required this.model, required this.isSelected, required this.isSaved,
    required this.onTap, required this.allMimo, required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFF6900).withOpacity(0.15), const Color(0xFFFF6900).withOpacity(0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF6900).withOpacity(0.3)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6900).withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('🔶', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('MiMo V2.5',
                      style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: RdcTheme.textPrimary)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF4CAF50), borderRadius: BorderRadius.circular(8)),
                    child: Text('GRÁTIS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text('Modelo principal — sem necessidade de API Key',
                    style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _statChip(Icons.speed, 'Reasoning', const Color(0xFF4CAF50)),
            const SizedBox(width: 8),
            _statChip(Icons.build, 'Tools', const Color(0xFF4CAF50)),
            const SizedBox(width: 8),
            _statChip(Icons.token, '1M ctx', const Color(0xFF4CAF50)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExplore,
                icon: const Icon(Icons.explore, size: 16),
                label: const Text('Explorar MiMo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6900),
                  side: const BorderSide(color: Color(0xFFFF6900)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onTap,
                icon: Icon(isSelected ? Icons.check : Icons.add, size: 16),
                label: Text(isSelected ? 'Selecionado' : 'Usar Agora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6900),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: color)),
      ]),
    );
  }
}

// ── Seção de provedor ──────────────────────────────────────────────────────

class _ProviderSection extends StatefulWidget {
  final String provider;
  final List<AiModelInfo> models;
  final Color accentColor;
  final String? selectedId;
  final Set<String> savedIds;
  final void Function(AiModelInfo) onSelect;
  final void Function(String) onRemoveSaved;

  const _ProviderSection({
    required this.provider, required this.models, required this.accentColor,
    required this.selectedId, required this.savedIds,
    required this.onSelect, required this.onRemoveSaved,
  });

  @override
  State<_ProviderSection> createState() => _ProviderSectionState();
}

class _ProviderSectionState extends State<_ProviderSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: RdcTheme.bg800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RdcTheme.bg600),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Container(width: 6, height: 24,
                  decoration: BoxDecoration(color: widget.accentColor, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.provider,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: RdcTheme.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: RdcTheme.bg600, borderRadius: BorderRadius.circular(10)),
                child: Text('${widget.models.length}',
                    style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted)),
              ),
              const SizedBox(width: 6),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: RdcTheme.textMuted, size: 20),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: RdcTheme.bg600),
          ...widget.models.map((m) => _ModelTile(
            model: m,
            isSelected: m.id == widget.selectedId,
            isSaved: widget.savedIds.contains(m.id),
            onTap: () => widget.onSelect(m),
            onRemoveSaved: () => widget.onRemoveSaved(m.id),
          )),
        ],
      ]),
    );
  }
}

// ── Tile de modelo ─────────────────────────────────────────────────────────

class _ModelTile extends StatelessWidget {
  final AiModelInfo model;
  final bool isSelected;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onRemoveSaved;

  const _ModelTile({
    required this.model, required this.isSelected, required this.isSaved,
    required this.onTap, required this.onRemoveSaved,
  });

  @override
  Widget build(BuildContext context) {
    final badge = _categoryBadge(model.category);
    return InkWell(
      onTap: onTap,
      onLongPress: isSaved ? () => _showRemoveDialog(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? model.color.withOpacity(0.08) : Colors.transparent,
          border: Border(bottom: BorderSide(color: RdcTheme.bg600.withOpacity(0.5), width: 0.5)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: model.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(model.logoAsset, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(model.name, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                          color: isSelected ? model.color : RdcTheme.textPrimary)),
                ),
                if (isSelected) ...[const SizedBox(width: 6), Icon(Icons.check_circle, size: 14, color: model.color)],
                if (isSaved && !isSelected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.bookmark, size: 14, color: const Color(0xFFFF6900)),
                ],
              ]),
              const SizedBox(height: 2),
              Row(children: [
                if (badge != null) ...[badge, const SizedBox(width: 6)],
                if (model.toolCall) _Tag('tools', RdcTheme.success),
                if (model.reasoning) ...[const SizedBox(width: 4), _Tag('reasoning', RdcTheme.primary)],
                if (isSaved) ...[const SizedBox(width: 4), _Tag('key salva', const Color(0xFFFF6900))],
              ]),
            ]),
          ),
          Icon(Icons.chevron_right, color: RdcTheme.textMuted, size: 18),
        ]),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remover ${model.name}?',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
        content: Text('A API Key salva será removida. Deseja continuar?',
            style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: GoogleFonts.inter(color: RdcTheme.textMuted))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); onRemoveSaved(); },
            style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.danger, foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  Widget? _categoryBadge(String category) {
    switch (category) {
      case 'mimo':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xFFFF6900).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('MiMo', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFFF6900))),
        );
      case 'popular':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('★ Popular', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.amber)),
        );
      case 'local':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('Local', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.green)),
        );
      default:
        return null;
    }
  }
}

// ── Tags ───────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: GoogleFonts.inter(fontSize: 9, color: color.withOpacity(0.8))),
  );
}

// ── Estado vazio ───────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_off, size: 48, color: RdcTheme.textMuted.withOpacity(0.3)),
      const SizedBox(height: 12),
      Text('Nenhum modelo encontrado',
          style: GoogleFonts.inter(fontSize: 15, color: RdcTheme.textMuted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('Tente buscar por outro nome ou provedor',
          style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textMuted.withOpacity(0.6))),
    ]),
  );
}
