import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../providers/beecount_server_providers.dart';
import '../system/logger_service.dart';

class CategoryShareService {
  final Ref _ref;

  CategoryShareService(this._ref);

  Map<String, String> _getHeaders(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<String?> _getToken() async {
    final session = await _ref.read(beecountSessionProvider.future);
    return session?.token;
  }

  Future<String?> _getServerUrl() async {
    final session = await _ref.read(beecountSessionProvider.future);
    return session?.serverUrl;
  }

  Future<CategoryShareCode> createShareCode({
    required String shareType,
  }) async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    if (serverUrl == null || token == null) {
      throw Exception('Not logged in');
    }

    final url = '$serverUrl/api/v1/category_share_codes';
    final body = jsonEncode({'share_type': shareType});

    logger.info('CategoryShare', 'Creating share code: $shareType');

    final response = await http.post(
      Uri.parse(url),
      headers: _getHeaders(token),
      body: body,
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      logger.info('CategoryShare', 'Share code created: ${data['code']}');
      return CategoryShareCode.fromJson(data);
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      logger.error('CategoryShare', 'Failed to create share code: $error');
      throw Exception(error);
    }
  }

  Future<List<CategoryShareCode>> getShareCodes() async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    if (serverUrl == null || token == null) {
      throw Exception('Not logged in');
    }

    final url = '$serverUrl/api/v1/category_share_codes';

    final response = await http.get(
      Uri.parse(url),
      headers: _getHeaders(token),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => CategoryShareCode.fromJson(e)).toList();
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }
  }

  Future<void> deleteShareCode(String code) async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    if (serverUrl == null || token == null) {
      throw Exception('Not logged in');
    }

    final url = '$serverUrl/api/v1/category_share_codes/$code';

    logger.info('CategoryShare', 'Deleting share code: $code');

    final response = await http.delete(
      Uri.parse(url),
      headers: _getHeaders(token),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      logger.error('CategoryShare', 'Failed to delete share code: $error');
      throw Exception(error);
    }

    logger.info('CategoryShare', 'Share code deleted: $code');
  }

  Future<CategoryImportResult> importCategories(String code) async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    if (serverUrl == null || token == null) {
      throw Exception('Not logged in');
    }

    final url = '$serverUrl/api/v1/category_import';
    final body = jsonEncode({'code': code});

    logger.info('CategoryShare', 'Importing categories with code: $code');

    final response = await http.post(
      Uri.parse(url),
      headers: _getHeaders(token),
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      logger.info('CategoryShare', 'Import complete: imported=${data['imported']}, skipped=${data['skipped']}');
      return CategoryImportResult.fromJson(data);
    } else if (response.statusCode == 404) {
      throw Exception('Invalid or expired share code');
    } else if (response.statusCode == 410) {
      throw Exception('Share code has expired');
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      logger.error('CategoryShare', 'Failed to import categories: $error');
      throw Exception(error);
    }
  }
}

class CategoryShareCode {
  final int? id;
  final String code;
  final String shareType;
  final DateTime createdAt;
  final DateTime? expiresAt;

  CategoryShareCode({
    this.id,
    required this.code,
    required this.shareType,
    required this.createdAt,
    this.expiresAt,
  });

  factory CategoryShareCode.fromJson(Map<String, dynamic> json) {
    return CategoryShareCode(
      id: json['id'] != null ? json['id'] as int : null,
      code: json['code'] as String,
      shareType: json['share_type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }
}

class CategoryImportResult {
  final int imported;
  final int skipped;

  CategoryImportResult({
    required this.imported,
    required this.skipped,
  });

  factory CategoryImportResult.fromJson(Map<String, dynamic> json) {
    return CategoryImportResult(
      imported: json['imported'] as int,
      skipped: json['skipped'] as int,
    );
  }
}

final categoryShareServiceProvider = Provider<CategoryShareService>((ref) {
  return CategoryShareService(ref);
});
