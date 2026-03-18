import 'dart:convert';
import 'dart:async';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:http/http.dart' as http;

class BeeCountAuthService implements CloudAuthService {
  final String serverUrl;
  CloudUser? _currentUser;
  final _authStateController = StreamController<CloudUser?>.broadcast();

  BeeCountAuthService(this.serverUrl);

  @override
  Stream<CloudUser?> get authStateChanges => _authStateController.stream;

  @override
  Future<CloudUser?> get currentUser async => _currentUser;

  /// Internal sync getter for the current user
  CloudUser? get currentUserSync => _currentUser;

  void restoreSession({
    required String token,
    required String userId,
    required String username,
  }) {
    _currentUser = CloudUser(
      id: userId,
      email: username,
      metadata: {'token': token},
    );
    _authStateController.add(_currentUser);
  }

  @override
  Future<CloudUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    // Note: server uses 'username' instead of 'email'
    final url = '$serverUrl/api/v1/public/login';
    final body = jsonEncode({'username': email, 'password': password});
    
    print('📡 POST $url');
    print('📤 Request body: $body');
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    
    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'];
      _currentUser = CloudUser(
        id: data['userId'].toString(),
        email: data['username'],
        metadata: {'token': token},
      );
      _authStateController.add(_currentUser);
      return _currentUser!;
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Login failed';
      throw CloudAuthException(error);
    }
  }

  @override
  Future<CloudUser> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final url = '$serverUrl/api/v1/public/register';
    final body = jsonEncode({'username': email, 'password': password});
    
    print('📡 POST $url');
    print('📤 Request body: $body');
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    
    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'];
      _currentUser = CloudUser(
        id: data['userId'].toString(),
        email: data['username'],
        metadata: {'token': token},
      );
      _authStateController.add(_currentUser);
      return _currentUser!;
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Registration failed';
      throw CloudAuthException(error);
    }
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _authStateController.add(null);
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    throw UnsupportedError('Password reset not supported on BeeCount server');
  }

  @override
  Future<void> resendEmailVerification({required String email}) async {
    throw UnsupportedError('Email verification not supported on BeeCount server');
  }

  void dispose() {
    _authStateController.close();
  }
}
