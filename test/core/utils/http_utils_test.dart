import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/http_utils.dart';

class _FakeHttpResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeHttpResponse(this._statusCode, this._body);

  final int _statusCode;
  final String _body;

  @override
  int get statusCode => _statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.fromIterable([utf8.encode(_body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // Stub implementations for HttpClientResponse interface
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._response);

  final HttpClientResponse _response;
  final headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _values[name];

  @override
  String? value(String name) => _values[name]?.firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._response);

  final HttpClientResponse _response;
  bool closed = false;
  _FakeHttpClientRequest? lastRequest;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    lastRequest = _FakeHttpClientRequest(_response);
    return lastRequest!;
  }

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('fetchJson', () {
    test('returns parsed JSON on 200', () async {
      final client = _FakeHttpClient(
        _FakeHttpResponse(200, jsonEncode({'ok': true})),
      );
      final result = await fetchJson(
        url: 'http://example.com/test',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      expect(result, {'ok': true});
      expect(client.closed, isFalse); // provided client is not closed
    });

    test('returns null on 404', () async {
      final client = _FakeHttpClient(_FakeHttpResponse(404, ''));
      final result = await fetchJson(
        url: 'http://example.com/missing',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      expect(result, isNull);
    });

    test('sends custom user-agent', () async {
      final response = _FakeHttpResponse(200, '{}');
      final client = _FakeHttpClient(response);
      await fetchJson(
        url: 'http://example.com/ua',
        timeout: const Duration(seconds: 5),
        userAgent: 'TestAgent/1.0',
        client: client,
      );

      expect(
        client.lastRequest?.headers.value(HttpHeaders.userAgentHeader),
        'TestAgent/1.0',
      );
    });

    test('sends extra headers', () async {
      final response = _FakeHttpResponse(200, '{}');
      final client = _FakeHttpClient(response);
      await fetchJson(
        url: 'http://example.com/headers',
        timeout: const Duration(seconds: 5),
        headers: {HttpHeaders.authorizationHeader: 'Bearer token'},
        client: client,
      );

      expect(
        client.lastRequest?.headers.value(HttpHeaders.authorizationHeader),
        'Bearer token',
      );
    });

    test('returns null on parse error', () async {
      final client = _FakeHttpClient(_FakeHttpResponse(200, 'not json'));
      final result = await fetchJson(
        url: 'http://example.com/bad',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      expect(result, isNull);
    });
  });
}
