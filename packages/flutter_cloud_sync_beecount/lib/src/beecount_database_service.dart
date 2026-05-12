import 'dart:convert';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:http/http.dart' as http;
import 'beecount_auth_service.dart';

class BeeCountDatabaseService implements CloudDatabaseService {
  final String serverUrl;
  final BeeCountAuthService auth;
  int _mutationCounter = 0;

  BeeCountDatabaseService(this.serverUrl, this.auth);

  Map<String, String> get _headers {
    final token = auth.currentUserSync?.metadata?['token'];
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _headersWithMutation(String table) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final counter = _mutationCounter++;
    return {
      ..._headers,
      'Idempotency-Key': '$table-$now-$counter',
    };
  }

  @override
  Future<Map<String, dynamic>> insert({
    required String table,
    required Map<String, dynamic> data,
    bool autoInjectUserId = true,
  }) async {
    final url = '$serverUrl/api/v1/$table';
    final body = jsonEncode(data);

    print('📡 POST $url  📤 Request body: $body');

    final response = await http.post(
      Uri.parse(url),
      headers: _headersWithMutation(table),
      body: body,
    );

    print(
        '📥 Response status: ${response.statusCode}  📥 Response body: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw CloudDatabaseException(
        'Failed to insert into $table: ${response.body}',
        response.body,
        response.statusCode,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> update({
    required String table,
    required String id,
    required Map<String, dynamic> data,
    bool autoFilterByUser = true,
  }) async {
    final url = '$serverUrl/api/v1/$table/$id';
    final body = jsonEncode(data);

    print('📡 PUT $url  📤 Request body: $body');

    final response = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: body,
    );

    print(
        '📥 Response status: ${response.statusCode}  📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw CloudDatabaseException(
        'Failed to update $table: ${response.body}',
        response.body,
        response.statusCode,
      );
    }
  }

  @override
  Future<void> delete({
    required String table,
    required String id,
    bool autoFilterByUser = true,
  }) async {
    final url = '$serverUrl/api/v1/$table/$id';

    print('📡 DELETE $url');

    final response = await http.delete(
      Uri.parse(url),
      headers: _headers,
    );

    print(
        '📥 Response status: ${response.statusCode}  📥 Response body: ${response.body}');

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw CloudDatabaseException(
        'Failed to delete from $table: ${response.body}',
        response.body,
        response.statusCode,
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query({
    required String table,
    List<QueryFilter>? filters,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool autoFilterByUser = true,
  }) async {
    final url = '$serverUrl/api/v1/$table';

    print(
        '📡 GET $url  📤 Filters: ${filters?.map((f) => '${f.column} ${f.operator} ${f.value}').join(', ')}');

    final response = await http.get(
      Uri.parse(url),
      headers: _headers,
    );

    print(
        '📥 Response status: ${response.statusCode}  📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      var results = data.cast<Map<String, dynamic>>();

      // Manual filtering (fallback if server doesn't support it)
      if (filters != null) {
        for (final filter in filters) {
          results = results.where((item) {
            final val = item[filter.column];
            switch (filter.operator) {
              case 'eq':
                return val == filter.value;
              case 'neq':
                return val != filter.value;
              case 'gt':
                return (val as num) > (filter.value as num);
              case 'gte':
                return (val as num) >= (filter.value as num);
              case 'lt':
                return (val as num) < (filter.value as num);
              case 'lte':
                return (val as num) <= (filter.value as num);
              case 'like':
                return val.toString().contains(filter.value.toString());
              case 'in':
                return (filter.value as List).contains(val);
              default:
                return true;
            }
          }).toList();
        }
      }

      // Manual sorting
      if (orderBy != null) {
        results.sort((a, b) {
          final valA = a[orderBy];
          final valB = b[orderBy];
          if (valA == null || valB == null) return 0;
          final cmp = (valA is Comparable) ? valA.compareTo(valB) : 0;
          return descending ? -cmp : cmp;
        });
      }

      // Manual pagination
      if (offset != null) {
        results = results.skip(offset).toList();
      }
      if (limit != null) {
        results = results.take(limit).toList();
      }

      return results;
    } else {
      throw CloudDatabaseException(
        'Failed to query $table: ${response.body}',
        response.body,
        response.statusCode,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> getById({
    required String table,
    required String id,
  }) async {
    final results = await query(
      table: table,
      filters: [QueryFilter.eq('id', id)],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Stream<DatabaseEvent> subscribe({
    required String table,
    List<QueryFilter>? filters,
    String event = '*',
  }) {
    // BeeCount server currently doesn't support realtime
    return const Stream.empty();
  }

  @override
  Future<List<Map<String, dynamic>>> batchInsert({
    required String table,
    required List<Map<String, dynamic>> data,
  }) async {
    final results = <Map<String, dynamic>>[];
    for (final item in data) {
      results.add(await insert(table: table, data: item));
    }
    return results;
  }

  @override
  Future<void> batchUpdate({
    required String table,
    required List<Map<String, dynamic>> data,
    String idField = 'id',
  }) async {
    for (final item in data) {
      final id = item[idField].toString();
      await update(table: table, id: id, data: item);
    }
  }

  @override
  Future<void> batchDelete({
    required String table,
    required List<QueryFilter> filters,
  }) async {
    final records = await query(table: table, filters: filters);
    for (final record in records) {
      final id = record['id'].toString();
      await delete(table: table, id: id);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String query) async {
    throw UnsupportedError('rawQuery not supported on BeeCount server');
  }

  Future<int> count({
    required String table,
    List<QueryFilter>? filters,
  }) async {
    final results = await query(table: table, filters: filters);
    return results.length;
  }

  Future<int?> getSyncVersion() async {
    final url = '$serverUrl/api/v1/sync_version';

    print('📡 GET $url (sync version)');

    final response = await http.get(
      Uri.parse(url),
      headers: _headers,
    );

    print(
        '📥 Response status: ${response.statusCode}  📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['version'] as int?;
    }

    print('⚠️ Failed to get sync version: ${response.body}');
    // 与 insert/update/delete 一致：携带 HTTP 状态码，便于上层识别 401/403 并提示重新登录
    throw CloudDatabaseException(
      'Failed to get sync version: ${response.body}',
      response.body,
      response.statusCode,
    );
  }
}
