import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _baseUrl = 'http://172.25.26.17:8080';
  static String? _token;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 1);

  static Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
  }

  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    _token = token;
  }

  static Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _token = null;
  }

  static Future<http.Response> _requestWithRetry(Future<http.Response> Function() request) async {
    int retries = 0;
    while (retries < _maxRetries) {
      try {
        final response = await request();
        return response;
      } catch (e) {
        retries++;
        if (retries >= _maxRetries) {
          rethrow;
        }
        await Future.delayed(_retryDelay * retries);
      }
    }
    throw Exception('请求失败，请检查网络连接');
  }

  static Future<Map<String, dynamic>> register(String email, String password, String name) async {
    final response = await _requestWithRetry(() => http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': name,
      }),
    ));

    if (response.statusCode != 201) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _requestWithRetry(() => http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    ));

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }

    final result = jsonDecode(response.body);
    await _saveToken(result['token']);
    return result;
  }

  static Future<void> logout() async {
    await _clearToken();
  }

  static Future<bool> isAuthenticated() async {
    await _loadToken();
    return _token != null;
  }

  static Future<http.Response> _get(String endpoint) async {
    await _loadToken();
    return _requestWithRetry(() => http.get(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    ));
  }

  static Future<http.Response> _post(String endpoint, dynamic data) async {
    await _loadToken();
    return _requestWithRetry(() => http.post(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode(data),
    ));
  }

  static Future<http.Response> _put(String endpoint, dynamic data) async {
    await _loadToken();
    return _requestWithRetry(() => http.put(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode(data),
    ));
  }

  static Future<http.Response> _delete(String endpoint) async {
    await _loadToken();
    return _requestWithRetry(() => http.delete(
      Uri.parse('$_baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    ));
  }

  // 账本相关 API
  static Future<Map<String, dynamic>> getLedgers() async {
    final response = await _get('/ledgers');
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createLedger(String name, String currency, String type) async {
    final response = await _post('/ledgers', {
      'name': name,
      'currency': currency,
      'type': type,
    });
    if (response.statusCode != 201) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  // 分类相关 API
  static Future<Map<String, dynamic>> getCategories({String? kind}) async {
    final query = kind != null ? '?kind=$kind' : '';
    final response = await _get('/categories$query');
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createCategory(Map<String, dynamic> data) async {
    final response = await _post('/categories', data);
    if (response.statusCode != 201) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  // 交易相关 API
  static Future<Map<String, dynamic>> getTransactions({int? ledgerId, String? startDate, String? endDate}) async {
    final query = [];
    if (ledgerId != null) query.add('ledger_id=$ledgerId');
    if (startDate != null) query.add('start_date=$startDate');
    if (endDate != null) query.add('end_date=$endDate');
    final queryString = query.isNotEmpty ? '?${query.join('&')}' : '';
    final response = await _get('/transactions$queryString');
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createTransaction(Map<String, dynamic> data) async {
    final response = await _post('/transactions', data);
    if (response.statusCode != 201) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  // 账户相关 API
  static Future<Map<String, dynamic>> getAccounts() async {
    final response = await _get('/accounts');
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createAccount(Map<String, dynamic> data) async {
    final response = await _post('/accounts', data);
    if (response.statusCode != 201) {
      final error = jsonDecode(response.body)['error'];
      throw Exception(error);
    }
    return jsonDecode(response.body);
  }
}
