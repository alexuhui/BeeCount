import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/theme_providers.dart';
import '../../providers/database_providers.dart';
import '../../services/share/category_share_service.dart';
import '../../services/sync/sync_version_service.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

class CategoryImportPage extends ConsumerStatefulWidget {
  const CategoryImportPage({super.key});

  @override
  ConsumerState<CategoryImportPage> createState() => _CategoryImportPageState();
}

class _CategoryImportPageState extends ConsumerState<CategoryImportPage> {
  final _codeController = TextEditingController();
  String _code = '';
  bool _isLoading = false;
  bool _isImporting = false;
  CategoryImportResult? _result;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      setState(() {
        _code = _codeController.text.trim().toUpperCase();
      });
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _importCategories() async {
    final l10n = AppLocalizations.of(context);
    if (_code.length != 6) {
      await AppDialog.error(
        context,
        title: l10n.commonError,
        message: l10n.categoryImportCodeInvalid,
      );
      return;
    }

    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.categoryImportConfirmTitle,
      message: l10n.categoryImportConfirmMessage,
    ) ?? false;

    if (!confirmed) return;

    setState(() {
      _isImporting = true;
      _result = null;
    });

    try {
      final service = ref.read(categoryShareServiceProvider);
      final result = await service.importCategories(_code);

      final syncVersionService = ref.read(syncVersionServiceProvider);
      await syncVersionService.checkVersion();

      ref.invalidate(categoriesWithCountProvider);

      if (mounted) {
        setState(() {
          _result = result;
          _isImporting = false;
        });

        await AppDialog.info(
          context,
          title: l10n.categoryImportCompleteTitle,
          message: l10n.categoryImportCompleteMessage(
            result.imported,
            result.skipped,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
        final l10n = AppLocalizations.of(context);
        await AppDialog.error(context, title: l10n.commonError, message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.categoryImportTitle,
            showBack: true,
          ),
          Expanded(
            child: _isImporting
                ? _buildImportingView()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildImportingView() {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            l10n.categoryImporting,
            style: TextStyle(
              fontSize: 16,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.categoryImportingHint,
            style: TextStyle(
              fontSize: 14,
              color: BeeTokens.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: ref.watch(primaryColorProvider),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.categoryImportDescription,
                      style: TextStyle(
                        color: ref.watch(primaryColorProvider),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.categoryImportDescriptionContent,
                  style: TextStyle(
                    color: BeeTokens.textSecondary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            l10n.categoryImportCodeLabel,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              color: BeeTokens.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'XXXXXX',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: ref.watch(primaryColorProvider),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _code.length == 6 && !_isImporting
                  ? _importCategories
                  : null,
              child: Text(l10n.categoryImportButton),
            ),
          ),
          const SizedBox(height: 16),

          if (_result != null) ...[
            const SizedBox(height: 24),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.categoryImportResultTitle,
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.categoryImportResultContent(
                      _result!.imported,
                      _result!.skipped,
                    ),
                    style: TextStyle(
                      color: BeeTokens.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
