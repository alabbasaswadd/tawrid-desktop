import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tawrid_app/app/router/routes.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/models/enums.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/repositories/sales_offer_repository.dart';
import 'package:tawrid_app/repositories/warehouse_profile_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/widgets/offer_summary_card.dart';
import 'package:tawrid_app/shared/utils/relative_time.dart';
import 'package:tawrid_app/shared/widgets/app_states.dart';
import 'package:tawrid_app/shared/widgets/chat_sheet.dart';
import 'package:tawrid_app/core/state/inventory_revision.dart';
import 'package:tawrid_app/shared/utils/export.dart';

// شرائح عروض المستودع (Figma): الكل، منشور، مسودة، متوقف، منتهٍ.
enum _OffersTab {
  all('الكل'),
  published('منشور'),
  draft('مسودة'),
  stopped('متوقف'),
  expired('منتهٍ');

  const _OffersTab(this.label);
  final String label;

  bool matches(SalesOfferStatus s) => switch (this) {
        _OffersTab.all => true,
        _OffersTab.published => s == SalesOfferStatus.active,
        _OffersTab.draft => s == SalesOfferStatus.draft,
        _OffersTab.stopped => s == SalesOfferStatus.cancelled,
        _OffersTab.expired => s == SalesOfferStatus.expired,
      };
}

/// محور ثانٍ مستقلّ عن الحالة: الحالة تقول «أين وصل العرض» والنوع يقول
/// «ما طبيعته». خلطُهما في صفٍّ واحد يجعل «منشور» و«ثابت» يبدوان بديلين
/// وهما ليسا كذلك — فعرضٌ منشورٌ وثابتٌ معاً أمرٌ عادي.
enum _KindTab {
  all('كل الأنواع'),
  standing('ثابتة'),
  timeLimited('لفترة محدّدة');

  const _KindTab(this.label);
  final String label;

  bool matches(SalesOfferKind k) => switch (this) {
        _KindTab.all => true,
        _KindTab.standing => k == SalesOfferKind.standing,
        _KindTab.timeLimited => k == SalesOfferKind.timeLimited,
      };
}

// عروضي عند المستودع (Figma: المستودع / العروض).
//
// شاشة إدارة لا تصفّح: لكل عرض حالته وإجراءاه، والسطر العلوي ينبّه إلى
// ما يقارب على الانتهاء قبل أن ينتهي صامتاً.
class WhOffersPage extends ConsumerStatefulWidget {
  const WhOffersPage({super.key});

  @override
  ConsumerState<WhOffersPage> createState() => _WhOffersPageState();
}

class _WhOffersPageState extends ConsumerState<WhOffersPage> {
  List<SalesOfferSummary>? _offers;
  bool _loading = true;
  bool _busy = false;
  ApiException? _error;
  _OffersTab _tab = _OffersTab.all;
  _KindTab _kind = _KindTab.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final list =
          await ref.read(salesOfferRepositoryProvider).getMyOffers(limit: 50);
      if (!mounted) return;
      setState(() {
        _offers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e);
        _loading = false;
      });
    }
  }

  /// أعمدة تصدير قائمة العروض.
  static List<ExportColumn<SalesOfferSummary>> _offerColumns() => [
        ExportColumn(
          header: 'العرض',
          value: (o) => o.title,
          width: 34,
          pdfFlex: 5,
        ),
        ExportColumn(
          header: 'الحالة',
          value: (o) => switch (o.status) {
            SalesOfferStatus.active => 'منشور',
            SalesOfferStatus.draft => 'مسودة',
            SalesOfferStatus.cancelled => 'متوقف',
            SalesOfferStatus.expired => 'منتهٍ',
          },
          width: 12,
        ),
        ExportColumn(
          header: 'الأصناف',
          value: (o) => o.itemCount,
          width: 10,
        ),
        ExportColumn(
          header: 'النوع',
          value: (o) => o.expiresAt == null ? 'ثابت' : 'مؤقّت',
          width: 10,
        ),
        ExportColumn(
          header: 'يبدأ',
          value: (o) => _day(o.startsAt),
          width: 13,
        ),
        ExportColumn(
          header: 'ينتهي',
          value: (o) => o.expiresAt == null ? 'بلا نهاية' : _day(o.expiresAt!),
          width: 13,
        ),
        ExportColumn(
          header: 'المناطق',
          value: (o) => o.targetRegions.isEmpty
              ? 'كل مناطق الخدمة'
              : o.targetRegions.map((r) => r.label).join('، '),
          width: 30,
          pdfFlex: 4,
        ),
        ExportColumn(
          header: 'بونص',
          value: (o) => o.hasItemBonus || o.hasOfferBonus ? 'نعم' : '—',
          width: 8,
        ),
      ];

  /// تاريخٌ قصير للتصدير — لا «منذ ساعة»: الملف يُقرأ بعد شهر.
  static String _day(DateTime d) {
    final l = d.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/'
        '${l.day.toString().padLeft(2, '0')}';
  }

  List<SalesOfferSummary> get _active => (_offers ?? const [])
      .where((o) => o.status == SalesOfferStatus.active)
      .toList();

  List<SalesOfferSummary> get _expiringSoon =>
      _active.where((o) => isOfferExpiringSoon(o.expiresAt)).toList();

  /// كم من السارية ثابتٌ لا ينتهي — يُقال في سطر الحالة لأن بقيّته مؤقّتة.
  int get _standingActive =>
      _active.where((o) => o.kind == SalesOfferKind.standing).length;

  Future<void> _publish(SalesOfferSummary offer) async {
    setState(() => _busy = true);
    try {
      await ref.read(salesOfferRepositoryProvider).publishOffer(offer.id);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      final updated = (_offers ?? []).where((o) => o.id == offer.id).firstOrNull;
      if (updated?.status == SalesOfferStatus.draft) {
        final tk = context.tokens;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تم حفظ العرض كمسودة وليس منشوراً بعد',
              style: TextStyle(color: Colors.white)),
          backgroundColor: tk.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      } else {
        AppSnackbar.success(context, 'نُشر العرض');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(SalesOfferSummary offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف العرض'),
        content:
            const Text('لن تراه الصيدليات بعد الإيقاف، ولا يمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(salesOfferRepositoryProvider).cancelOffer(offer.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'أُوقف العرض');
      await _load(silent: true);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openComments(SalesOfferSummary offer) {
    final repo = ref.read(salesOfferRepositoryProvider);
    return ChatSheet.show(
      context,
      title: 'دردشة مع الصيدليات',
      currentUserType: 'warehouse',
      loadMessages: () => repo.getWarehouseComments(offer.id),
      sendMessage: (text) => repo.addWarehouseComment(offer.id, text),
    );
  }

  @override
  Widget build(BuildContext context) {
    // مخزونٌ تغيّر من شاشة الاستيراد — تُعاد القائمة بهدوء بلا مؤشّر
    // تحميلٍ يقطع ما يقرأه المستخدم.
    ref.listen(inventoryRevisionProvider, (_, _) => _load(silent: true));

    return Scaffold(
      appBar: AppBar(
        title: const Text('عروضي'),
        actions: [
          ExportButton<SalesOfferSummary>(
            compact: true,
            fileName: 'عروضي',
            title: 'عروض المستودع',
            issuer: ref.watch(warehouseMeProvider).value?.warehouseName,
            sheetName: 'العروض',
            facts: [
              (label: 'عدد العروض', value: '${(_offers ?? const []).length}'),
              (label: 'السارية', value: '${_active.length}'),
            ],
            columns: _offerColumns(),
            rows: _offers ?? const [],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'wh_offers_fab',
        tooltip: 'إنشاء عرض جديد',
        onPressed: () async {
          await context.push(TRoutes.whCreateOffer);
          if (mounted) await _load(silent: true);
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppListSkeleton();
    if (_error != null) return ErrorState.of(_error!, onRetry: _load);

    final all = _offers ?? const <SalesOfferSummary>[];
    final shown = all
        .where((o) => _tab.matches(o.status) && _kind.matches(o.kind))
        .toList();
    final expiring = _expiringSoon.length;
    final tk = context.tokens;

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: _OffersTab.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) {
              final t = _OffersTab.values[i];
              return AppFilterChip(
                label: t.label,
                selected: _tab == t,
                onTap: () => setState(() => _tab = t),
              );
            },
          ),
        ),

        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: _KindTab.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) {
              final k = _KindTab.values[i];
              return AppFilterChip(
                label: k.label,
                selected: _kind == k,
                onTap: () => setState(() => _kind = k),
              );
            },
          ),
        ),

        // سطر الحالة: السارية، ثم تحذير ما يقارب على الانتهاء.
        Padding(
          padding: EdgeInsets.fromLTRB(context.pageGutter, AppSpacing.md,
              context.pageGutter, AppSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              [
                '${_active.length} ${_active.length == 1 ? 'عرض سارٍ' : 'عرضاً سارياً'}',
                if (_standingActive > 0) '$_standingActive ثابت',
                // المسوّدات تُذكر في السطر نفسه: عرضٌ أُنشئ ولم يُنشَر
                // خبرٌ يخصّ صاحبه، وإخفاؤه خلف تبويبٍ يجعل الاستيراد
                // يبدو كأنه لم يُنتج شيئاً.
                if (_drafts > 0) '$_drafts مسوّدة لم تُنشَر',
                if (expiring > 0)
                  '$expiring ${expiring == 1 ? 'ينتهي قريباً' : 'تنتهي قريباً'}',
              ].join(' · '),
              style: context.text.bodySmall
                  ?.copyWith(color: expiring > 0 ? tk.warning : tk.hint),
            ),
          ),
        ),

        Expanded(
          child: shown.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: AppSpacing.x3l),
                    EmptyState(
                      icon: Icons.sell_outlined,
                      message: _tab == _OffersTab.all && _kind == _KindTab.all
                          ? 'لا عروض بعد — أنشئ عرضاً ليصل الصيدليات التي تخدمها'
                          : 'لا عروض في «${_tab.label}» ضمن «${_kind.label}»',
                    ),
                  ],
                )
              : AdaptiveCardGrid(
                  padding: EdgeInsets.fromLTRB(
                      context.pageGutter, 0, context.pageGutter, 88),
                  itemCount: shown.length,
                  tileHeight: 210,
                  minTileWidth: 400,
                  maxColumns: 4,
                  itemBuilder: (_, i) => _card(shown[i]),
                ),
        ),
      ],
    );
  }

  int get _drafts =>
      (_offers ?? const <SalesOfferSummary>[])
          .where((o) => o.status == SalesOfferStatus.draft)
          .length;

  Widget _card(SalesOfferSummary o) {
    // العرض الثابت لا يوشك على الانتهاء — لا تاريخ له.
    final expiringSoon =
        o.status == SalesOfferStatus.active && isOfferExpiringSoon(o.expiresAt);

    // «ينتهي قريباً» تسبق «منشور» في الشارة: الأهمّ ما يستدعي إجراءً،
    // لا ما هو قائم أصلاً.
    final (label, tone) = switch (o.status) {
      SalesOfferStatus.active when expiringSoon =>
        ('ينتهي قريباً', StatusTone.warning),
      SalesOfferStatus.active => ('منشور', StatusTone.success),
      SalesOfferStatus.draft => ('مسودة', StatusTone.neutral),
      SalesOfferStatus.cancelled => ('متوقف', StatusTone.danger),
      SalesOfferStatus.expired => ('منتهٍ', StatusTone.neutral),
    };

    final bonus = switch ((o.hasItemBonus, o.hasOfferBonus)) {
      (true, true) => 'بونص أصناف + بونص على كامل العرض',
      (true, false) => 'بونص أصناف فقط',
      (false, true) => 'بونص على كامل العرض',
      _ => 'بلا بونص',
    };

    return WarehouseOfferCard(
      title: o.title,
      itemsText: '${o.itemCount} ${o.itemCount == 1 ? 'صنف' : 'أصناف'} · $bonus',
      expiryText: switch (o.status) {
        SalesOfferStatus.draft => 'لم تُنشر بعد',
        // العرض الثابت: نوعُه هو الخبر، لا تاريخٌ لا وجود له.
        _ when o.expiresAt == null => o.kind.label,
        SalesOfferStatus.cancelled =>
          'أُوقف ${formatSmartTimestamp(o.expiresAt!)}',
        _ when o.expiresAt!.isBefore(DateTime.now()) =>
          'انتهى ${formatSmartTimestamp(o.expiresAt!)}',
        _ => 'ينتهي ${formatSmartTimestamp(o.expiresAt!)}',
      },
      statusLabel: label,
      statusTone: tone,
      lastUpdateText: 'أُنشئ ${formatSmartTimestamp(o.createdOn)}',
      // المسودة تُنشر، والمنشور تُقرأ تعليقاته — الزرّ يسمّي ما سيحدث فعلاً.
      // (الخادم لا يتيح تعديل عرض منشور، فلا نَعِد بزرّ «تعديل».)
      editLabel: o.status == SalesOfferStatus.draft ? 'نشر' : 'التعليقات',
      onEdit: _busy
          ? null
          : o.status == SalesOfferStatus.draft
              ? () => _publish(o)
              : () => _openComments(o),
      // الإيقاف للمسودة والمنشور فقط — ما انتهى أو أُوقف لا يُوقف.
      onStop: _busy ||
              o.status == SalesOfferStatus.expired ||
              o.status == SalesOfferStatus.cancelled
          ? null
          : () => _stop(o),
      onTap: () => context.push(TRoutes.whOfferDetail(o.id)),
    );
  }
}
