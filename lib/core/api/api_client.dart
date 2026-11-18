import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

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

class ApiResponse {
  const ApiResponse(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

/// Thin JSON wrapper over `package:http`. Throws [ApiFailure] for anything
/// that is not a 2xx response.
class ApiClient {
  ApiClient({required String baseUrl, http.Client? httpClient})
    : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  /// The signed-in session token, sent as `Authorization: Bearer`. Set by the
  /// auth controller; null when signed out.
  String? bearerToken;

  static const _timeout = Duration(seconds: 20);
  static const _fallbackMessage =
      'Something went wrong on our side. Please try again.';

  Future<ApiResponse> get(String path) => _send('GET', path);

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
      throw const ApiFailure.network();
    } on TimeoutException {
      throw const ApiFailure.network();
    } on http.ClientException {
      throw const ApiFailure.network();
    }

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
      message: details['message'] as String? ?? _fallbackMessage,
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

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }
}
