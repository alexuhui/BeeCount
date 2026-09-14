import 'package:intl/intl.dart';

String buildBeeCountExportFileName({
  required DateTime at,
  String? username,
}) {
  final ts = DateFormat('yyyyMMdd_HHmmss').format(at);
  final safe = _sanitizeExportUsername(username);
  if (safe.isEmpty) return 'beecount_export_$ts.xlsx';
  return 'beecount_export_${safe}_$ts.xlsx';
}

String _sanitizeExportUsername(String? username) {
  if (username == null) return '';
  final cleaned =
      username.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
}
