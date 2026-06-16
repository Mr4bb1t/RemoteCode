/// RDC — Git interno para snapshots de chat
/// Salva estado dos arquivos antes de cada run para poder desfazer realmente
import '../api/api_client.dart';

class ChatSnapshot {
  final int runId;
  final int projectId;
  final String projectPath;
  final Map<String, String> fileContents; // mantido por compatibilidade
  final DateTime timestamp;

  ChatSnapshot({
    required this.runId,
    required this.projectId,
    required this.projectPath,
    required this.fileContents,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'projectId': projectId,
    'projectPath': projectPath,
    'fileContents': fileContents,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatSnapshot.fromJson(Map<String, dynamic> j) => ChatSnapshot(
    runId: j['runId'],
    projectId: j['projectId'],
    projectPath: j['projectPath'] ?? '',
    fileContents: Map<String, String>.from(j['fileContents'] ?? {}),
    timestamp: DateTime.parse(j['timestamp']),
  );
}

class ChatSnapshotService {
  static ChatSnapshotService? _instance;
  static ChatSnapshotService get instance => _instance ??= ChatSnapshotService._();
  ChatSnapshotService._();

  final Map<int, ChatSnapshot> _snapshots = {}; // em memória para rastreamento de UI

  Future<void> init() async {
    // A inicialização agora é feita em memória e delegada ao agente
  }

  /// Salva snapshot dos arquivos no agente antes de uma run
  Future<void> saveSnapshot(int runId, int projectId, List<String> filePaths, String projectPath) async {
    try {
      await ApiClient.instance.post('/api/mimo/snapshot/save', data: {
        'project_id': projectId,
        'run_id': runId,
        'files': filePaths,
      });
      _snapshots[runId] = ChatSnapshot(
        runId: runId,
        projectId: projectId,
        projectPath: projectPath,
        fileContents: {},
        timestamp: DateTime.now(),
      );
    } catch (_) {}
  }

  /// Renomeia runId de um snapshot existente no agente
  Future<void> updateRunId(int oldRunId, int newRunId) async {
    try {
      await ApiClient.instance.post('/api/mimo/snapshot/rename', data: {
        'old_run_id': oldRunId,
        'new_run_id': newRunId,
      });
      final snapshot = _snapshots.remove(oldRunId);
      if (snapshot != null) {
        _snapshots[newRunId] = ChatSnapshot(
          runId: newRunId,
          projectId: snapshot.projectId,
          projectPath: snapshot.projectPath,
          fileContents: {},
          timestamp: snapshot.timestamp,
        );
      }
    } catch (_) {}
  }

  /// Restaura arquivos de um snapshot (desfazer) no agente
  Future<bool> restoreSnapshot(int runId, {String? projectPath}) async {
    try {
      final res = await ApiClient.instance.post('/api/mimo/snapshot/restore/$runId');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Remove snapshot no agente
  Future<void> deleteSnapshot(int runId) async {
    try {
      await ApiClient.instance.delete('/api/mimo/snapshot/$runId');
      _snapshots.remove(runId);
    } catch (_) {}
  }

  /// Verifica se existe snapshot para um runId
  bool hasSnapshot(int runId) => _snapshots.containsKey(runId);

  /// Retorna o snapshot de um runId
  ChatSnapshot? getSnapshot(int runId) => _snapshots[runId];

  /// Retorna todos os snapshots de um projeto
  List<ChatSnapshot> getProjectSnapshots(int projectId) {
    return _snapshots.values.where((s) => s.projectId == projectId).toList()
      ..sort((a, b) => a.runId.compareTo(b.runId));
  }

  /// Limpa snapshots antigos (mais de N dias)
  Future<void> cleanupOldSnapshots({int maxAgeDays = 30}) async {
    // snapshots do agente são limpos de acordo com a aprovação/rejeição
  }
}
