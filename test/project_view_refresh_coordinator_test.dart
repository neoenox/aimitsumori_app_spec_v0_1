import 'package:aimitsumori_app/services/project_view_refresh_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectViewRefreshCoordinator', () {
    test('selecting requirements refreshes only the requirements view', () {
      final coordinator = ProjectViewRefreshCoordinator();

      coordinator.selectView(1);

      expect(coordinator.selectedIndex, 1);
      expect(coordinator.requirementsRevision, 1);
      expect(coordinator.historyRevision, 0);
      expect(coordinator.comparisonRevision, 0);
    });

    test('selecting history refreshes only the history view', () {
      final coordinator = ProjectViewRefreshCoordinator();

      coordinator.selectView(2);

      expect(coordinator.selectedIndex, 2);
      expect(coordinator.requirementsRevision, 0);
      expect(coordinator.historyRevision, 1);
      expect(coordinator.comparisonRevision, 0);
    });

    test('scanner save refreshes comparison and history and returns home', () {
      final coordinator = ProjectViewRefreshCoordinator()..selectView(2);
      final previousHistoryRevision = coordinator.historyRevision;

      coordinator.projectChangedFromScanner();

      expect(coordinator.selectedIndex, 0);
      expect(coordinator.comparisonRevision, 1);
      expect(coordinator.requirementsRevision, 0);
      expect(coordinator.historyRevision, previousHistoryRevision + 1);
    });
  });
}
