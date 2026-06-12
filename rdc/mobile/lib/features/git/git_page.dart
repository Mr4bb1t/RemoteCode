/// RDC — Git Interface
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

class GitPage extends StatefulWidget {
  final int projectId;
  const GitPage({super.key, required this.projectId});

  @override
  State<GitPage> createState() => _GitPageState();
}

class _GitPageState extends State<GitPage> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late TabController _tabs;
  Map<String, dynamic>? _status;
  List<dynamic> _commits = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await ApiClient.instance.get('/api/git/${widget.projectId}/status');
      final l = await ApiClient.instance.get('/api/git/${widget.projectId}/log?limit=30');
      setState(() {
        _status = s.data;
        _commits = l.data['commits'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _commit() async {
    final ctrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: const Text('Commit', style: TextStyle(color: RdcTheme.textPrimary)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: RdcTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Mensagem do commit'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Commit')),
        ],
      ),
    );
    if (msg == null || msg.isEmpty) return;
    final res = await ApiClient.instance.post('/api/git/${widget.projectId}/commit',
        data: {'project_id': widget.projectId, 'message': msg, 'stage_all': true});
    _showResult(res.data);
    _loadAll();
  }

  Future<void> _gitAction(String action) async {
    final res = await ApiClient.instance.post('/api/git/${widget.projectId}/$action',
        data: {'project_id': widget.projectId});
    _showResult(res.data);
    _loadAll();
  }

  void _showResult(Map<String, dynamic>? data) {
    if (data == null || !mounted) return;
    final ok = data['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(data['message'] ?? ''),
      backgroundColor: ok ? RdcTheme.success : RdcTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: RdcTheme.danger)));

    final branch = _status?['branch'] ?? 'main';
    final ahead = _status?['ahead'] ?? 0;
    final behind = _status?['behind'] ?? 0;
    final modified = (_status?['modified'] as List? ?? []);
    final staged = (_status?['staged'] as List? ?? []);
    final untracked = (_status?['untracked'] as List? ?? []);

    return Column(children: [
      // Branch header
      Container(
        padding: const EdgeInsets.all(16),
        color: RdcTheme.bg800,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: RdcTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: RdcTheme.primary.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.call_split, size: 14, color: RdcTheme.primary),
              const SizedBox(width: 6),
              Text(branch, style: GoogleFonts.firaCode(fontSize: 13, color: RdcTheme.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 12),
          if (ahead > 0) _Badge('↑$ahead', RdcTheme.success),
          if (behind > 0) _Badge('↓$behind', RdcTheme.warning),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _loadAll),
        ]),
      ),

      // Ações Git
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          _ActionChip(label: 'Commit', icon: Icons.check_circle_outline, color: RdcTheme.success, onTap: _commit),
          _ActionChip(label: 'Push', icon: Icons.upload_outlined, color: RdcTheme.primary, onTap: () => _gitAction('push')),
          _ActionChip(label: 'Pull', icon: Icons.download_outlined, color: RdcTheme.info, onTap: () => _gitAction('pull')),
          _ActionChip(label: 'Fetch', icon: Icons.sync, color: RdcTheme.textSecondary, onTap: () => _gitAction('fetch')),
        ]),
      ),

      // Tabs: Status | Log | Diff
      TabBar(
        controller: _tabs,
        labelColor: RdcTheme.primary,
        unselectedLabelColor: RdcTheme.textMuted,
        indicatorColor: RdcTheme.primary,
        tabs: const [Tab(text: 'Status'), Tab(text: 'Log'), Tab(text: 'Diff')],
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          // Status
          ListView(padding: const EdgeInsets.all(16), children: [
            if (staged.isNotEmpty) ...[
              _SectionLabel('Staged', RdcTheme.success),
              ...staged.map((f) => _FileStatusTile(file: f, color: RdcTheme.success)),
            ],
            if (modified.isNotEmpty) ...[
              _SectionLabel('Modificados', RdcTheme.warning),
              ...modified.map((f) => _FileStatusTile(file: f, color: RdcTheme.warning)),
            ],
            if (untracked.isNotEmpty) ...[
              _SectionLabel('Não rastreados', RdcTheme.textMuted),
              ...untracked.map((f) => _FileStatusTile(file: {'path': f, 'status': '?'}, color: RdcTheme.textMuted)),
            ],
            if (staged.isEmpty && modified.isEmpty && untracked.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Nada para commitar', style: GoogleFonts.inter(color: RdcTheme.textMuted)))),
          ]),

          // Log de commits
          ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _commits.length,
            itemBuilder: (ctx, i) {
              final c = _commits[i];
              return _CommitTile(commit: c);
            },
          ),

          // Diff
          FutureBuilder(
            future: ApiClient.instance.get('/api/git/${widget.projectId}/diff'),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final diff = snap.data!.data['diff'] as String? ?? '';
              if (diff.isEmpty) return Center(child: Text('Sem alterações', style: GoogleFonts.inter(color: RdcTheme.textMuted)));
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: _DiffView(diff: diff),
              );
            },
          ),
        ]),
      ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
  );
}

class _FileStatusTile extends StatelessWidget {
  final Map<String, dynamic> file;
  final Color color;
  const _FileStatusTile({required this.file, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Container(
        width: 18, height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(file['status'] ?? 'M', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(file['path'] ?? '', style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.textSecondary))),
    ]),
  );
}

class _CommitTile extends StatelessWidget {
  final Map<String, dynamic> commit;
  const _CommitTile({required this.commit});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: RdcTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(commit['short_sha'] ?? '', style: GoogleFonts.firaCode(fontSize: 9, color: RdcTheme.primary)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(commit['message'] ?? '', style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text('${commit['author']} • ${commit['date']?.substring(0, 10) ?? ''}',
            style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted)),
      ])),
    ]),
  );
}

class _DiffView extends StatelessWidget {
  final String diff;
  const _DiffView({required this.diff});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: diff.split('\n').map((line) {
        Color color = RdcTheme.textSecondary;
        Color bg = Colors.transparent;
        if (line.startsWith('+') && !line.startsWith('+++')) { color = RdcTheme.success; bg = RdcTheme.success.withOpacity(0.05); }
        else if (line.startsWith('-') && !line.startsWith('---')) { color = RdcTheme.danger; bg = RdcTheme.danger.withOpacity(0.05); }
        else if (line.startsWith('@@')) { color = RdcTheme.info; }
        else if (line.startsWith('diff') || line.startsWith('index')) { color = RdcTheme.textMuted; }
        return Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(line, style: GoogleFonts.firaCode(fontSize: 12, color: color, height: 1.4)),
        );
      }).toList(),
    );
  }
}
