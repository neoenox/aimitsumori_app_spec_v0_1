/// Coordinates which project views need a fresh widget instance after
/// navigation or project mutations.
///
/// This keeps the existing revision-key refresh behavior explicit and testable
/// without introducing another application state-management system.
class ProjectViewRefreshCoordinator {
  int selectedIndex = 0;
  int comparisonRevision = 0;
  int requirementsRevision = 0;
  int historyRevision = 0;

  void selectView(int index) {
    selectedIndex = index;
    if (index == 1) {
      requirementsRevision += 1;
    } else if (index == 2) {
      historyRevision += 1;
    }
  }

  void projectChangedFromScanner() {
    comparisonRevision += 1;
    historyRevision += 1;
    selectedIndex = 0;
  }
}
