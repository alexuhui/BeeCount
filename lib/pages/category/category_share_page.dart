import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/theme_providers.dart';
import '../../services/share/category_share_service.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

class CategorySharePage extends ConsumerStatefulWidget {
  const CategorySharePage({super.key});

  @override
  ConsumerState<CategorySharePage> createState() => _CategorySharePageState();
}

class _CategorySharePageState extends ConsumerState<CategorySharePage> {
  List<CategoryShareCode> _shareCodes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShareCodes();
  }

  Future<void> _loadShareCodes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(categoryShareServiceProvider);
      final codes = await service.getShareCodes();
      if (mounted) {
        setState(() {
          _shareCodes = codes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createShareCode(String shareType) async {
    try {
      final service = ref.read(categoryShareServiceProvider);
      final code = await service.createShareCode(shareType: shareType);
      
      if (mounted) {
        await _showCodeDialog(code);
        await _loadShareCodes();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        await AppDialog.error(context, title: l10n.commonError, message: e.toString());
      }
    }
  }

  Future<void> _showCodeDialog(CategoryShareCode code) async {
    final l10n = AppLocalizations.of(context);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.categoryShareCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.categoryShareCodeMessage,
              style: TextStyle(
                color: BeeTokens.textSecondary(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ref.watch(primaryColorProvider).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code.code,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: ref.watch(primaryColorProvider),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              code.shareType == 'expense' 
                  ? l10n.categoryShareTypeExpense
                  : l10n.categoryShareTypeAll,
              style: TextStyle(
                color: BeeTokens.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code.code));
              if (mounted) {
                showToast(context, l10n.categoryShareCodeCopied);
              }
            },
            icon: const Icon(Icons.content_copy),
            label: Text(l10n.categoryShareCodeCopy),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteShareCode(String code) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.categoryShareDeleteTitle,
      message: l10n.categoryShareDeleteMessage,
    ) ?? false;

    if (!confirmed) return;

    try {
      final service = ref.read(categoryShareServiceProvider);
      await service.deleteShareCode(code);
      await _loadShareCodes();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        await AppDialog.error(context, title: l10n.commonError, message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BeeScaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.categoryShareTitle,
            showBack: true,
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);

    return Padding(
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
                      l10n.categoryShareDescription,
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
                  l10n.categoryShareDescriptionContent,
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
            l10n.categoryShareCreateTitle,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ShareTypeButton(
                  label: l10n.categoryShareTypeExpense,
                  icon: Icons.trending_down,
                  onTap: () => _createShareCode('expense'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ShareTypeButton(
                  label: l10n.categoryShareTypeAll,
                  icon: Icons.category,
                  onTap: () => _createShareCode('all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_shareCodes.isNotEmpty) ...[
            Text(
              l10n.categoryShareMyCodes,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: BeeTokens.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _shareCodes.length,
                itemBuilder: (context, index) {
                  final code = _shareCodes[index];
                  return _ShareCodeTile(
                    code: code,
                    onDelete: () => _deleteShareCode(code.code),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareTypeButton extends ConsumerWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ShareTypeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: primaryColor,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCodeTile extends ConsumerWidget {
  final CategoryShareCode code;
  final VoidCallback onDelete;

  const _ShareCodeTile({
    required this.code,
    required this.onDelete,
  });

  Future<void> _copyCode(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: code.code));
    if (context.mounted) {
      showToast(context, l10n.categoryShareCodeCopied);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        border: Border.all(color: BeeTokens.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              code.code,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
        ),
        title: Text(
          code.shareType == 'expense'
              ? l10n.categoryShareTypeExpense
              : l10n.categoryShareTypeAll,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: BeeTokens.textPrimary(context),
          ),
        ),
        subtitle: Text(
          _formatDate(code.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: BeeTokens.textSecondary(context),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.content_copy,
                color: primaryColor,
              ),
              onPressed: () => _copyCode(context, ref),
              tooltip: l10n.categoryShareCodeCopy,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: BeeTokens.iconSecondary(context),
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
