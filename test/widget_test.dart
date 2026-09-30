import 'package:aimitsumori_app/main.dart';
import 'package:aimitsumori_app/repositories/project_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_helpers.dart';

void main() {
  testWidgets('App renders onboarding on first launch', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final database = MockDatabaseService();
    final repository = ProjectRepository(databaseService: database);
    final adService = MockAdMobService();

    await tester.pumpWidget(
      AimitsumoriApp(repository: repository, adService: adService),
    );
    await tester.pumpAndSettle();

    expect(find.text('外構工事の見積書を比較する'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('exterior-scope-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('このアプリは外構工事専用です'), findsOneWidget);
    expect(find.textContaining('引越し・車検'), findsOneWidget);
    expect(find.text('サンプルデータで試す'), findsOneWidget);
    expect(find.text('空の状態から始める'), findsOneWidget);
    expect(database.getProjectsCallCount, 0);
  });
}
