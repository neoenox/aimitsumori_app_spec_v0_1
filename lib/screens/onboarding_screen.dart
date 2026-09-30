/// ファイルパス: lib/screens/onboarding_screen.dart
/// 初回起動時に3ステップの利用方法を案内し、サンプルデータを任意で登録する
library;

import '../utils/app_logger.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sample_data.dart';
import '../repositories/project_repository.dart';
import '../repositories/project_requirement_repository.dart';
import '../repositories/quote_revision_repository.dart';
import '../services/ad_service.dart';
import '../services/haptic_service.dart';
import 'home_screen.dart';

class FirstRunGate extends StatefulWidget {
  const FirstRunGate({
    super.key,
    this.repository,
    this.requirementRepository,
    this.quoteRevisionRepository,
    this.adService,
    this.darkModeEnabled = false,
    this.onDarkModeChanged,
  });

  final ProjectRepository? repository;
  final ProjectRequirementRepository? requirementRepository;
  final QuoteRevisionRepository? quoteRevisionRepository;
  final AdService? adService;
  final bool darkModeEnabled;
  final ValueChanged<bool>? onDarkModeChanged;

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  static const _completedKey = 'onboarding_completed';

  bool? _completed;
  bool _saving = false;
  String? _error;

  ProjectRepository get _repository =>
      widget.repository ?? ProjectRepository.instance;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final completed = preferences.getBool(_completedKey) ?? false;
      if (!mounted) return;
      setState(() => _completed = completed);
    } catch (error) {
      AppLogger.debug('Onboarding preference load failed: $error');
      if (!mounted) return;
      setState(() => _completed = true);
    }
  }

  Future<void> _complete({required bool loadSample}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (loadSample) {
        await _repository.saveProject(SampleData.project());
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_completedKey, true);
      if (!mounted) return;
      setState(() => _completed = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    if (completed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (completed) {
      return HomeScreen(
        repository: _repository,
        requirementRepository: widget.requirementRepository,
        quoteRevisionRepository: widget.quoteRevisionRepository,
        adService: widget.adService,
        darkModeEnabled: widget.darkModeEnabled,
        onDarkModeChanged: widget.onDarkModeChanged,
      );
    }
    return OnboardingScreen(
      loading: _saving,
      error: _error,
      onStart: () => _complete(loadSample: false),
      onTrySample: () => _complete(loadSample: true),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.loading,
    required this.onStart,
    required this.onTrySample,
    this.error,
  });

  final bool loading;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onTrySample;

  Future<void> _handleTap(VoidCallback callback) async {
    await HapticService.lightImpact();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Icon(
              Icons.compare_arrows_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              '外構工事の見積書の「違い」を見つける',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              '外構工事18カテゴリを対象に、総合点や順位ではなく、価格・工事範囲・不明点を並べて確認するアプリです。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const _OnboardingStep(
              number: '1',
              icon: Icons.document_scanner_outlined,
              title: '見積書を取り込む',
              description: '外構工事のPDFまたは写真を選ぶと、端末内OCRで文字を読み取ります。',
            ),
            const _OnboardingStep(
              number: '2',
              icon: Icons.edit_note_outlined,
              title: '抽出結果を確認する',
              description: '自動判定された業者名・金額・外構工事カテゴリを、必要な箇所だけ修正します。',
            ),
            const _OnboardingStep(
              number: '3',
              icon: Icons.table_chart_outlined,
              title: '条件差を比較する',
              description: '「見積内」「別途」「不明」を横並びで確認し、業者への質問を整理します。',
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: loading ? null : () => _handleTap(onTrySample),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: const Text('サンプルデータで試す'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: loading ? null : () => _handleTap(onStart),
              child: const Text('空の状態から始める'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(child: Text(number)),
            const SizedBox(width: 12),
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
