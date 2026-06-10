/// RDC — Execução e resultado de testes
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

class TestsPage extends StatefulWidget {
  final int projectId;
  const TestsPage({super.key, required this.projectId});

  @override
  State<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends State<TestsPage> {
  List<dynamic> _history = [];
  bool _running = false;
  String? _selectedRunner;
  String? _error;

  static const _runners = ['auto', 'pytest', 'unittest', 'jest', 'npm_test', 'cargo'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiClient.instance.get('/api/tests/${widget.projectId}/history');
      setState(() => _history = res.data ?? []);
    } catch (_) {}
  }

  Future<void> _runTests() async {
    setState(() { _running = true; _error = null; });
    try {
      final res = await ApiClient.instance.post(
        '/api/tests/${widget.projectId}/run',
        data: {
          'project_id': widget.projectId,
          'runner': _selectedRunner == 'auto' ? null : _selectedRunner,
        },
      );
      if (res.statusCode == 200) {
        setState(() { _history.insert(0, res.data); });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Runner selector + Run button
      Container(
        padding: const EdgeInsets.all(16),
        color: RdcTheme.bg800,
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedRunner ?? 'auto',
              decoration: const InputDecoration(labelText: 'Runner'),
              dropdownColor: RdcTheme.bg700,
              style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textPrimary),
              items: _runners.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedRunner = v),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _running ? null : _runTests,
            icon: _running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow),
            label: Text(_running ? 'Executando...' : 'Executar'),
          ),
        ]),
      ),
      if (_error != null)
        Container(
          padding: const EdgeInsets.all(12),
          color: RdcTheme.danger.withOpacity(0.1),
          child: Text(_error!, style: const TextStyle(color: RdcTheme.danger)),
        ),

      // Último resultado destaque
      if (_history.isNotEmpty) _TestResultCard(run: _history.first, isLatest: true),

      // Histórico
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _history.length,
          itemBuilder: (ctx, i) => i == 0 ? const SizedBox.shrink() : _TestHistoryTile(run: _history[i]),
        ),
      ),
    ]);
  }
}

class _TestResultCard extends StatelessWidget {
  final Map<String, dynamic> run;
  final bool isLatest;
  const _TestResultCard({required this.run, this.isLatest = false});

  @override
  Widget build(BuildContext context) {
    final status = run['status'] ?? 'unknown';
    final passed = run['passed'] ?? 0;
    final failed = run['failed'] ?? 0;
    final skipped = run['skipped'] ?? 0;
    final elapsed = run['execution_time_s'];
    final output = run['output'] ?? '';

    final statusColor = switch (status) {
      'passed' => RdcTheme.success,
      'failed' => RdcTheme.danger,
      'running' => RdcTheme.warning,
      _ => RdcTheme.textMuted,
    };

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RdcTheme.bg700,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_statusIcon(status), color: statusColor, size: 20),
          const SizedBox(width: 8),
          Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: statusColor)),
          const Spacer(),
          if (elapsed != null) Text('${elapsed.toStringAsFixed(1)}s', style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _StatBadge('$passed', 'Passou', RdcTheme.success),
          const SizedBox(width: 8),
          _StatBadge('$failed', 'Falhou', RdcTheme.danger),
          const SizedBox(width: 8),
          _StatBadge('$skipped', 'Pulou', RdcTheme.textMuted),
        ]),
        if (output.isNotEmpty && status == 'failed') ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Text('Output', style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: RdcTheme.bg900, borderRadius: BorderRadius.circular(8)),
            child: Text(
              output.length > 1000 ? output.substring(0, 1000) + '...' : output,
              style: GoogleFonts.firaCode(fontSize: 11, color: RdcTheme.textSecondary, height: 1.4),
            ),
          ),
        ],
      ]),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
    'passed' => Icons.check_circle,
    'failed' => Icons.cancel,
    'running' => Icons.hourglass_top,
    _ => Icons.help_outline,
  };
}

class _StatBadge extends StatelessWidget {
  final String count;
  final String label;
  final Color color;
  const _StatBadge(this.count, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(count, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: GoogleFonts.inter(fontSize: 10, color: color)),
    ]),
  );
}

class _TestHistoryTile extends StatelessWidget {
  final Map<String, dynamic> run;
  const _TestHistoryTile({required this.run});

  @override
  Widget build(BuildContext context) {
    final status = run['status'] ?? '';
    final color = status == 'passed' ? RdcTheme.success : status == 'failed' ? RdcTheme.danger : RdcTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(status == 'passed' ? Icons.check_circle : Icons.cancel, size: 16, color: color),
        const SizedBox(width: 8),
        Text(run['runner'] ?? '', style: GoogleFonts.firaCode(fontSize: 12, color: RdcTheme.textSecondary)),
        const Spacer(),
        Text('${run['passed'] ?? 0}✓ ${run['failed'] ?? 0}✗', style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
      ]),
    );
  }
}
