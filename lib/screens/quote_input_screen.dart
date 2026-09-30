/// ファイルパス: lib/screens/quote_input_screen.dart
/// PDF・カメラ・写真から見積を取り込み、OCR結果を確認して保存する画面。
library;

import '../utils/app_logger.dart';

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/category_master.dart';
import '../models.dart';
import '../ocr_models.dart';
import '../quote_revision_models.dart';
import '../repositories/project_repository.dart';
import '../services/id_generator.dart';
import '../services/ocr_review_store.dart';
import '../services/ocr_service.dart';
import '../validation/input_validators.dart';
import '../widgets/ocr_review_widgets.dart';

class QuoteInputScreen extends StatefulWidget {
  const QuoteInputScreen({
    super.key,
    required this.project,
    this.repository,
    this.ocrService,
    this.reviewStore,
    this.initialQuote,
    this.initialReviewBundle,
    this.revisionIntent = const QuoteImportIntent.newQuote(),
  });

  final Project project;
  final ProjectRepository? repository;
  final OcrService? ocrService;
  final OcrReviewStore? reviewStore;
  final RawQuoteData? initialQuote;
  final OcrReviewBundle? initialReviewBundle;
  final QuoteImportIntent revisionIntent;

  @override
  State<QuoteInputScreen> createState() => _QuoteInputScreenState();
}

class _QuoteInputScreenState extends State<QuoteInputScreen> {
  late final bool _ownsOcrService = widget.ocrService == null;
  late final OcrService _ocrService = widget.ocrService ?? OcrService();
  late final OcrReviewStore _reviewStore =
      widget.reviewStore ?? OcrReviewStore();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _contractorController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();

  RawQuoteData? _rawQuote;
  OcrReviewBundle? _reviewBundle;
  String? _documentReviewKey;
  Map<String, OcrReviewStatus> _reviewStatuses = {};
  List<_EditableLineItem> _editableItems = [];
  String? _pendingQuoteId;
  bool _processing = false;
  bool _saving = false;
  String? _error;

  ProjectRepository get _repository =>
      widget.repository ?? ProjectRepository.instance;

  @override
  void initState() {
    super.initState();
    final initialQuote = widget.initialQuote;
    if (initialQuote == null) return;

    _rawQuote = initialQuote;
    _documentReviewKey = initialQuote.sourcePath;
    _reviewBundle = widget.initialReviewBundle;
    _reviewStatuses = {
      for (final line in widget.initialReviewBundle?.lines ?? const [])
        line.id: line.initialStatus,
      for (final issue in widget.initialReviewBundle?.issues ?? const [])
        issue.id: issue.initialStatus,
    };
    _contractorController.text = initialQuote.contractorName;
    _totalController.text = initialQuote.totalAmountYen == null
        ? ''
        : NumberFormat('#,##0', 'ja_JP').format(initialQuote.totalAmountYen);
    _replaceEditableItems(initialQuote.lineItems, const []);
  }

  @override
  void dispose() {
    _contractorController.dispose();
    _totalController.dispose();
    for (final item in _editableItems) {
      item.dispose();
    }
    if (_ownsOcrService) unawaited(_ocrService.dispose());
    super.dispose();
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path != null) await _process(path);
    } catch (error, stackTrace) {
      AppLogger.debug('PDF picker failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = 'PDFを開けませんでした。ファイルを選び直してください。');
      }
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('quote-camera-option'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('カメラで撮影'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                key: const ValueKey('quote-gallery-option'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('写真ライブラリから選択'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (image != null) await _process(image.path);
    } catch (error, stackTrace) {
      AppLogger.debug('Image picker failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = '写真を開けませんでした。カメラ・写真へのアクセス権限を確認してください。');
      }
    }
  }

  Future<void> _process(String path) async {
    if (!mounted) return;
    setState(() {
      _processing = true;
      _error = null;
      _rawQuote = null;
      _reviewBundle = null;
      _documentReviewKey = null;
      _reviewStatuses = {};
      _pendingQuoteId = null;
      _replaceEditableItems(const [], const []);
    });

    try {
      final result = await _ocrService.extractQuote(path);
      final bundle =
          _ocrService.lastReviewBundle ??
          const OcrReviewBundle(lines: [], issues: []);
      final documentKey = _ocrService.lastSourceFileHash ?? result.sourcePath;
      final persisted = await _reviewStore.load(documentKey);
      final statuses = <String, OcrReviewStatus>{
        for (final line in bundle.lines) line.id: line.initialStatus,
        for (final issue in bundle.issues) issue.id: issue.initialStatus,
        ...persisted,
      };
      if (!mounted) return;
      _contractorController.text = result.contractorName;
      _totalController.text = result.totalAmountYen == null
          ? ''
          : NumberFormat('#,##0', 'ja_JP').format(result.totalAmountYen);
      setState(() {
        _rawQuote = result;
        _reviewBundle = bundle;
        _documentReviewKey = documentKey;
        _reviewStatuses = statuses;
        _replaceEditableItems(result.lineItems, bundle.lines);
      });
    } on OcrException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      AppLogger.debug('OCR processing failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = '文字の読み取りに失敗しました。画像の明るさ・向き・解像度を確認してください。');
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _replaceEditableItems(
    List<RawQuoteLineItem> items,
    List<OcrRecognizedLine> recognizedLines,
  ) {
    for (final item in _editableItems) {
      item.dispose();
    }
    final remaining = List<OcrRecognizedLine>.from(recognizedLines);
    _editableItems = items
        .map((item) {
          final matchIndex = remaining.indexWhere(
            (line) =>
                line.rawText == item.rawLabel &&
                line.categoryCandidates.contains(item.categoryId),
          );
          final sourceLine = matchIndex < 0
              ? null
              : remaining.removeAt(matchIndex);
          return _EditableLineItem.fromModel(item, sourceLine: sourceLine);
        })
        .toList(growable: true);
  }

  void _addLineItem() {
    setState(() => _editableItems.add(_EditableLineItem.empty()));
  }

  void _removeLineItem(int index) {
    setState(() {
      final removed = _editableItems.removeAt(index);
      removed.dispose();
    });
  }

  OcrReviewStatus _statusFor(OcrRecognizedLine line) =>
      _reviewStatuses[line.id] ?? line.initialStatus;

  void _setReviewStatus(String id, OcrReviewStatus status) {
    final documentKey = _documentReviewKey;
    setState(() => _reviewStatuses[id] = status);
    if (documentKey != null) {
      unawaited(_reviewStore.save(documentKey, _reviewStatuses));
    }
  }

  void _confirmNonCriticalItems() {
    final bundle = _reviewBundle;
    if (bundle == null) return;
    final updated = Map<String, OcrReviewStatus>.from(_reviewStatuses);
    for (final line in bundle.lines) {
      if (line.severity != OcrReviewSeverity.critical &&
          (_statusFor(line) == OcrReviewStatus.pending)) {
        updated[line.id] = OcrReviewStatus.confirmed;
      }
    }
    for (final issue in bundle.issues) {
      if (issue.severity != OcrReviewSeverity.critical &&
          (_reviewStatuses[issue.id] ?? issue.initialStatus) ==
              OcrReviewStatus.pending) {
        updated[issue.id] = OcrReviewStatus.confirmed;
      }
    }
    setState(() => _reviewStatuses = updated);
    final documentKey = _documentReviewKey;
    if (documentKey != null) unawaited(_reviewStore.save(documentKey, updated));
  }

  int _criticalPendingCount() {
    final bundle = _reviewBundle;
    if (bundle == null) return 0;
    final criticalLines = bundle.lines.where(
      (line) =>
          line.severity == OcrReviewSeverity.critical &&
          (_reviewStatuses[line.id] ?? line.initialStatus) ==
              OcrReviewStatus.pending,
    );
    final criticalIssues = bundle.issues.where(
      (issue) =>
          issue.severity == OcrReviewSeverity.critical &&
          (_reviewStatuses[issue.id] ?? issue.initialStatus) ==
              OcrReviewStatus.pending,
    );
    return criticalLines.length + criticalIssues.length;
  }

  Future<bool> _confirmSaveWithCriticalItems() async {
    final count = _criticalPendingCount();
    if (count == 0) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.warning_amber_outlined),
            title: const Text('重大な未確認項目があります'),
            content: Text('合計不一致や数量×単価不一致など、$count件が未確認です。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('確認に戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('未確認のまま保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    final rawQuote = _rawQuote;
    if (rawQuote == null || _saving) return;
    final formValid = _formKey.currentState?.validate() ?? false;
    debugPrint(
      'QUOTE_SAVE_PREFLIGHT formValid=$formValid '
      'reviewBundleIssues=${_reviewBundle?.issues.length ?? 0} '
      'reviewBundleLines=${_reviewBundle?.lines.length ?? 0} '
      'criticalPending=${_criticalPendingCount()}',
    );
    AppLogger.debug(
      'Quote save preflight: formValid=$formValid '
      'reviewBundleIssues=${_reviewBundle?.issues.length ?? 0} '
      'reviewBundleLines=${_reviewBundle?.lines.length ?? 0} '
      'criticalPending=${_criticalPendingCount()}',
    );
    if (!formValid) {
      debugPrint(
        'QUOTE_FIELDS contractor=${_contractorController.text} '
        'total=${_totalController.text} totalError=${validateAmount(_totalController.text, maxDecimalPlaces: 0)} '
        'items=${_editableItems.map((item) => 'label=${item.rawLabelController.text},amount=${item.amountController.text},amountError=${validateAmount(item.amountController.text, allowZero: true, maxDecimalPlaces: 0)},quantity=${item.quantityController.text},quantityError=${validateQuantity(item.quantityController.text)}').join('|')}',
      );
    }
    if (!formValid) return;
    if (!await _confirmSaveWithCriticalItems()) return;

    late final List<RawQuoteLineItem> lineItems;
    try {
      lineItems = [
        for (var index = 0; index < _editableItems.length; index++)
          _editableItems[index].toModel(index),
      ];
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    final totalAmountYen = int.tryParse(
      _totalController.text.trim().replaceAll(',', ''),
    );
    if (totalAmountYen == null) {
      setState(() => _error = '提示総額を整数（円）で入力してください。');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final corrected = RawQuoteData(
        contractorName: _contractorController.text.trim(),
        totalAmountYen: totalAmountYen,
        lineItems: lineItems,
        extractedText: rawQuote.extractedText,
        sourcePath: rawQuote.sourcePath,
        createdAtEpochMillis: rawQuote.createdAtEpochMillis,
      );
      final quoteId = _pendingQuoteId ??= IdGenerator.prefixed('quote');
      final quote = corrected.toContractorQuote(id: quoteId);
      final documentKey = _documentReviewKey;
      await _repository.saveQuote(
        widget.project.id,
        quote,
        revisionIntent: widget.revisionIntent,
        sourceFileHash:
            documentKey != null &&
                RegExp(r'^[0-9a-f]{64}$').hasMatch(documentKey)
            ? documentKey
            : null,
      );
      if (documentKey != null) {
        await _reviewStore.save(documentKey, _reviewStatuses);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('見積を保存しました。')));
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      AppLogger.debug('Quote save failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = '見積の保存に失敗しました。入力内容を確認して、もう一度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawQuote = _rawQuote;
    final bundle = _reviewBundle;
    final ocrSupported = OcrService.isSupportedPlatform;

    return Scaffold(
      appBar: AppBar(
        title: const Text('編集'),
        actions: [
          IconButton(
            key: const ValueKey('quote-save-button'),
            tooltip: '確認して保存',
            onPressed: rawQuote == null || _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                '外構工事の見積書を取り込む',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            const Text('PDFまたは写真を読み取り、内容を確認してから保存します。'),
            const SizedBox(height: 12),
            Card(
              key: const ValueKey('quote-exterior-scope-warning'),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '対応範囲は外構工事の固定18カテゴリです。内装リフォーム・引越し・車検など他分野の見積書は取り込まず、分野に合った方法で確認してください。',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (ocrSupported)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('quote-pdf-button'),
                    onPressed: _processing ? null : _pickPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDFを選択'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('quote-photo-button'),
                    onPressed: _processing ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('写真から取り込む'),
                  ),
                ],
              )
            else
              const Card(
                key: ValueKey('quote-ocr-unsupported'),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '見積書のOCR取込はAndroid・iOSで利用できます。モバイル端末でこの案件を開いてください。',
                  ),
                ),
              ),
            if (_processing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('文字を読み取っています…'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ],
            if (rawQuote != null) ...[
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('quote-contractor-field'),
                controller: _contractorController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '業者名',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '業者名を入力してください。'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('quote-total-field'),
                controller: _totalController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: '提示総額（税込・円）',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    validateAmount(value, maxDecimalPlaces: 0),
              ),
              if (bundle != null &&
                  (bundle.lines.isNotEmpty || bundle.issues.isNotEmpty)) ...[
                const SizedBox(height: 16),
                OcrReviewOverview(
                  bundle: bundle,
                  statuses: _reviewStatuses,
                  onStatusChanged: _setReviewStatus,
                  onConfirmNonCritical: _confirmNonCriticalItems,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '明細',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addLineItem,
                    icon: const Icon(Icons.add),
                    label: const Text('明細を追加'),
                  ),
                ],
              ),
              if (_editableItems.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('明細がありません。必要に応じて追加してください。'),
                  ),
                ),
              for (var index = 0; index < _editableItems.length; index++) ...[
                _LineItemEditor(
                  index: index,
                  item: _editableItems[index],
                  reviewStatus: _editableItems[index].sourceLine == null
                      ? null
                      : _statusFor(_editableItems[index].sourceLine!),
                  onReviewStatusChanged:
                      _editableItems[index].sourceLine == null
                      ? null
                      : (status) => _setReviewStatus(
                          _editableItems[index].sourceLine!.id,
                          status,
                        ),
                  onRemove: () => _removeLineItem(index),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '確認して保存'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineItemEditor extends StatelessWidget {
  const _LineItemEditor({
    required this.index,
    required this.item,
    required this.onRemove,
    this.reviewStatus,
    this.onReviewStatusChanged,
  });

  final int index;
  final _EditableLineItem item;
  final VoidCallback onRemove;
  final OcrReviewStatus? reviewStatus;
  final ValueChanged<OcrReviewStatus>? onReviewStatusChanged;

  @override
  Widget build(BuildContext context) {
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('明細 ${index + 1}')),
            IconButton(
              tooltip: '明細${index + 1}を削除',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        TextFormField(
          key: ValueKey('quote-line-label-$index'),
          controller: item.rawLabelController,
          decoration: const InputDecoration(
            labelText: '項目名',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '項目名を入力してください。' : null,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: item.categoryId,
          decoration: const InputDecoration(
            labelText: 'カテゴリ（自動判定・変更可）',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in CategoryMaster.categories)
              DropdownMenuItem(
                value: category.id,
                child: Text(category.nameJa),
              ),
          ],
          onChanged: (value) {
            if (value != null) item.categoryId = value;
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<InclusionStatus>(
          initialValue: item.inclusionStatus,
          decoration: const InputDecoration(
            labelText: '見積への含まれ方',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final status in InclusionStatus.values)
              DropdownMenuItem(value: status, child: Text(status.labelJa)),
          ],
          onChanged: (value) {
            if (value != null) item.inclusionStatus = value;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('quote-line-amount-$index'),
          controller: item.amountController,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: '金額（円・未記載は空欄）',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            return validateAmount(value, allowZero: true, maxDecimalPlaces: 0);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey('quote-line-quantity-$index'),
                controller: item.quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '数量',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  return validateQuantity(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: item.unitController,
                decoration: const InputDecoration(
                  labelText: '単位',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: item.specificationController,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '仕様・備考',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );

    final sourceLine = item.sourceLine;
    if (sourceLine == null ||
        reviewStatus == null ||
        onReviewStatusChanged == null) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(12), child: editor),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final review = OcrLineReviewPanel(
              line: sourceLine,
              status: reviewStatus!,
              onChanged: onReviewStatusChanged!,
            );
            if (constraints.maxWidth >= 680) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 220, child: review),
                  const SizedBox(width: 16),
                  Expanded(child: editor),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [review, const SizedBox(height: 12), editor],
            );
          },
        ),
      ),
    );
  }
}

class _EditableLineItem {
  _EditableLineItem({
    required this.rawLabelController,
    required this.amountController,
    required this.quantityController,
    required this.unitController,
    required this.specificationController,
    required this.categoryId,
    required this.inclusionStatus,
    this.note,
    this.sourceLine,
  });

  factory _EditableLineItem.fromModel(
    RawQuoteLineItem item, {
    OcrRecognizedLine? sourceLine,
  }) => _EditableLineItem(
    rawLabelController: TextEditingController(text: item.rawLabel),
    amountController: TextEditingController(
      text: item.amountYen?.toString() ?? '',
    ),
    quantityController: TextEditingController(
      text: item.quantity?.toString() ?? '',
    ),
    unitController: TextEditingController(text: item.unit ?? ''),
    specificationController: TextEditingController(
      text: item.specification ?? '',
    ),
    categoryId: CategoryMaster.find(item.categoryId) == null
        ? CategoryMaster.categories.first.id
        : item.categoryId,
    inclusionStatus: item.inclusionStatus,
    note: item.note,
    sourceLine: sourceLine,
  );

  factory _EditableLineItem.empty() => _EditableLineItem(
    rawLabelController: TextEditingController(),
    amountController: TextEditingController(),
    quantityController: TextEditingController(),
    unitController: TextEditingController(),
    specificationController: TextEditingController(),
    categoryId: CategoryMaster.categories.first.id,
    inclusionStatus: InclusionStatus.unknown,
  );

  final TextEditingController rawLabelController;
  final TextEditingController amountController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController specificationController;
  String categoryId;
  InclusionStatus inclusionStatus;
  final String? note;
  final OcrRecognizedLine? sourceLine;

  RawQuoteLineItem toModel(int index) {
    final rawLabel = rawLabelController.text.trim();
    if (rawLabel.isEmpty) {
      throw FormatException('明細${index + 1}の項目名を入力してください。');
    }

    final amountText = amountController.text.trim().replaceAll(',', '');
    final amount = amountText.isEmpty ? null : int.tryParse(amountText);
    if (amountText.isNotEmpty && amount == null) {
      throw FormatException('明細${index + 1}の金額を整数で入力してください。');
    }

    final quantityText = quantityController.text.trim().replaceAll(',', '');
    final quantity = quantityText.isEmpty
        ? null
        : double.tryParse(quantityText);
    if (quantityText.isNotEmpty &&
        (quantity == null || !quantity.isFinite || quantity <= 0)) {
      throw FormatException('明細${index + 1}の数量は0より大きい数値で入力してください。');
    }

    final specification = specificationController.text.trim();
    if (specification.length > 500) {
      throw FormatException('明細${index + 1}の仕様は500文字以内で入力してください。');
    }

    return RawQuoteLineItem(
      rawLabel: rawLabel,
      categoryId: categoryId,
      amountYen: amount,
      inclusionStatus: inclusionStatus,
      quantity: quantity,
      unit: unitController.text.trim().isEmpty
          ? null
          : unitController.text.trim(),
      specification: specification.isEmpty ? null : specification,
      note: note,
    );
  }

  void dispose() {
    rawLabelController.dispose();
    amountController.dispose();
    quantityController.dispose();
    unitController.dispose();
    specificationController.dispose();
  }
}
