import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class McpTestClient {
  McpTestClient(this.port);
  final int port;
  final http = HttpClient();
  int id = 0;
  String? session;
  Future<Map> call(String method, [Map<String, Object?>? params]) async {
    final r = await http.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    r.headers
      ..set('Authorization', 'Bearer test')
      ..set('Accept', 'application/json, text/event-stream')
      ..contentType = ContentType.json;
    if (session != null) r.headers.set('Mcp-Session-Id', session!);
    r.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': ++id,
        'method': method,
        'params': ?params,
      }),
    );
    final response = await r.close();
    session ??= response.headers.value('mcp-session-id');
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: body);
    final decoded = jsonDecode(body) as Map;
    expect(decoded['error'], isNull, reason: body);
    return decoded['result'] as Map;
  }

  Future<void> initialize() async {
    await call('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'contract-test', 'version': '1'},
    });
    await notification('notifications/initialized');
  }

  Future<void> notification(String method, [Map<String, Object?>? params]) async {
    final r = await http.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    r.headers
      ..set('Authorization', 'Bearer test')
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Mcp-Session-Id', session!)
      ..contentType = ContentType.json;
    r.write(jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': ?params}));
    await (await r.close()).drain<void>();
  }

  Future<String> tool(String name, Map<String, Object?> args) async {
    final r = await call('tools/call', {'name': name, 'arguments': args});
    return (r['content'] as List).map((e) => (e as Map)['text']).join('\n');
  }

  Future<String> waitStatus(
    String toolName,
    String number,
    bool Function(String) ready,
  ) async {
    var result = '';
    for (var i = 0; i < 100; i++) {
      result = await tool(toolName, {'id': number});
      if (ready(result)) return result;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Status wurde nicht erreicht: $result');
  }
}
