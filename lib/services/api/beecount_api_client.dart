import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/db.dart';
import 'beecount_api_exception.dart';
import 'api_json.dart';

class BeeCountApiClient {
  BeeCountApiClient({
    required this.serverUrl,
    required this.token,
    this.onAuthFailed,
    this.onNetworkError,
  });

  final String serverUrl;
  final String token;
  final void Function()? onAuthFailed;
  final void Function()? onNetworkError;

  String get _base {
    var u = serverUrl;
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$_base/api/v1$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    late http.Response res;
    final encoded = body == null ? null : jsonEncode(body);
    try {
      if (method == 'GET') {
        res = await http.get(uri, headers: _headers);
      } else if (method == 'POST') {
        res = await http.post(uri, headers: _headers, body: encoded);
      } else if (method == 'PUT') {
        res = await http.put(uri, headers: _headers, body: encoded);
      } else if (method == 'DELETE') {
        res = await http.delete(uri, headers: _headers);
      } else {
        throw BeeCountApiException('Unsupported method $method');
      }
    } on SocketException {
      onNetworkError?.call();
      rethrow;
    } on http.ClientException {
      onNetworkError?.call();
      rethrow;
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      onAuthFailed?.call();
    }
    return res;
  }

  Future<dynamic> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    int ok = 200,
    List<int> okAny = const [],
  }) async {
    final res = await _send(method, path, query: query, body: body);
    final allowed = okAny.isEmpty ? [ok] : okAny;
    if (res.statusCode == 204) return null;
    if (!allowed.contains(res.statusCode)) {
      throw BeeCountApiException(
        'HTTP ${res.statusCode} $path',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  static Map<String, String> q(Map<String, String?> raw) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v != null && v.isNotEmpty) out[k] = v;
    });
    return out;
  }

  Future<({String token, String userId, String username})> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$_base/api/v1/public/login');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw BeeCountApiException('Login failed',
          statusCode: res.statusCode, body: res.body);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      token: data['token'].toString(),
      userId: data['userId'].toString(),
      username: (data['username'] ?? username).toString(),
    );
  }

  static Future<({String token, String userId, String username})> loginAt({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return BeeCountApiClient(serverUrl: serverUrl, token: '').login(
      username: username,
      password: password,
    );
  }

  static Future<({String token, String userId, String username})> registerAt({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    var u = serverUrl;
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    final uri = Uri.parse('$u/api/v1/public/register');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw BeeCountApiException('Register failed',
          statusCode: res.statusCode, body: res.body);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      token: data['token'].toString(),
      userId: data['userId'].toString(),
      username: (data['username'] ?? username).toString(),
    );
  }

  Future<int?> getSyncVersion() async {
    final data = await _json('GET', '/sync_version');
    final v = (data as Map)['version'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  Future<int> generateRecurring() async {
    final data = await _json('POST', '/recurring_transactions/generate',
        okAny: [200, 201]);
    return ((data as Map)['generated'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> listAll(String path,
      [Map<String, String?>? query]) async {
    final data = await _json('GET', path, query: q(query ?? {}));
    return asItemMaps(data);
  }

  Future<PagedResult<Map<String, dynamic>>> listPaged(
    String path, {
    required int page,
    required int pageSize,
    Map<String, String?> extra = const {},
  }) async {
    final data = await _json(
      'GET',
      path,
      query: q({
        'page': '$page',
        'page_size': '$pageSize',
        ...extra,
      }),
    );
    return parsePagedMaps(data);
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query}) async {
    final data = await _json('GET', path, query: query);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> post(String path, Object body) async {
    final data = await _json('POST', path, body: body, okAny: [200, 201]);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> put(String path, Object body) async {
    final data = await _json('PUT', path, body: body);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> delete(String path) async {
    await _json('DELETE', path, okAny: [200, 204]);
  }

  Future<List<int>> getAttachmentBytes(int id) async {
    final res = await _send('GET', '/attachments/$id/file');
    if (res.statusCode != 200) {
      throw BeeCountApiException('Download failed',
          statusCode: res.statusCode, body: res.body);
    }
    return res.bodyBytes;
  }
}
