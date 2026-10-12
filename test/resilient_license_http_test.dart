import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/network/resilient_license_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activation transport sends non-ASCII JSON request bodies as UTF-8', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedBody;

    final subscription = server.listen((request) async {
      receivedBody = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });

    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final response = await const LicenseHttpTransport().send(
      method: 'POST',
      uri: Uri.parse('http://127.0.0.1:${server.port}/v1/licenses/reserve'),
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode(<String, dynamic>{'note': '测试3'}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(receivedBody, '{"note":"测试3"}');
  });
}
