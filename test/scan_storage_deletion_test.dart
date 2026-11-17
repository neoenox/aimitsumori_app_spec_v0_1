import 'dart:io';

import 'package:aimitsumori_app/repositories/project_repository.dart';
import 'package:aimitsumori_app/services/scan_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/test_helpers.dart';

void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('scan-cleanup-test-');
  });

  tearDown(() async {
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  ScanStorageService storage({
    ScanFileDeleter? fileDeleter,
    ScanDirectoryDeleter? directoryDeleter,
  }) => ScanStorageService(
    documentsDirectoryProvider: () async => documents,
    fileDeleter: fileDeleter,
    directoryDeleter: directoryDeleter,
  );

  test(
    'deletePath reports failure and leaves the file available for retry',
    () async {
      final root = Directory(p.join(documents.path, 'scans'));
      final file = File(
        p.join(root.path, 'project-1', 'session-1', 'scan.jpg'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('private scan');

      final failing = storage(
        fileDeleter: (target) async {
          throw FileSystemException('simulated delete failure', target.path);
        },
      );

      await expectLater(
        failing.deletePath(file.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.exists(), isTrue);

      await storage().deletePath(file.path);
      expect(await file.exists(), isFalse);
    },
  );

  test('cleanupProject reports failure and can be retried', () async {
    final project = Directory(p.join(documents.path, 'scans', 'project-1'));
    await Directory(p.join(project.path, 'session-1')).create(
      recursive: true,
    );

    final failing = storage(
      directoryDeleter: (target) async {
        throw FileSystemException('simulated delete failure', target.path);
      },
    );

    await expectLater(
      failing.cleanupProject('project-1'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await project.exists(), isTrue);

    await storage().cleanupProject('project-1');
    expect(await project.exists(), isFalse);
  });

  test('cleanupAll reports failure and can be retried', () async {
    final root = Directory(p.join(documents.path, 'scans'));
    await Directory(p.join(root.path, 'project-1', 'session-1')).create(
      recursive: true,
    );

    final failing = storage(
      directoryDeleter: (target) async {
        throw FileSystemException('simulated delete failure', target.path);
      },
    );

    await expectLater(
      failing.cleanupAll(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await root.exists(), isTrue);

    await storage().cleanupAll();
    expect(await root.exists(), isFalse);
  });

  test(
    'deleteProject keeps its database row until scan cleanup succeeds',
    () async {
      final database = MockDatabaseService(
        initialProjects: [createTestProject(id: 'project-1')],
      );
      final project = Directory(p.join(documents.path, 'scans', 'project-1'));
      await Directory(p.join(project.path, 'session-1')).create(
        recursive: true,
      );

      final repository = ProjectRepository(
        databaseService: database,
        scanStorageService: storage(
          directoryDeleter: (target) async {
            throw FileSystemException('simulated delete failure', target.path);
          },
        ),
      );

      await expectLater(
        repository.deleteProject('project-1'),
        throwsA(isA<ProjectRepositoryException>()),
      );
      expect(
        (await database.getProjects()).map((item) => item.id),
        ['project-1'],
      );
      expect(await project.exists(), isTrue);

      final retryRepository = ProjectRepository(
        databaseService: database,
        scanStorageService: storage(),
      );
      await retryRepository.deleteProject('project-1');

      expect(await database.getProjects(), isEmpty);
      expect(await project.exists(), isFalse);
    },
  );

  test(
    'deleteAllData retains database records when scan cleanup fails',
    () async {
      final database = MockDatabaseService(
        initialProjects: [createTestProject(id: 'project-1')],
      );
      final root = Directory(p.join(documents.path, 'scans'));
      await Directory(p.join(root.path, 'project-1', 'session-1')).create(
        recursive: true,
      );

      final repository = ProjectRepository(
        databaseService: database,
        scanStorageService: storage(
          directoryDeleter: (target) async {
            throw FileSystemException('simulated delete failure', target.path);
          },
        ),
      );

      await expectLater(
        repository.deleteAllData(),
        throwsA(isA<ProjectRepositoryException>()),
      );
      expect(database.deleteAllDataCallCount, 0);
      expect(
        (await database.getProjects()).map((item) => item.id),
        ['project-1'],
      );
      expect(await root.exists(), isTrue);

      final retryRepository = ProjectRepository(
        databaseService: database,
        scanStorageService: storage(),
      );
      await retryRepository.deleteAllData();

      expect(database.deleteAllDataCallCount, 1);
      expect(await database.getProjects(), isEmpty);
      expect(await root.exists(), isFalse);
    },
  );
}
