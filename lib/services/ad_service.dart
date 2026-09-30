/// ファイルパス: lib/services/ad_service.dart
/// AdMob広告と広告削除の非消費型課金を管理するサービス。
library;

import '../utils/app_logger.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_verification_queue.dart';
import 'purchase_verification_service.dart';

enum RewardedAdOutcome { rewarded, unavailable, dismissed }

abstract interface class AdConsentPlatform {
  Future<void> requestUpdate();
  Future<void> showRequiredForm();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
}

class GoogleUmpConsentPlatform implements AdConsentPlatform {
  const GoogleUmpConsentPlatform();

  @override
  Future<void> requestUpdate() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => completer.complete(),
      (error) => completer.completeError(error),
    );
    return completer.future;
  }

  @override
  Future<void> showRequiredForm() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }
}

class AdConsentManager {
  AdConsentManager({AdConsentPlatform? platform})
    : _platform = platform ?? const GoogleUmpConsentPlatform();

  final AdConsentPlatform _platform;
  bool canRequestAds = false;
  bool privacyOptionsRequired = false;

  Future<void> refresh() async {
    try {
      await _platform.requestUpdate();
      await _platform.showRequiredForm();
    } catch (_) {
      // A prior valid consent state may still allow ads.
    }
    await _sync();
  }

  Future<bool> reopenPrivacyOptions() async {
    try {
      await _platform.showPrivacyOptions();
    } catch (_) {
      await _sync();
      return false;
    }
    await _sync();
    return true;
  }

  Future<void> _sync() async {
    try {
      canRequestAds = await _platform.canRequestAds();
    } catch (_) {
      canRequestAds = false;
    }
    try {
      privacyOptionsRequired = await _platform.privacyOptionsRequired();
    } catch (_) {
      privacyOptionsRequired = false;
    }
  }
}

/// リワード広告のロード完了とタイムアウトの競合を調停する。
/// 一度確定したら二度と変わらず、確定後の遅延ロード広告は表示できない。
@visibleForTesting
class RewardedAdLoadGate {
  final Completer<RewardedAdOutcome> _completer =
      Completer<RewardedAdOutcome>();

  bool get canPresent => !_completer.isCompleted;

  Future<RewardedAdOutcome> get outcome => _completer.future;

  bool settle(RewardedAdOutcome value) {
    if (_completer.isCompleted) return false;
    _completer.complete(value);
    return true;
  }
}

class AdService {
  AdService._({
    PurchaseVerifier? verifier,
    PendingVerificationStore? verificationStore,
  }) : _verifier = verifier ?? const PurchaseVerificationService() {
    _verificationQueue = PurchaseVerificationQueue(
      verifier: _verifier,
      store: verificationStore,
    );
  }

  @visibleForTesting
  factory AdService.testing({
    bool adFree = true,
    PurchaseVerifier verifier = const TestingPurchaseVerifier(),
    PendingVerificationStore? verificationStore,
  }) {
    final service = AdService._(
      verifier: verifier,
      verificationStore: verificationStore,
    );
    service.adFree.value = adFree;
    service._initialized = true;
    return service;
  }

  static final AdService instance = AdService._();

  static const String removeAdsProductId = String.fromEnvironment(
    'REMOVE_ADS_PRODUCT_ID',
    defaultValue: 'remove_ads',
  );
  static const String _adFreePreferenceKey = 'ad_free_verified_cache_v2';
  static const String _adFreeVerifiedAtKey = 'ad_free_verified_at_v2';
  static const Duration _verificationGracePeriod = Duration(days: 7);

  static const String _configuredAndroidBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: '',
  );
  static const String _configuredIosBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: '',
  );
  static const String _configuredAndroidRewardedId = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_ID',
    defaultValue: '',
  );
  static const String _configuredIosRewardedId = String.fromEnvironment(
    'ADMOB_IOS_REWARDED_ID',
    defaultValue: '',
  );

  static const String _androidTestBannerId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosTestBannerId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _androidTestRewardedId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosTestRewardedId =
      'ca-app-pub-3940256099942544/1712485313';

  final ValueNotifier<bool> adFree = ValueNotifier<bool>(false);

  /// 検証待ち（リトライキュー内）の購入件数。
  final ValueNotifier<int> pendingVerificationCount = ValueNotifier<int>(0);

  /// 最大試行回数・24時間窓を超えて自動再試行できなくなった購入（要確認）が
  /// 1件でもあるかどうか。UIは非破壊の案内バナーを出す。
  final ValueNotifier<bool> purchaseNeedsConfirmation = ValueNotifier<bool>(
    false,
  );

  final PurchaseVerifier _verifier;
  late final PurchaseVerificationQueue _verificationQueue;

  // 遅延解決：テストなどプラットフォームチャネルが無い環境でも
  // インスタンス化できるようにする。
  InAppPurchase get _inAppPurchase => InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _removeAdsProduct;
  bool _initialized = false;

  bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  ProductDetails? get removeAdsProduct => _removeAdsProduct;

  String get bannerAdUnitId {
    final configured = defaultTargetPlatform == TargetPlatform.iOS
        ? _configuredIosBannerId
        : _configuredAndroidBannerId;
    final testId = defaultTargetPlatform == TargetPlatform.iOS
        ? _iosTestBannerId
        : _androidTestBannerId;
    return _adUnitId(configured: configured, testId: testId, kind: 'banner');
  }

  String get rewardedAdUnitId {
    final configured = defaultTargetPlatform == TargetPlatform.iOS
        ? _configuredIosRewardedId
        : _configuredAndroidRewardedId;
    final testId = defaultTargetPlatform == TargetPlatform.iOS
        ? _iosTestRewardedId
        : _androidTestRewardedId;
    return _adUnitId(configured: configured, testId: testId, kind: 'rewarded');
  }

  bool get _hasAdConfiguration {
    try {
      return bannerAdUnitId.isNotEmpty && rewardedAdUnitId.isNotEmpty;
    } on StateError {
      return false;
    }
  }

  String _adUnitId({
    required String configured,
    required String testId,
    required String kind,
  }) {
    if (configured.trim().isNotEmpty) return configured.trim();
    if (!kReleaseMode) return testId;
    throw StateError('$kind AdMob unit ID is not configured for release.');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadRecentVerifiedEntitlement();
    await _refreshPendingVerificationState();
    if (!isSupportedPlatform) return;

    _purchaseSubscription ??= _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.debug('Purchase stream error: $error\n$stackTrace');
      },
    );

    if (_hasAdConfiguration) {
      try {
        await MobileAds.instance.initialize();
      } catch (error) {
        AppLogger.debug('Mobile Ads initialization failed: $error');
      }
    }

    try {
      await _loadRemoveAdsProduct();
    } catch (error) {
      AppLogger.debug('Remove ads product load failed: $error');
    }

    await restorePurchases();
    await retryPendingVerifications();
  }

  Future<void> _loadRecentVerifiedEntitlement() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final cached = preferences.getBool(_adFreePreferenceKey) ?? false;
      final verifiedAtMillis = preferences.getInt(_adFreeVerifiedAtKey);
      if (!cached || verifiedAtMillis == null) return;

      final verifiedAt = DateTime.fromMillisecondsSinceEpoch(verifiedAtMillis);
      final age = DateTime.now().difference(verifiedAt);
      if (!age.isNegative && age <= _verificationGracePeriod) {
        adFree.value = true;
      }
    } catch (error) {
      AppLogger.debug('Ad entitlement cache load failed: $error');
    }
  }

  Future<void> _loadRemoveAdsProduct() async {
    if (!await _inAppPurchase.isAvailable()) return;
    final response = await _inAppPurchase.queryProductDetails({
      removeAdsProductId,
    });
    if (response.error != null) {
      AppLogger.debug('Product query failed: ${response.error}');
      return;
    }
    for (final product in response.productDetails) {
      if (product.id == removeAdsProductId) {
        _removeAdsProduct = product;
        return;
      }
    }
  }

  BannerAd? createBannerAd({
    VoidCallback? onLoaded,
    ValueChanged<LoadAdError>? onFailed,
  }) {
    if (!isSupportedPlatform || !_hasAdConfiguration || adFree.value) {
      return null;
    }

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailed?.call(error);
        },
      ),
    );
  }

  Future<RewardedAdOutcome> showRewardedAd() async {
    if (adFree.value) return RewardedAdOutcome.rewarded;
    if (!isSupportedPlatform || !_hasAdConfiguration) {
      return RewardedAdOutcome.unavailable;
    }

    final gate = RewardedAdLoadGate();
    Timer? timeout;
    try {
      timeout = Timer(const Duration(seconds: 20), () {
        gate.settle(RewardedAdOutcome.unavailable);
      });
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!gate.canPresent) {
              ad.dispose();
              return;
            }
            var earnedReward = false;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (dismissedAd) {
                dismissedAd.dispose();
                gate.settle(
                  earnedReward
                      ? RewardedAdOutcome.rewarded
                      : RewardedAdOutcome.dismissed,
                );
              },
              onAdFailedToShowFullScreenContent: (failedAd, error) {
                AppLogger.debug('Rewarded ad failed to show: $error');
                failedAd.dispose();
                gate.settle(RewardedAdOutcome.unavailable);
              },
            );
            ad.show(onUserEarnedReward: (_, _) => earnedReward = true);
          },
          onAdFailedToLoad: (error) {
            AppLogger.debug('Rewarded ad failed to load: $error');
            gate.settle(RewardedAdOutcome.unavailable);
          },
        ),
      );
    } catch (error) {
      AppLogger.debug('Rewarded ad request failed: $error');
      gate.settle(RewardedAdOutcome.unavailable);
    }
    try {
      return await gate.outcome;
    } finally {
      timeout?.cancel();
    }
  }

  Future<bool> purchaseRemoveAds() async {
    if (!isSupportedPlatform) return false;
    try {
      _removeAdsProduct ??= await _queryRemoveAdsProduct();
      final product = _removeAdsProduct;
      if (product == null || product.id != removeAdsProductId) return false;
      return _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (error) {
      AppLogger.debug('Remove ads purchase start failed: $error');
      return false;
    }
  }

  Future<ProductDetails?> _queryRemoveAdsProduct() async {
    if (!await _inAppPurchase.isAvailable()) return null;
    final response = await _inAppPurchase.queryProductDetails({
      removeAdsProductId,
    });
    if (response.error != null) return null;
    for (final product in response.productDetails) {
      if (product.id == removeAdsProductId) return product;
    }
    return null;
  }

  Future<void> restorePurchases() async {
    if (!isSupportedPlatform) return;
    try {
      await _inAppPurchase.restorePurchases();
    } catch (error) {
      AppLogger.debug('Purchase restore failed: $error');
    }
    // ユーザーが復元を明示的に行ったタイミングでも保留中の検証を再試行する。
    await retryPendingVerifications();
  }

  /// 検証待ち購入を再試行する。アプリ起動時・レジューム時・購入復元時に呼ぶ。
  /// 検証に成功したレコードは権利付与後に削除し、invalidなら権利を取り消す。
  /// 自動再試行が終了した（要確認）レコードは保持してUIへ状態を公開する。
  Future<void> retryPendingVerifications() async {
    try {
      final report = await _verificationQueue.processPending();
      if (report.verifiedRecordIds.isNotEmpty) {
        AppLogger.debug(
          'Pending purchase verification succeeded: '
          '${report.verifiedRecordIds.length} record(s).',
        );
        await _setAdFree(true);
      }
      if (report.rejectedRecordIds.isNotEmpty) {
        AppLogger.debug(
          'Pending purchase verification rejected: '
          '${report.rejectedRecordIds.length} record(s).',
        );
        await _setAdFree(false);
      }
      if (report.escalatedRecordIds.isNotEmpty) {
        AppLogger.debug(
          'Pending purchase verification needs confirmation: '
          '${report.escalatedRecordIds.length} record(s).',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.debug('Pending verification retry failed: $error\n$stackTrace');
    }
    await _refreshPendingVerificationState();
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != removeAdsProductId) continue;

      var completePurchase = true;
      try {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          final result = await _verifier.verify(purchase);
          switch (result) {
            case PurchaseVerificationResult.valid:
              await _setAdFree(true);
              break;
            case PurchaseVerificationResult.invalid:
              AppLogger.debug('Remove ads purchase verification rejected.');
              await _setAdFree(false);
              break;
            case PurchaseVerificationResult.retryable:
              completePurchase = false;
              AppLogger.debug(
                'Remove ads purchase verification is retryable; '
                'preserving the current entitlement.',
              );
              // ストア側の再配信に依存せず、アプリ起動・レジューム時にも
              // 再検証できるようリトライキューへ永続化する。
              await _enqueueRetryableVerification(purchase);
              break;
          }
        } else if (purchase.status == PurchaseStatus.error) {
          AppLogger.debug('Remove ads purchase failed: ${purchase.error}');
        } else if (purchase.status == PurchaseStatus.pending) {
          completePurchase = false;
        }
      } finally {
        if (completePurchase && purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
      }
    }
  }

  /// retryable だった購入を検証リトライキューへ登録する。
  /// 永続化に失敗してもストア側が未完了トランザクションを再配信するため、
  /// ここで例外を投げずに継続する。
  Future<void> _enqueueRetryableVerification(PurchaseDetails purchase) async {
    try {
      final record = await _verificationQueue.enqueue(
        productId: purchase.productID,
        serverVerificationData:
            purchase.verificationData.serverVerificationData,
        purchaseId: purchase.purchaseID,
        transactionDate: purchase.transactionDate,
        source: purchase.verificationData.source,
      );
      if (record == null) {
        AppLogger.debug(
          'Remove ads purchase has no verifiable receipt token; '
          'it cannot be queued for retry.',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.debug(
        'Pending verification persist failed: $error\n$stackTrace',
      );
    }
    await _refreshPendingVerificationState();
  }

  Future<void> _refreshPendingVerificationState() async {
    try {
      final records = await _verificationQueue.loadRecords();
      pendingVerificationCount.value = records.length;
      purchaseNeedsConfirmation.value = records.any(
        (record) =>
            record.status == PendingVerificationStatus.needsConfirmation,
      );
    } catch (error) {
      AppLogger.debug('Pending verification state refresh failed: $error');
    }
  }

  Future<void> _setAdFree(bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final cacheSaved = await preferences.setBool(_adFreePreferenceKey, value);
      final timestampSaved = value
          ? await preferences.setInt(
              _adFreeVerifiedAtKey,
              DateTime.now().millisecondsSinceEpoch,
            )
          : await preferences.remove(_adFreeVerifiedAtKey);
      if (!cacheSaved || !timestampSaved) {
        AppLogger.debug('Ad entitlement cache was not persisted completely.');
      }
    } catch (error) {
      AppLogger.debug('Ad preference save failed: $error');
    }
    adFree.value = value;
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    adFree.dispose();
    pendingVerificationCount.dispose();
    purchaseNeedsConfirmation.dispose();
  }
}
