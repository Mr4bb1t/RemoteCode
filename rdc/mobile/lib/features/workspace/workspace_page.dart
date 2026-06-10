/// RDC — Workspace: container principal com abas do projeto
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../files/files_page.dart';
import '../editor/editor_page.dart';
import '../terminal/terminal_page.dart';
import '../git/git_page.dart';
import '../logs/logs_page.dart';
import '../tests/tests_page.dart';
import '../antigravity/antigravity_page.dart';
import '../preview/preview_page.dart';

class WorkspacePage extends ConsumerStatefulWidget {
  final int projectId;
  final String projectName;

  const WorkspacePage({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Arquivo aberto no editor (compartilhado entre Files e Editor)
  String? _openFilePath;
  String? _openFileName;

  static const List<_WorkspaceTab> _tabs = [
    _WorkspaceTab(icon: Icons.folder_outlined, label: 'Arquivos'),
    _WorkspaceTab(icon: Icons.code, label: 'Editor'),
    _WorkspaceTab(icon: Icons.terminal, label: 'Terminal'),
    _WorkspaceTab(icon: Icons.call_split, label: 'Git'),
    _WorkspaceTab(icon: Icons.receipt_long, label: 'Logs'),
    _WorkspaceTab(icon: Icons.science_outlined, label: 'Testes'),
    _WorkspaceTab(icon: Icons.auto_awesome, label: 'Antigravity'),
    _WorkspaceTab(icon: Icons.preview_outlined, label: 'Preview'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openFile(String path, String name) {
    setState(() {
      _openFilePath = path;
      _openFileName = name;
    });
    _tabController.animateTo(1); // Ir para aba Editor
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.projectName,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
            Text('Workspace', style: GoogleFonts.inter(fontSize: 11, color: RdcTheme.textMuted)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: RdcTheme.primary,
          indicatorWeight: 3,
          labelColor: RdcTheme.primary,
          unselectedLabelColor: RdcTheme.textMuted,
          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
          tabs: _tabs.map((t) => Tab(
            height: 44,
            child: Row(
              children: [
                Icon(t.icon, size: 16),
                const SizedBox(width: 6),
                Text(t.label),
              ],
            ),
          )).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), // evitar swipe acidental
        children: [
          FilesPage(projectId: widget.projectId, onOpenFile: _openFile),
          EditorPage(projectId: widget.projectId, filePath: _openFilePath, fileName: _openFileName),
          TerminalPage(projectId: widget.projectId),
          GitPage(projectId: widget.projectId),
          LogsPage(projectId: widget.projectId),
          TestsPage(projectId: widget.projectId),
          AntigravityPage(projectId: widget.projectId),
          PreviewPage(projectId: widget.projectId),
        ],
      ),
    );
  }
}

class _WorkspaceTab {
  final IconData icon;
  final String label;
  const _WorkspaceTab({required this.icon, required this.label});
}
