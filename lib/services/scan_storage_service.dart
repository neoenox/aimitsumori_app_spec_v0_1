library;

import 'dart:io';

import '../utils/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ScanDocumentsDirectoryProvider = Future<Directory> Function();
typedef ScanFileDeleter = Future<void> Function(File file);
typedef ScanDirectoryDeleter = Future<void> Function(Directory directory);

class ScanStorageService {
  const ScanStorageService({
    this.documentsDirectoryProvider,
    this.fileDeleter,
    this.directoryDeleter,
  });

  final ScanDocumentsDirectoryProvider? documentsDirectoryProvider;
  final ScanFileDeleter? fileDeleter;
  final ScanDirectoryDeleter? directoryDeleter;

  Future<String> persistCapture({
    required String sourcePath,
    required String projectId,
    required String sessionId,
    required String pageId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('撮影元ファイルが見つかりません。');
    }
    final root = await _scanRoot();
    final directory = Directory(
      p.join(root.path, _safeSegment(projectId), _safeSegment(sessionId)),
    );
    await directory.create(recursive: true);

    final extension = p.extension(sourcePath).toLowerCase();
    final safeExtension = RegExp(r'^\\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.jpg';
    final target = File(
      p.join(directory.path, '${_safeSegment(pageId)}$safeExtension'),
    );
    _assertInsideRoot(root, target.path);
    await source.copy(target.path);
    return target.path;
  }

  Future<void> deletePath(String path) async {
    final root = await _scanRoot();
    _assertInsideRoot(root, path);
    final file = File(path);
    if (!await file.exists()) return;

    try {
      await (fileDeleter ?? (target) => target.delete())(file);
    } on FileSystemException catch (error, stackTrace) {
      AppLogger.debug('Scan file cleanup failed: $error\\n$stackTrace');
      rethrow;
    }

    if (await file.exists()) {
      throw FileSystemException('Scan file remains after cleanup', path);
    }
  }

  Future<void> cleanupSession({
    required String projectId,
    required String sessionId,
  }) async {
    final root = await _scanRoot();
    final directory = Directory(
      p.join(root.path, _safeSegment(projectId), _safeSegment(sessionId)),
    );
    _assertInsideRoot(root, directory.path);
    await _deleteDirectory(directory, operation: 'scan session cleanup');
  }

  Future<void> cleanupProject(String projectId) async {
    final root = await _scanRoot();
    final directory = Directory(p.join(root.path, _safeSegment(projectId)));
    _assertInsideRoot(root, directory.path);
    await _deleteDirectory(directory, operation: 'project scan cleanup');
  }

  Future<void> cleanupAll() async {
    final root = await _scanRoot();
    await _deleteDirectory(root, operation: 'all scan cleanup');
  }

  Future<void> _deleteDirectory(
    Directory directory, {
    required String operation,
  }) async {
    if (!await directory.exists()) return;

    try {
      await (directoryDeleter ??
          (target) => target.delete(recursive: true))(directory);
    } on FileSystemException catch (error, stackTrace) {
      AppLogger.debug('$operation failed: $error\\n$stackTrace');
      rethrow;
    }

    if (await directory.exists()) {
      throw FileSystemException(
        '$operation did not remove the directory',
        directory.path,
      );
    }
  }

  Future<Directory> _scanRoot() async {
    final documents = await (documentsDirectoryProvider ??
        getApplicationDocumentsDirectory)();
    return Directory(p.join(documents.path, 'scans'));
  }

  String _safeSegment(String value) {
    final trimmed = value.trim();
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw ArgumentError.value(value, 'path segment', '安全なIDではありません。');
    }
    return sanitized;
  }

  void _assertInsideRoot(Directory root, String candidatePath) {
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final normalizedCandidate = p.normalize(p.absolute(candidatePath));
    if (!p.isWithin(normalizedRoot, normalizedCandidate)) {
      throw StateError('スキャン保存領域外のパスは操作できません。');
    }
  }
}
