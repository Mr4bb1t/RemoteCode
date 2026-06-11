/// RDC — Lista de Projetos
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

class Project {
  final int id;
  final String name;
  final String path;
  final String? language;
  final bool isFavorite;
  final String? currentBranch;
  final String? lastModified;

  const Project({
    required this.id,
    required this.name,
    required this.path,
    this.language,
    required this.isFavorite,
    this.currentBranch,
    this.lastModified,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'],
        name: j['name'],
        path: j['path'],
        language: j['language'],
        isFavorite: j['is_favorite'] ?? false,
        currentBranch: j['current_branch'],
        lastModified: j['last_modified'],
      );
}

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final res = await ApiClient.instance.get('/api/projects');
  if (res.statusCode == 200) {
    return (res.data as List).map((j) => Project.fromJson(j)).toList();
  }
  throw Exception('Erro ao carregar projetos');
});

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _langCtrl = TextEditingController();

  Future<void> _addProject() async {
    final name = _nameCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    if (name.isEmpty || path.isEmpty) return;

    try {
      await ApiClient.instance.post('/api/projects', data: {
        'name': name,
        'path': path,
        'language': _langCtrl.text.trim().isEmpty ? null : _langCtrl.text.trim(),
      });
      ref.invalidate(projectsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleFavorite(int projectId) async {
    await ApiClient.instance.post('/api/projects/$projectId/favorite');
    ref.invalidate(projectsProvider);
  }

  Future<void> _deleteProject(int projectId) async {
    await ApiClient.instance.delete('/api/projects/$projectId');
    ref.invalidate(projectsProvider);
  }

  void _showAddDialog() {
    _nameCtrl.clear(); _pathCtrl.clear(); _langCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RdcTheme.bg700,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adicionar Projeto', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: RdcTheme.textPrimary)),
            const SizedBox(height: 20),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nome do Projeto'), style: const TextStyle(color: RdcTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(controller: _pathCtrl, decoration: const InputDecoration(labelText: 'Caminho (ex: C:\\meu\\projeto)'), style: const TextStyle(color: RdcTheme.textPrimary)),
            const SizedBox(height: 12),
            TextField(controller: _langCtrl, decoration: const InputDecoration(labelText: 'Linguagem (opcional)'), style: const TextStyle(color: RdcTheme.textPrimary)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addProject, child: const Text('Adicionar'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/dashboard')),
        title: const Text('Projetos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(projectsProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: RdcTheme.primary,
        child: const Icon(Icons.add),
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: RdcTheme.textMuted),
                  const SizedBox(height: 16),
                  Text('Nenhum projeto cadastrado', style: GoogleFonts.inter(color: RdcTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _showAddDialog, child: const Text('Adicionar projeto')),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            itemBuilder: (ctx, i) => _ProjectCard(
              project: projects[i],
              onTap: () => context.push('/workspace/${projects[i].id}?name=${Uri.encodeComponent(projects[i].name)}'),
              onFavorite: () => _toggleFavorite(projects[i].id),
              onDelete: () => _deleteProject(projects[i].id),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e', style: const TextStyle(color: RdcTheme.danger))),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onFavorite,
    required this.onDelete,
  });

  Color _langColor(String? lang) {
    return switch (lang?.toLowerCase()) {
      'python' => const Color(0xFF3B82F6),
      'javascript' || 'typescript' => const Color(0xFFF59E0B),
      'dart' || 'flutter' => const Color(0xFF06B6D4),
      'rust' => const Color(0xFFEF4444),
      _ => RdcTheme.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RdcTheme.bg700,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: project.isFavorite ? RdcTheme.primary.withOpacity(0.4) : RdcTheme.bg500),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(project.name, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: RdcTheme.textPrimary)),
                ),
                IconButton(
                  icon: Icon(project.isFavorite ? Icons.star : Icons.star_outline, color: project.isFavorite ? RdcTheme.warning : RdcTheme.textMuted, size: 20),
                  onPressed: onFavorite, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: RdcTheme.danger, size: 20),
                  onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 4),
              Text(project.path, style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Row(children: [
                if (project.language != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _langColor(project.language).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _langColor(project.language).withOpacity(0.3)),
                    ),
                    child: Text(project.language!, style: GoogleFonts.inter(fontSize: 11, color: _langColor(project.language), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                ],
                if (project.currentBranch != null) ...[
                  const Icon(Icons.call_split, size: 12, color: RdcTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(project.currentBranch!, style: GoogleFonts.inter(fontSize: 12, color: RdcTheme.textSecondary)),
                ],
                const Spacer(),
                const Icon(Icons.chevron_right, color: RdcTheme.textMuted, size: 20),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
