import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'offline.dart';
import 'scan.dart';

/// A failed API call, built from the error envelope
/// `{"error": {"code", "message", "fields"}, "trace_id"}` or from a transport
/// failure (status 0).
class ApiFailure implements Exception {
  const ApiFailure({
    required this.status,
    required this.code,
    required this.message,
    this.fields = const {},
    this.traceId,
    this.retryAfter,
    this.details = const {},
  });

  const ApiFailure.network()
    : this(
        status: 0,
        code: 'NETWORK_ERROR',
        message: 'We could not reach RightProperty365. Check your connection and try again.',
      );

  /// A change that could not leave the phone: nothing was sent.
  const ApiFailure.notSent()
    : this(
        status: 0,
        code: 'NETWORK_ERROR',
        message:
            'You are offline or RightProperty365 cannot be reached. Nothing '
            'was sent: try again when you are connected.',
      );

  /// A change sent with no answer in time: it may or may not have arrived.
  const ApiFailure.noAnswer()
    : this(
        status: 0,
        code: 'NETWORK_TIMEOUT',
        message:
            'We did not hear back in time. Check whether it went through '
            'before trying again.',
      );

  final int status;
  final String code;
  final String message;

  /// API field path (for example `guest_contact.phone`) to its problem.
  final Map<String, String> fields;
  final String? traceId;

  /// From a `Retry-After` header: how long to wait before trying again.
  final Duration? retryAfter;

  /// `error.details`, when the API sends more about a failure (for example
  /// the duplicates of a contact).
  final Map<String, dynamic> details;

  bool get isNetwork => status == 0;

  /// The same failure with wording chosen by the caller.
  ApiFailure withMessage(String message) => ApiFailure(
    status: status,
    code: code,
    message: message,
    fields: fields,
    traceId: traceId,
    retryAfter: retryAfter,
    details: details,
  );

  @override
  String toString() => 'ApiFailure($status, $code)';
}

/// API 0.57.0: the item belongs to another branch of the organisation.
const branchForbiddenCode = 'BRANCH_FORBIDDEN';
const branchForbiddenMessage =
    'This belongs to another branch of your organisation, so you cannot open '
    'it. Ask an owner or manager if you need it.';

class ApiResponse {
  const ApiResponse(this.status, this.body, {this.savedAt});
  final int status;
  final Map<String, dynamic> body;

  /// Set when the answer is this phone's copy, shown offline.
  final DateTime? savedAt;
}

/// Thin JSON wrapper over `package:http`. Throws [ApiFailure] for anything
/// that is not a 2xx response.
class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? httpClient,
    this.cache,
    this.connectivity,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  /// The last answers to [keptOffline] requests, shown when offline.
  ResponseCache? cache;

  /// Told whether each request got through.
  Connectivity? connectivity;

  final String _baseUrl;
  final http.Client _http;

  /// The signed-in session token, sent as `Authorization: Bearer`. Set by the
  /// auth controller; null when signed out.
  String? bearerToken;

  /// Sent as `User-Agent`, so the account's list of signed-in devices
  /// names this app (API 0.50.0), for example
  /// "RightProperty365/1.0.0 (Android)".
  String? userAgent;

  Map<String, String> get _agentHeader =>
      userAgent == null ? const {} : {'User-Agent': userAgent!};

  /// The phone's languages for `Accept-Language` (API 0.43.0); the API
  /// answers in English when it has nothing better.
  String Function()? acceptLanguage;

  Map<String, String> get _languageHeader {
    final value = acceptLanguage?.call();
    return value == null || value.isEmpty
        ? const {}
        : {'Accept-Language': value};
  }

  static const _timeout = Duration(seconds: 20);

  /// Plain wording for codes the app words the same everywhere.
  static const _messages = {branchForbiddenCode: branchForbiddenMessage};
  static const _fallbackMessage =
      'Something went wrong on our side. Please try again.';

  /// A GET. Offline, a [keptOffline] path answers with this phone's last
  /// copy (with [ApiResponse.savedAt]) instead of failing.
  Future<ApiResponse> get(String path) async {
    final keep = cache != null && keptOffline(path);
    try {
      final response = await _exchange('GET', path);
      if (keep) unawaited(cache!.write(path, response.body));
      return ApiResponse(response.statusCode, _decode(response.body));
    } on ApiFailure catch (failure) {
      final copy = keep && failure.isNetwork ? cache!.read(path) : null;
      if (copy == null) rethrow;
      connectivity?.servedFromCopy(copy.savedAt);
      return ApiResponse(200, _decode(copy.body), savedAt: copy.savedAt);
    }
  }

  /// Whether the API answers at all (for "try again" while offline).
  Future<bool> ping() async {
    try {
      await _exchange('GET', '/healthz', accept: '*/*');
      return true;
    } on ApiFailure catch (failure) {
      return !failure.isNetwork;
    }
  }

  Future<ApiResponse> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) => _send('POST', path, body: body, headers: headers);

  /// A POST without a body, for actions such as accepting an invitation.
  Future<ApiResponse> post(
    String path, {
    Map<String, String> headers = const {},
  }) => _send('POST', path, headers: headers);

  Future<ApiResponse> patchJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) => _send('PATCH', path, body: body, headers: headers);

  Future<ApiResponse> putJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) => _send('PUT', path, body: body, headers: headers);

  Future<ApiResponse> delete(
    String path, {
    Map<String, String> headers = const {},
  }) => _send('DELETE', path, headers: headers);

  /// A DELETE with a JSON body, such as the password that confirms deleting
  /// an account.
  Future<ApiResponse> deleteJson(String path, Map<String, dynamic> body) =>
      _send('DELETE', path, body: body);

  /// Uploads one file as `multipart/form-data` (part [field]).
  Future<ApiResponse> postFile(
    String path, {
    required String field,
    required List<int> bytes,
    required String fileName,
    String? contentType,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        ..._agentHeader,
        ..._languageHeader,
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: fileName,
          contentType: contentType == null
              ? null
              : MediaType.parse(contentType),
        ),
      );
    final response = await _complete(request, uploadTimeout);
    return ApiResponse(response.statusCode, _decode(response.body));
  }

  static const uploadTimeout = Duration(seconds: 90);

  /// A file, such as a PDF, as bytes. Failures are read from the JSON error
  /// envelope like any other call.
  Future<Uint8List> getBytes(String path) async =>
      (await _exchange('GET', path, accept: '*/*')).bodyBytes;

  /// A JSON POST whose answer is a file, such as a generated image.
  Future<Uint8List> postJsonForBytes(
    String path,
    Map<String, dynamic> body,
  ) async =>
      (await _exchange('POST', path, body: body, accept: '*/*')).bodyBytes;

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    final response = await _exchange(
      method,
      path,
      body: body,
      headers: headers,
    );
    return ApiResponse(response.statusCode, _decode(response.body));
  }

  /// Sends the request; returns a 2xx response or throws [ApiFailure].
  Future<http.Response> _exchange(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    String accept = 'application/json',
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Accept': accept,
        ..._agentHeader,
        ..._languageHeader,
        if (body != null) 'Content-Type': 'application/json',
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
        ...headers,
      });
    if (body != null) request.body = jsonEncode(body);

    return _complete(request, _timeout);
  }

  Future<http.Response> _complete(
    http.BaseRequest request,
    Duration timeout,
  ) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on SocketException {
      throw _unreachable(request, timedOut: false);
    } on TimeoutException {
      throw _unreachable(request, timedOut: true);
    } on http.ClientException {
      throw _unreachable(request, timedOut: false);
    }
    connectivity?.reachable();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final decoded = _decode(response.body);

    final error = decoded['error'];
    final details = error is Map<String, dynamic>
        ? error
        : const <String, dynamic>{};
    final fields = details['fields'];
    throw ApiFailure(
      status: response.statusCode,
      code: details['code'] as String? ?? 'HTTP_${response.statusCode}',
      // An upload's scan failure in the app's own plain words (a 409 on a
      // download keeps the API's).
      message:
          (response.statusCode == 409
              ? null
              : scanFailureMessages[details['code']]) ??
          _messages[details['code']] ??
          details['message'] as String? ??
          _fallbackMessage,
      fields: fields is Map
          ? fields.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      traceId: decoded['trace_id'] as String?,
      details: switch (details['details']) {
        final Map<String, dynamic> d => d,
        _ => const {},
      },
      retryAfter: switch (int.tryParse(response.headers['retry-after'] ?? '')) {
        final seconds? when seconds >= 0 => Duration(seconds: seconds),
        _ => null,
      },
    );
  }

  ApiFailure _unreachable(http.BaseRequest request, {required bool timedOut}) {
    connectivity?.unreachable();
    if (request.method == 'GET') return const ApiFailure.network();
    return timedOut ? const ApiFailure.noAnswer() : const ApiFailure.notSent();
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }
}
