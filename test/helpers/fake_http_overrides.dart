import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Routing fake `dart:io` HTTP stack for unit tests.
///
/// Install via [HttpOverrides.global] and swap [FakeHttpOverrides.responder]
/// per test to control status codes, bodies, chunking, and failures:
/// ```dart
/// final overrides = FakeHttpOverrides(
///   responder: (uri, headers) => githubReleaseResponse(200, tagName: 'v9.9.9'),
/// );
/// HttpOverrides.global = overrides;
/// ...
/// HttpOverrides.global = null;
/// ```
class FakeHttpOverrides extends HttpOverrides {
  FakeHttpOverrides({FakeHttpResponder? responder})
      : responder =
            responder ??
            ((uri, headers) => const FakeHttpResponse(404, <int>[]));

  /// Invoked for every request; may throw (e.g. [SocketException]).
  FakeHttpResponder responder;

  /// Number of requests seen so far.
  int requestCount = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient(
    (uri, headers) {
      requestCount++;
      return responder(uri, headers);
    },
  );
}

typedef FakeHttpResponder =
    FakeHttpResponse Function(Uri uri, FakeHttpHeaders headers);

/// Plain-data description of a fake HTTP response.
class FakeHttpResponse {
  const FakeHttpResponse(this.statusCode, this.bodyBytes, {this.chunkSize});

  final int statusCode;
  final List<int> bodyBytes;

  /// When set, the body is streamed in chunks of this many bytes so tests
  /// can exercise multi-chunk download progress.
  final int? chunkSize;
}

/// Builds a GitHub "latest release" API JSON response for update tests.
FakeHttpResponse githubReleaseResponse(int status, {String tagName = ''}) {
  final body = jsonEncode(<String, Object?>{
    'tag_name': tagName,
    'html_url': 'https://example.test/release/$tagName',
    'body': 'notes',
    'assets': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'yoloit-macos-arm64-${tagName.replaceFirst('v', '')}.dmg',
        'browser_download_url': 'https://example.test/download.dmg',
      },
    ],
  });
  return FakeHttpResponse(status, utf8.encode(body));
}

/// Captures request headers set via [HttpHeaders.set].
class FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = <String>[value.toString()];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.respond);

  final FakeHttpResponder respond;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(url, respond);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, this.respond);

  @override
  final Uri uri;
  final FakeHttpResponder respond;

  @override
  final FakeHttpHeaders headers = FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(
    respond(uri, headers),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.data);

  final FakeHttpResponse data;

  @override
  int get statusCode => data.statusCode;

  @override
  int get contentLength => data.bodyBytes.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final body = data.bodyBytes;
    final chunkSize = data.chunkSize;
    final chunks = <List<int>>[
      if (chunkSize == null || chunkSize <= 0 || body.isEmpty)
        body
      else
        for (var i = 0; i < body.length; i += chunkSize)
          body.sublist(
            i,
            i + chunkSize > body.length ? body.length : i + chunkSize,
          ),
    ];
    return Stream<List<int>>.fromIterable(chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
