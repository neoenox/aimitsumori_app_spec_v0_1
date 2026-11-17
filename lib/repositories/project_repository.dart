/// ファイルパス: lib/repositories/project_repository.dart
/// UI層からSQLite実装を隠す案件リポジトリ。
library;

import '../utils/app_logger.dart';

import '../models.dart';
import '../quote_revision_models.dart';
import '../services/database_service.dart';
import '../services/quote_revision_service.dart';
import '../services/scan_storage_service.dart';

class ProjectRepository {
  ProjectRepository({
    DatabaseService? databaseService,
    QuoteRevisionService? revisionService,
    ScanStorageService? scanStorageService,
  }) : _databaseService = databaseService ?? DatabaseService.instance,
       _revisionService =
           revisionService ??
           (databaseService == null ? QuoteRevisionService.instance : null),
       _scanStorageService =
           scanStorageService ??
           (databaseService == null ? const ScanStorageService() : null);

  static final ProjectRepository instance = ProjectRepository();

  final DatabaseService _databaseService;
  final QuoteRevisionService? _revisionService;
  final ScanStorageService? _scanStorageService;

  Future<List<Project>> getProjects() =>
      _run(operation: '案件の読み込み', action: _databaseService.getProjects);

  Future<Project?> getProject(String projectId) => _run(
    operation: '案件の読み込み',
    action: () => _databaseService.getProject(projectId),
  );

  Future<void> saveProject(Project project) => _run(
    operation: '案件の保存',
    action: () => _databaseService.saveProject(project),
  );

  Future<void> updateProject(Project project) => _run(
    operation: '案件の更新',
    action: () => _databaseService.updateProject(project),
  );

  Future<void> deleteProject(String projectId) => _run(
    operation: '案件の削除',
    action: () async {
      // Keep the database record until scan files are confirmed removed. If
      // cleanup fails, the project remains visible and the user can retry.
      final storage = _scanStorageService;
      if (storage != null) await storage.cleanupProject(projectId);
      await _databaseService.deleteProject(projectId);
    },
  );

  Future<void> deleteAllData() => _run(
    operation: '全データの削除',
    action: () async {
      // Cleanup is idempotent. Run it first so a filesystem failure cannot
      // clear the database while leaving sensitive scan files behind.
      final storage = _scanStorageService;
      if (storage != null) await storage.cleanupAll();
      await _databaseService.deleteAllData();
    },
  );

  Future<void> saveQuote(
    String projectId,
    ContractorQuote quote, {
    QuoteImportIntent revisionIntent = const QuoteImportIntent.newQuote(),
    String? sourceFileHash,
  }) => _run(
    operation: '見積の保存',
    action: () async {
      final revisionService = _revisionService;
      if (revisionService == null) {
        await _databaseService.saveQuote(projectId, quote);
        return;
      }

      final db = await _databaseService.database;
      await db.transaction((transaction) async {
        await _databaseService.saveQuoteInTransaction(
          transaction,
          projectId,
          quote,
        );
        await revisionService.recordQuoteInTransaction(
          transaction,
          projectId: projectId,
          quote: quote,
          intent: revisionIntent,
          sourceFileHash: sourceFileHash,
        );

        final parentQuote = revisionIntent.parentQuote;
        if (revisionIntent.isRevision &&
            parentQuote != null &&
            parentQuote.id != quote.id) {
          await transaction.delete(
            'contractor_quotes',
            where: 'id = ? AND project_id = ?',
            whereArgs: [parentQuote.id, projectId],
          );
        }
      });
    },
  );

  Future<void> saveComparisonResult(ComparisonReport report) => _run(
    operation: '比較結果の保存',
    action: () => _databaseService.saveComparisonResult(report),
  );

  Future<ComparisonReport?> loadComparisonResult(String projectId) => _run(
    operation: '比較結果の読み込み',
    action: () => _databaseService.loadComparisonResult(projectId),
  );

  Future<T> _run<T>({
    required String operation,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } on ProjectRepositoryException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.debug('$operation failed: $error\\n$stackTrace');
      throw ProjectRepositoryException(operation, error);
    }
  }
}

class ProjectRepositoryException implements Exception {
  const ProjectRepositoryException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() => '$operationに失敗しました。入力内容を確認して、もう一度お試しください。';
}
