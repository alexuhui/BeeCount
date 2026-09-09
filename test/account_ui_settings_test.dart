import 'package:beecount/services/api/api_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses account settings json', () {
    final settings = AccountUiSettings.fromJson({
      'default_income_account_id': 3,
      'default_expense_account_id': 8,
      'accounts_group_by_type': true,
    });
    expect(settings.defaultIncomeAccountId, 3);
    expect(settings.defaultExpenseAccountId, 8);
    expect(settings.groupByType, isTrue);
  });

  test('parses empty account settings json', () {
    final settings = AccountUiSettings.fromJson({
      'default_income_account_id': null,
      'default_expense_account_id': null,
      'accounts_group_by_type': false,
    });
    expect(settings.defaultIncomeAccountId, isNull);
    expect(settings.defaultExpenseAccountId, isNull);
    expect(settings.groupByType, isFalse);
  });
}
