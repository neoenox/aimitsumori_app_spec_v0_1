/// ファイルパス: lib/main.dart
/// エントリポイント、広告・課金初期化、アプリテーマ
/// 関連ファイル: lib/screens/onboarding_screen.dart, lib/services/ad_service.dart
library;

import 'utils/app_logger.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'repositories/project_repository.dart';
import 'repositories/project_requirement_repository.dart';
import 'repositories/quote_revision_repository.dart';
import 'screens/onboarding_screen.dart';
import 'services/ad_service.dart';
import 'services/app_preferences.dart';
import 'services/database_initializer.dart';
import 'services/startup_cleanup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const StartupCleanupService().run();
  await initializeDatabase();
  try {
    await AdService.instance.initialize();
  } catch (error) {
    AppLogger.debug('Ad service initialization failed: $error');
  }
  runApp(const AimitsumoriApp());
}

class AimitsumoriApp extends StatefulWidget {
  const AimitsumoriApp({
    super.key,
    this.repository,
    this.requirementRepository,
    this.quoteRevisionRepository,
    this.adService,
    this.preferences,
  });

  final ProjectRepository? repository;
  final ProjectRequirementRepository? requirementRepository;
  final QuoteRevisionRepository? quoteRevisionRepository;
  final AdService? adService;
  final AppPreferences? preferences;

  @override
  State<AimitsumoriApp> createState() => _AimitsumoriAppState();
}

class _AimitsumoriAppState extends State<AimitsumoriApp>
    with WidgetsBindingObserver {
  bool _darkModeEnabled = false;

  late final ProjectRepository _repository;
  late final ProjectRequirementRepository _requirementRepository;
  late final QuoteRevisionRepository _quoteRevisionRepository;
  late final AppPreferences _preferences;
  late final AdService _adService;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ProjectRepository.instance;
    _requirementRepository =
        widget.requirementRepository ?? ProjectRequirementRepository.instance;
    _quoteRevisionRepository =
        widget.quoteRevisionRepository ?? QuoteRevisionRepository.instance;
    _preferences = widget.preferences ?? AppPreferences.instance;
    _adService = widget.adService ?? AdService.instance;
    WidgetsBinding.instance.addObserver(this);
    _loadDarkMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 復帰（ネットワーク回復後の再開を含む）時に保留中の購入検証を再試行する。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    try {
      unawaited(_adService.retryPendingVerifications());
    } catch (error) {
      AppLogger.debug('Pending verification resume retry failed: $error');
    }
  }

  Future<void> _loadDarkMode() async {
    try {
      final enabled = await _preferences.isDarkModeEnabled();
      if (mounted) setState(() => _darkModeEnabled = enabled);
    } catch (error) {
      AppLogger.debug('Dark mode preference load failed: $error');
    }
  }

  Future<void> _setDarkMode(bool enabled) async {
    final previous = _darkModeEnabled;
    setState(() => _darkModeEnabled = enabled);
    try {
      await _preferences.setDarkModeEnabled(enabled);
    } catch (error) {
      AppLogger.debug('Dark mode preference save failed: $error');
      if (mounted) setState(() => _darkModeEnabled = previous);
    }
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorSchemeSeed: Colors.indigo,
    useMaterial3: true,
    brightness: brightness,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.square(48)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '相見積もり比較',
      // Japanese locale keeps CJK glyph fallback aligned with Japanese forms
      // instead of allowing the device default to select Chinese glyphs.
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _darkModeEnabled ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 2,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FirstRunGate(
        repository: _repository,
        requirementRepository: _requirementRepository,
        quoteRevisionRepository: _quoteRevisionRepository,
        adService: _adService,
        darkModeEnabled: _darkModeEnabled,
        onDarkModeChanged: _setDarkMode,
      ),
    );
  }
}
