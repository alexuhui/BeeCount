import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'beecount_auth_service.dart';
import 'beecount_database_service.dart';

class BeeCountProvider implements CloudProvider {
  BeeCountAuthService? _authService;
  BeeCountDatabaseService? _databaseService;
  String? _serverUrl;

  @override
  String get providerId => 'beecount';

  @override
  String get providerName => 'BeeCount Server';

  @override
  CloudAuthService get auth {
    if (_authService == null) {
      throw CloudConfigurationException('Provider not initialized.');
    }
    return _authService!;
  }

  @override
  CloudStorageService get storage => NoopStorageService();

  /// Database service for direct database operations
  @override
  CloudDatabaseService? get databaseService => _databaseService;

  @override
  CloudRealtimeService? get realtimeService => null;

  @override
  String? get currentUserId => _authService?.currentUserSync?.id;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    if (!validateConfig(config)) {
      throw CloudConfigurationException('Invalid configuration. Required key: serverUrl');
    }

    _serverUrl = config['serverUrl'] as String;
    // Remove trailing slash if exists
    if (_serverUrl!.endsWith('/')) {
      _serverUrl = _serverUrl!.substring(0, _serverUrl!.length - 1);
    }

    _authService = BeeCountAuthService(_serverUrl!);
    _databaseService = BeeCountDatabaseService(_serverUrl!, _authService!);
  }

  @override
  bool validateConfig(Map<String, dynamic> config) {
    return config.containsKey('serverUrl') && config['serverUrl'] is String;
  }

  @override
  Future<void> dispose() async {
    _authService = null;
    _databaseService = null;
    _serverUrl = null;
  }
}
