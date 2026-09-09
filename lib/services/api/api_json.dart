import '../../data/db.dart';
import 'beecount_api_exception.dart';

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

int? asIntN(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

double asDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

DateTime asDate(dynamic v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  if (v is num) {
    final n = v.toInt();
    if (n > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    return DateTime.fromMillisecondsSinceEpoch(n * 1000);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? asDateN(dynamic v) => v == null ? null : asDate(v);

dynamic pick(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k) && m[k] != null) return m[k];
  }
  return null;
}

List<Map<String, dynamic>> asItemMaps(dynamic data) {
  if (data is List) {
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  if (data is Map && data['items'] is List) {
    return (data['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  return const [];
}

PagedResult<Map<String, dynamic>> parsePagedMaps(dynamic data) {
  if (data is List) {
    final items = asItemMaps(data);
    return PagedResult(
      items: items,
      page: 1,
      pageSize: items.length,
      total: items.length,
    );
  }
  final map = Map<String, dynamic>.from(data as Map);
  final items = asItemMaps(map);
  return PagedResult(
    items: items,
    page: asInt(map['page'], 1),
    pageSize: asInt(map['page_size'] ?? map['pageSize'], items.length),
    total: asInt(map['total'], items.length),
  );
}

Ledger ledgerFromJson(Map<String, dynamic> m) => Ledger(
      id: asInt(pick(m, ['id'])),
      name: '${pick(m, ['name']) ?? ''}',
      currency: '${pick(m, ['currency']) ?? 'CNY'}',
      type: '${pick(m, ['type']) ?? 'personal'}',
      createdAt: asDate(pick(m, ['createdAt', 'created_at'])),
    );

Account accountFromJson(Map<String, dynamic> m) => Account(
      id: asInt(pick(m, ['id'])),
      ledgerId: asInt(pick(m, ['ledger_id', 'ledgerId'])),
      name: '${pick(m, ['name']) ?? ''}',
      type: '${pick(m, ['type']) ?? 'cash'}',
      currency: '${pick(m, ['currency']) ?? 'CNY'}',
      initialBalance: asDouble(pick(m, ['initial_balance', 'initialBalance'])),
      createdAt: asDateN(pick(m, ['created_at', 'createdAt'])),
      updatedAt: asDateN(pick(m, ['updated_at', 'updatedAt'])),
    );

Category categoryFromJson(Map<String, dynamic> m) => Category(
      id: asInt(pick(m, ['id'])),
      name: '${pick(m, ['name']) ?? ''}',
      kind: '${pick(m, ['kind']) ?? 'expense'}',
      icon: pick(m, ['icon'])?.toString(),
      sortOrder: asInt(pick(m, ['sort_order', 'sortOrder'])),
      parentId: asIntN(pick(m, ['parent_id', 'parentId'])),
      level: asInt(pick(m, ['level']), 1),
      iconType: '${pick(m, ['icon_type', 'iconType']) ?? 'material'}',
      customIconPath: pick(m, ['custom_icon_path', 'customIconPath'])?.toString(),
      communityIconId:
          pick(m, ['community_icon_id', 'communityIconId'])?.toString(),
    );

Transaction txFromJson(Map<String, dynamic> m) => Transaction(
      id: asInt(pick(m, ['id'])),
      ledgerId: asInt(pick(m, ['ledger_id', 'ledgerId'])),
      type: '${pick(m, ['type']) ?? 'expense'}',
      amount: asDouble(pick(m, ['amount'])),
      categoryId: asIntN(pick(m, ['category_id', 'categoryId'])),
      accountId: asIntN(pick(m, ['account_id', 'accountId'])),
      toAccountId: asIntN(pick(m, ['to_account_id', 'toAccountId'])),
      happenedAt: asDate(pick(m, ['happened_at', 'happenedAt'])),
      note: pick(m, ['note'])?.toString(),
      recurringId: asIntN(pick(m, ['recurring_id', 'recurringId'])),
      excludeFromStats:
          asBool(pick(m, ['exclude_from_stats', 'excludeFromStats'])),
      receivableId: asIntN(pick(m, ['receivable_id', 'receivableId'])),
      payableId: asIntN(pick(m, ['payable_id', 'payableId'])),
      receivablePaymentId:
          asIntN(pick(m, ['receivable_payment_id', 'receivablePaymentId'])),
      payablePaymentId:
          asIntN(pick(m, ['payable_payment_id', 'payablePaymentId'])),
      investEvent: pick(m, ['invest_event', 'investEvent'])?.toString(),
    );

RecurringTransaction recurringFromJson(Map<String, dynamic> m) =>
    RecurringTransaction(
      id: asInt(pick(m, ['id'])),
      ledgerId: asInt(pick(m, ['ledger_id', 'ledgerId'])),
      type: '${pick(m, ['type']) ?? 'expense'}',
      amount: asDouble(pick(m, ['amount'])),
      categoryId: asIntN(pick(m, ['category_id', 'categoryId'])),
      accountId: asIntN(pick(m, ['account_id', 'accountId'])),
      toAccountId: asIntN(pick(m, ['to_account_id', 'toAccountId'])),
      note: pick(m, ['note'])?.toString(),
      frequency: '${pick(m, ['frequency']) ?? 'monthly'}',
      interval: asInt(pick(m, ['interval']), 1),
      dayOfMonth: asIntN(pick(m, ['day_of_month', 'dayOfMonth'])),
      dayOfWeek: asIntN(pick(m, ['day_of_week', 'dayOfWeek'])),
      monthOfYear: asIntN(pick(m, ['month_of_year', 'monthOfYear'])),
      startDate: asDate(pick(m, ['start_date', 'startDate'])),
      endDate: asDateN(pick(m, ['end_date', 'endDate'])),
      lastGeneratedDate:
          asDateN(pick(m, ['last_generated_date', 'lastGeneratedDate'])),
      enabled: asBool(pick(m, ['enabled']), true),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
      updatedAt: asDate(pick(m, ['updated_at', 'updatedAt'])),
    );

Tag tagFromJson(Map<String, dynamic> m) => Tag(
      id: asInt(pick(m, ['id'])),
      name: '${pick(m, ['name']) ?? ''}',
      color: pick(m, ['color'])?.toString(),
      sortOrder: asInt(pick(m, ['sort_order', 'sortOrder'])),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
    );

Budget budgetFromJson(Map<String, dynamic> m) => Budget(
      id: asInt(pick(m, ['id'])),
      ledgerId: asInt(pick(m, ['ledger_id', 'ledgerId'])),
      year: asInt(pick(m, ['year'])),
      month: asInt(pick(m, ['month'])),
      categoryId: asIntN(pick(m, ['category_id', 'categoryId'])),
      amount: asDouble(pick(m, ['amount'])),
      enabled: asBool(pick(m, ['enabled']), true),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
      updatedAt: asDate(pick(m, ['updated_at', 'updatedAt'])),
      prompt: asBool(pick(m, ['prompt'])),
      promptDay: asIntN(pick(m, ['prompt_day', 'promptDay'])),
      ignored: m.containsKey('ignored') ? asBool(m['ignored']) : null,
    );

Receivable receivableFromJson(Map<String, dynamic> m) => Receivable(
      id: asInt(pick(m, ['id'])),
      accountId: asInt(pick(m, ['account_id', 'accountId'])),
      borrowerName: '${pick(m, ['borrower_name', 'borrowerName']) ?? ''}',
      amount: asDouble(pick(m, ['amount'])),
      borrowDate: asDate(pick(m, ['borrow_date', 'borrowDate'])),
      note: pick(m, ['note'])?.toString(),
      fromAccountId: asIntN(pick(m, ['from_account_id', 'fromAccountId'])),
      isReceived: asBool(pick(m, ['is_received', 'isReceived'])),
      receiveDate: asDateN(pick(m, ['receive_date', 'receiveDate'])),
      toAccountId: asIntN(pick(m, ['to_account_id', 'toAccountId'])),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
      updatedAt: asDate(pick(m, ['updated_at', 'updatedAt'])),
    );

Payable payableFromJson(Map<String, dynamic> m) => Payable(
      id: asInt(pick(m, ['id'])),
      accountId: asInt(pick(m, ['account_id', 'accountId'])),
      payeeName: '${pick(m, ['payee_name', 'payeeName']) ?? ''}',
      amount: asDouble(pick(m, ['amount'])),
      payDate: asDate(pick(m, ['pay_date', 'payDate'])),
      note: pick(m, ['note'])?.toString(),
      toAccountId: asIntN(pick(m, ['to_account_id', 'toAccountId'])),
      isPaid: asBool(pick(m, ['is_paid', 'isPaid'])),
      paidDate: asDateN(pick(m, ['paid_date', 'paidDate'])),
      fromAccountId: asIntN(pick(m, ['from_account_id', 'fromAccountId'])),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
      updatedAt: asDate(pick(m, ['updated_at', 'updatedAt'])),
    );

ReceivablePayment receivablePaymentFromJson(Map<String, dynamic> m) =>
    ReceivablePayment(
      id: asInt(pick(m, ['id'])),
      receivableId: asInt(pick(m, ['receivable_id', 'receivableId'])),
      amount: asDouble(pick(m, ['amount'])),
      interestAmount: asDouble(pick(m, ['interest_amount', 'interestAmount'])),
      happenedAt: asDate(pick(m, ['happened_at', 'happenedAt'])),
      accountId: asIntN(pick(m, ['account_id', 'accountId'])),
      note: pick(m, ['note'])?.toString(),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
    );

PayablePayment payablePaymentFromJson(Map<String, dynamic> m) => PayablePayment(
      id: asInt(pick(m, ['id'])),
      payableId: asInt(pick(m, ['payable_id', 'payableId'])),
      amount: asDouble(pick(m, ['amount'])),
      interestAmount: asDouble(pick(m, ['interest_amount', 'interestAmount'])),
      happenedAt: asDate(pick(m, ['happened_at', 'happenedAt'])),
      accountId: asIntN(pick(m, ['account_id', 'accountId'])),
      note: pick(m, ['note'])?.toString(),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
    );

TransactionAttachment attachmentFromJson(Map<String, dynamic> m) =>
    TransactionAttachment(
      id: asInt(pick(m, ['id'])),
      transactionId: asInt(pick(m, ['transaction_id', 'transactionId'])),
      fileName: '${pick(m, ['file_name', 'fileName']) ?? ''}',
      originalName: pick(m, ['original_name', 'originalName'])?.toString(),
      fileSize: asIntN(pick(m, ['file_size', 'fileSize'])),
      width: asIntN(pick(m, ['width'])),
      height: asIntN(pick(m, ['height'])),
      sortOrder: asInt(pick(m, ['sort_order', 'sortOrder'])),
      createdAt: asDate(pick(m, ['created_at', 'createdAt'])),
    );

class AccountUiSettings {
  const AccountUiSettings({
    this.defaultIncomeAccountId,
    this.defaultExpenseAccountId,
    this.groupByType = false,
  });

  final int? defaultIncomeAccountId;
  final int? defaultExpenseAccountId;
  final bool groupByType;

  factory AccountUiSettings.fromJson(Map<String, dynamic> json) {
    return AccountUiSettings(
      defaultIncomeAccountId: asIntN(json['default_income_account_id']),
      defaultExpenseAccountId: asIntN(json['default_expense_account_id']),
      groupByType: asBool(json['accounts_group_by_type']),
    );
  }
}
