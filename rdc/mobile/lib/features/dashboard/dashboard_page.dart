/// RDC — Dashboard: status da máquina + projetos recentes
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../core/api/api_client.dart';
import '../../core/api/ws_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/app_theme.dart';

// ── Modelo ────────────────────────────────────────────────────────────────────

class SystemInfo {
  final String hostname;
  final String os;
  final double cpuPercent;
  final int cpuCores;
  final double ramPercent;
  final double ramUsedGb;
  final double ramTotalGb;
  final double? temperatureCelsius;
  final String uptimeHuman;
  final List<dynamic> disks;

  const SystemInfo({
    required this.hostname,
    required this.os,
    required this.cpuPercent,
    required this.cpuCores,
    required this.ramPercent,
    required this.ramUsedGb,
    required this.ramTotalGb,
    this.temperatureCelsius,
    required this.uptimeHuman,
    required this.disks,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> j) => SystemInfo(
        hostname: j['hostname'] ?? '',
        os: j['os'] ?? '',
        cpuPercent: (j['cpu_percent'] ?? 0).toDouble(),
        cpuCores: j['cpu_cores'] ?? 0,
        ramPercent: (j['ram_percent'] ?? 0).toDouble(),
        ramUsedGb: (j['ram_used_gb'] ?? 0).toDouble(),
        ramTotalGb: (j['ram_total_gb'] ?? 0).toDouble(),
        temperatureCelsius: j['temperature_celsius']?.toDouble(),
        uptimeHuman: j['uptime_human'] ?? '',
        disks: j['disks'] ?? [],
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final systemInfoProvider = StreamProvider<SystemInfo>((ref) async* {
  final agentUrl = await SecureStorage.getAgentUrl() ?? '';
  final token = await SecureStorage.getAccessToken() ?? '';

  final ctrl = StreamController<SystemInfo>();
  final ws = WsClient(
    path: '/ws/system',
    queryParams: {'interval': '3'},
    onMessage: (msg) {
      try {
        final data = jsonDecode(msg) as Map<String, dynamic>;
        ctrl.add(SystemInfo.fromJson(data));
      } catch (_) {}
    },
    onError: (e) => ctrl.addError(e),
    onDone: () => ctrl.close(),
  );

  await ws.connect();
  ref.onDispose(() {
    ws.disconnect();
    ctrl.close();
  });

  yield* ctrl.stream;
});

// ── Tela ──────────────────────────────────────────────────────────────────────

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sysAsync = ref.watch(systemInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Projetos',
            onPressed: () => context.go('/projects'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Desconectar',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: RdcTheme.bg700,
                  title: const Text('Desconectar', style: TextStyle(color: RdcTheme.textPrimary)),
                  content: const Text('Deseja realmente desconectar do agente?', style: TextStyle(color: RdcTheme.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.danger),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Desconectar', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/settings');
              }
            },
          ),
        ],
      ),
      body: sysAsync.when(
        data: (info) => _DashboardContent(info: info),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: RdcTheme.textMuted),
              const SizedBox(height: 16),
              Text('Sem conexão com o agente', style: GoogleFonts.inter(color: RdcTheme.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(systemInfoProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar Reconectar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RdcTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/settings');
                }, 
                child: const Text('Mudar URL / Agente'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/projects'),
        icon: const Icon(Icons.rocket_launch),
        label: const Text('Abrir Projeto'),
        backgroundColor: RdcTheme.primary,
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final SystemInfo info;
  const _DashboardContent({required this.info});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header da máquina
        _MachineHeader(info: info),
        const SizedBox(height: 16),

        // Métricas CPU + RAM
        Row(children: [
          Expanded(child: _MetricGauge(
            label: 'CPU',
            value: info.cpuPercent / 100,
            displayText: '${info.cpuPercent.toStringAsFixed(0)}%',
            color: _gaugeColor(info.cpuPercent),
            subtitle: '${info.cpuCores} núcleos',
          )),
          const SizedBox(width: 12),
          Expanded(child: _MetricGauge(
            label: 'RAM',
            value: info.ramPercent / 100,
            displayText: '${info.ramPercent.toStringAsFixed(0)}%',
            color: _gaugeColor(info.ramPercent),
            subtitle: '${info.ramUsedGb.toStringAsFixed(1)} / ${info.ramTotalGb.toStringAsFixed(1)} GB',
          )),
          if (info.temperatureCelsius != null) ...[
            const SizedBox(width: 12),
            Expanded(child: _MetricGauge(
              label: 'Temp',
              value: info.temperatureCelsius! / 100,
              displayText: '${info.temperatureCelsius!.toStringAsFixed(0)}°C',
              color: _gaugeColor(info.temperatureCelsius!),
              subtitle: 'CPU',
            )),
          ],
        ]),

        const SizedBox(height: 16),

        // Discos
        _SectionTitle('Armazenamento'),
        const SizedBox(height: 8),
        ...info.disks.map((d) => _DiskBar(disk: d)),

        const SizedBox(height: 16),

        // Info da máquina
        _InfoCard(items: [
          ('Sistema', info.os),
          ('Hostname', info.hostname),
          ('Uptime', info.uptimeHuman),
        ]),
      ],
    );
  }

  Color _gaugeColor(double value) {
    if (value > 85) return RdcTheme.danger;
    if (value > 60) return RdcTheme.warning;
    return RdcTheme.success;
  }
}

class _MachineHeader extends StatelessWidget {
  final SystemInfo info;
  const _MachineHeader({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: RdcTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.computer, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.hostname, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(info.os, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: RdcTheme.success, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _MetricGauge extends StatelessWidget {
  final String label;
  final double value;
  final String displayText;
  final Color color;
  final String subtitle;

  const _MetricGauge({
    required this.label,
    required this.value,
    required this.displayText,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RdcTheme.bg700,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RdcTheme.bg500),
      ),
      child: Column(
        children: [
          CircularPercentIndicator(
            radius: 40,
            lineWidth: 6,
            percent: value.clamp(0, 1),
            center: Text(displayText, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
            progressColor: color,
            backgroundColor: RdcTheme.bg500,
            circularStrokeCap: CircularStrokeCap.round,
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: RdcTheme.textPrimary)),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _DiskBar extends StatelessWidget {
  final dynamic disk;
  const _DiskBar({required this.disk});

  @override
  Widget build(BuildContext context) {
    final pct = (disk['percent'] as num).toDouble();
    final used = (disk['used_gb'] as num).toDouble();
    final total = (disk['total_gb'] as num).toDouble();
    final mount = disk['mountpoint'] as String;
    final color = pct > 85 ? RdcTheme.danger : pct > 60 ? RdcTheme.warning : RdcTheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.storage, size: 14, color: RdcTheme.textMuted),
            const SizedBox(width: 6),
            Text(mount, style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textSecondary)),
            const Spacer(),
            Text('${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB',
                style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: RdcTheme.bg500,
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary));
  }
}

class _InfoCard extends StatelessWidget {
  final List<(String, String)> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RdcTheme.bg700,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RdcTheme.bg500),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final (k, v) = e.value;
          return Padding(
            padding: EdgeInsets.only(bottom: e.key < items.length - 1 ? 12 : 0),
            child: Row(
              children: [
                Text(k, style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textMuted)),
                const Spacer(),
                Text(v, style: GoogleFonts.inter(fontSize: 13, color: RdcTheme.textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
