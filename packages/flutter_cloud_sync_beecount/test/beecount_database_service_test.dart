import 'dart:convert';
import 'dart:io';

import 'package:flutter_cloud_sync_beecount/src/beecount_auth_service.dart';
import 'package:flutter_cloud_sync_beecount/src/beecount_database_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('insert sends an Idempotency-Key header', () async {
    late HttpHeaders requestHeaders;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      requestHeaders = request.headers;
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'id': 1}));
      await request.response.close();
    });

    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });

    final serverUrl = 'http://${server.address.host}:${server.port}';
    final auth = BeeCountAuthService(serverUrl)
      ..restoreSession(token: 'token', userId: '1', username: 'tester');
    final service = BeeCountDatabaseService(serverUrl, auth);

    await service.insert(table: 'ledgers', data: {'name': 'Main'});

    expect(requestHeaders.value('idempotency-key'), isNotEmpty);
    expect(requestHeaders.value('authorization'), 'Bearer token');
  });
}
