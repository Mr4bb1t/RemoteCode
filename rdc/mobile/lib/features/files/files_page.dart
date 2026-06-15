/// RDC — Explorador de Arquivos (carregamento incremental)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

typedef OnOpenFile = void Function(String path, String name);

class _FileNode {
  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final String? extension;
  bool isExpanded;
  List<_FileNode>? children;

  _FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.extension,
    this.isExpanded = false,
    this.children,
  });

  factory _FileNode.fromJson(Map<String, dynamic> j) => _FileNode(
        name: j['name'],
        path: j['path'],
        isDir: j['is_dir'] ?? false,
        size: j['size'],
        extension: j['extension'],
      );
}

class FilesPage extends ConsumerStatefulWidget {
  final int projectId;
  final OnOpenFile onOpenFile;

  const FilesPage({super.key, required this.projectId, required this.onOpenFile});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<_FileNode> _rootNodes = [];
  bool _loading = true;
  String? _error;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _loadDir('');
  }

  Future<void> _loadDir(String relativePath) async {
    try {
      final res = await ApiClient.instance.get(
        '/api/files/${widget.projectId}/tree',
        queryParameters: {'path': relativePath},
      );
      if (res.statusCode == 200) {
        final nodes = (res.data as List).map((j) => _FileNode.fromJson(j)).toList();
        if (relativePath.isEmpty) {
          setState(() { _rootNodes = nodes; _loading = false; });
        } else {
          _updateChildren(relativePath, nodes);
        }
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _updateChildren(String path, List<_FileNode> children) {
    setState(() {
      _setChildren(_rootNodes, path, children);
    });
  }

  bool _setChildren(List<_FileNode> nodes, String path, List<_FileNode> children) {
    for (final n in nodes) {
      if (n.path == path) {
        n.children = children;
        n.isExpanded = true;
        return true;
      }
      if (n.children != null && _setChildren(n.children!, path, children)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _toggleDir(_FileNode node) async {
    if (!node.isDir) return;
    if (node.isExpanded) {
      setState(() => node.isExpanded = false);
    } else if (node.children != null) {
      setState(() => node.isExpanded = true);
    } else {
      await _loadDir(node.path);
    }
  }

  Future<void> _createItem({required String parentPath, required bool isDir}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: Text(isDir ? 'Nova Pasta' : 'Novo Arquivo', style: const TextStyle(color: RdcTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: RdcTheme.textPrimary),
          decoration: InputDecoration(hintText: isDir ? 'Nome da pasta' : 'arquivo.py'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Criar')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final path = parentPath.isEmpty ? result : '$parentPath/$result';
    await ApiClient.instance.post(
      '/api/files/${widget.projectId}/create',
      data: {'project_id': widget.projectId, 'relative_path': path, 'is_dir': isDir},
    );
    await _loadDir(parentPath);
  }

  Future<void> _deleteItem(_FileNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RdcTheme.bg700,
        title: const Text('Excluir', style: TextStyle(color: RdcTheme.textPrimary)),
        content: Text('Excluir "${node.name}"?', style: const TextStyle(color: RdcTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: RdcTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiClient.instance.delete(
      '/api/files/${widget.projectId}/delete',
      data: {'project_id': widget.projectId, 'relative_path': node.path},
    );
    setState(() { _loading = true; });
    await _loadDir('');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Erro: $_error', style: const TextStyle(color: RdcTheme.danger)));

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: RdcTheme.bg800,
          child: Row(
            children: [
              Text('Arquivos', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: RdcTheme.textSecondary)),
              const Spacer(),
              _ToolbarBtn(icon: Icons.create_new_folder_outlined, tooltip: 'Nova Pasta', onTap: () => _createItem(parentPath: '', isDir: true)),
              _ToolbarBtn(icon: Icons.note_add_outlined, tooltip: 'Novo Arquivo', onTap: () => _createItem(parentPath: '', isDir: false)),
              _ToolbarBtn(icon: Icons.refresh, tooltip: 'Atualizar', onTap: () { setState(() => _loading = true); _loadDir(''); }),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _rootNodes.length,
            itemBuilder: (ctx, i) => _FileTreeItem(
              node: _rootNodes[i],
              depth: 0,
              selectedPath: _selectedPath,
              onTap: (node) {
                if (node.isDir) {
                  _toggleDir(node);
                } else {
                  setState(() => _selectedPath = node.path);
                  widget.onOpenFile(node.path, node.name);
                }
              },
              onLongPress: (node) => _showContextMenu(node),
            ),
          ),
        ),
      ],
    );
  }

  void _showContextMenu(_FileNode node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: RdcTheme.bg700,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: RdcTheme.bg500, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: RdcTheme.danger),
              title: Text('Excluir "${node.name}"', style: const TextStyle(color: RdcTheme.danger)),
              onTap: () { Navigator.pop(ctx); _deleteItem(node); },
            ),
            if (node.isDir) ...[
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, color: RdcTheme.textSecondary),
                title: const Text('Nova Pasta aqui', style: TextStyle(color: RdcTheme.textPrimary)),
                onTap: () { Navigator.pop(ctx); _createItem(parentPath: node.path, isDir: true); },
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined, color: RdcTheme.textSecondary),
                title: const Text('Novo Arquivo aqui', style: TextStyle(color: RdcTheme.textPrimary)),
                onTap: () { Navigator.pop(ctx); _createItem(parentPath: node.path, isDir: false); },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FileTreeItem extends StatelessWidget {
  final _FileNode node;
  final int depth;
  final String? selectedPath;
  final void Function(_FileNode) onTap;
  final void Function(_FileNode) onLongPress;

  const _FileTreeItem({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.onTap,
    required this.onLongPress,
  });

  Color _extColor(String? ext) {
    return switch (ext) {
      '.py' => const Color(0xFF3B82F6),
      '.js' || '.jsx' => const Color(0xFFF59E0B),
      '.ts' || '.tsx' => const Color(0xFF06B6D4),
      '.dart' => const Color(0xFF00D4FF),
      '.json' => const Color(0xFF10B981),
      '.md' => const Color(0xFF8B5CF6),
      '.html' => const Color(0xFFEF4444),
      '.css' || '.scss' => const Color(0xFF6366F1),
      '.yaml' || '.yml' => const Color(0xFFF97316),
      _ => RdcTheme.textMuted,
    };
  }

  IconData _icon() {
    if (node.isDir) {
      return node.isExpanded ? Icons.folder_open : Icons.folder;
    }
    return switch (node.extension) {
      '.py' => Icons.code,
      '.js' || '.ts' || '.jsx' || '.tsx' => Icons.javascript,
      '.dart' => Icons.flutter_dash,
      '.json' => Icons.data_object,
      '.md' => Icons.description,
      '.html' => Icons.html,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedPath == node.path;
    final color = node.isDir ? RdcTheme.warning : _extColor(node.extension);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onTap(node),
          onLongPress: () => onLongPress(node),
          child: Container(
            color: isSelected ? RdcTheme.primary.withOpacity(0.1) : null,
            padding: EdgeInsets.only(left: 12.0 + depth * 16, right: 12, top: 6, bottom: 6),
            child: Row(
              children: [
                if (node.isDir)
                  Icon(node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: RdcTheme.textMuted),
                const SizedBox(width: 4),
                Icon(_icon(), size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isSelected ? RdcTheme.primary : RdcTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!node.isDir && node.size != null)
                  Text(_formatSize(node.size!), style: GoogleFonts.inter(fontSize: 10, color: RdcTheme.textMuted)),
              ],
            ),
          ),
        ),
        if (node.isDir && node.isExpanded && node.children != null)
          ...node.children!.map((child) => _FileTreeItem(
            node: child, depth: depth + 1,
            selectedPath: selectedPath,
            onTap: onTap, onLongPress: onLongPress,
          )),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: RdcTheme.textSecondary),
        ),
      ),
    );
  }
}
