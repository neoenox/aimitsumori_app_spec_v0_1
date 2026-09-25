/// 見積比較、要望差異、改訂履歴を切り替えるプロジェクト比較シェル。
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../repositories/project_repository.dart';
import '../repositories/project_requirement_repository.dart';
import '../repositories/quote_revision_repository.dart';
import '../services/ad_service.dart';
import '../services/project_view_refresh_coordinator.dart';
import 'comparison_screen.dart';
import 'document_scanner_screen.dart';
import 'quote_revision_screen.dart';
import 'requirements_comparison_screen.dart';

class RequirementsComparisonShell extends StatefulWidget {
  const RequirementsComparisonShell({
    super.key,
    required this.project,
    this.projectRepository,
    this.requirementRepository,
    this.quoteRevisionRepository,
    this.adService,
  });

  final Project project;
  final ProjectRepository? projectRepository;
  final ProjectRequirementRepository? requirementRepository;
  final QuoteRevisionRepository? quoteRevisionRepository;
  final AdService? adService;

  @override
  State<RequirementsComparisonShell> createState() =>
      _RequirementsComparisonShellState();
}

class _RequirementsComparisonShellState
    extends State<RequirementsComparisonShell> {
  final ProjectViewRefreshCoordinator _refresh =
      ProjectViewRefreshCoordinator();
  late Project _project = widget.project;

  ProjectRepository get _projectRepository =>
      widget.projectRepository ?? ProjectRepository.instance;

  void _select(int index) {
    setState(() => _refresh.selectView(index));
  }

  Future<void> _openScanner() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentScannerScreen(
          project: _project,
          repository: _projectRepository,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final refreshed = await _projectRepository.getProject(_project.id);
    if (!mounted || refreshed == null) return;
    setState(() {
      _project = refreshed;
      _refresh.projectChangedFromScanner();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('撮影した見積を保存しました。')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _refresh.selectedIndex,
        children: [
          ComparisonScreen(
            key: ValueKey('comparison-${_refresh.comparisonRevision}'),
            project: _project,
            repository: _projectRepository,
            adService: widget.adService,
          ),
          RequirementsComparisonScreen(
            key: ValueKey('requirements-${_refresh.requirementsRevision}'),
            project: _project,
            projectRepository: _projectRepository,
            repository: widget.requirementRepository,
          ),
          QuoteRevisionScreen(
            key: ValueKey('quote-history-${_refresh.historyRevision}'),
            project: _project,
            projectRepository: _projectRepository,
            repository: widget.quoteRevisionRepository,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'guided-document-scanner',
        onPressed: _openScanner,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('見積を撮影'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _refresh.selectedIndex,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined),
            selectedIcon: Icon(Icons.compare_arrows),
            label: '見積比較',
          ),
          NavigationDestination(
            icon: Icon(Icons.rule_outlined),
            selectedIcon: Icon(Icons.rule),
            label: '要望差異',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '改訂履歴',
          ),
        ],
      ),
    );
  }
}
