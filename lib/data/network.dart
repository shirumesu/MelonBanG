import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'json.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.host);
  final int status;
  final String host;
  @override
  String toString() => '$host 请求失败（HTTP $status）';
}

class ApiClient {
  ApiClient({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<http.Response> send(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': 'Melonbang/1.0 (Flutter; ${Platform.operatingSystem})',
      ...headers,
    });
    if (body is Map<String, String>) {
      request.bodyFields = body;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 20)),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, uri.host);
    }
    return response;
  }

  Future<dynamic> json(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final response = await send(
      uri,
      method: method,
      body: body,
      headers: headers,
    );
    return response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<Json> map(
    Uri uri, {
    String method = 'GET',
    Object? body,
    Map<String, String> headers = const {},
  }) async =>
      object(await json(uri, method: method, body: body, headers: headers));
  void close() => client.close();
}
