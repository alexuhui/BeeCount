import 'package:beecount/utils/export_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 9, 14, 21, 24, 6);

  test('includes sanitized username before timestamp', () {
    expect(
      buildBeeCountExportFileName(at: at, username: 'cyh666'),
      'beecount_export_cyh666_20260914_212406.xlsx',
    );
  });

  test('omits username when not logged in', () {
    expect(
      buildBeeCountExportFileName(at: at, username: null),
      'beecount_export_20260914_212406.xlsx',
    );
  });

  test('strips characters that are illegal in file names', () {
    expect(
      buildBeeCountExportFileName(at: at, username: ' cyh/666:* '),
      'beecount_export_cyh_666_20260914_212406.xlsx',
    );
  });
}
