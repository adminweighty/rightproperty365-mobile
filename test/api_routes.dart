import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rightproperty365/core/api/api_client.dart';

import 'support.dart';

/// An answer for one route: a JSON-able value (sent with 200) or a ready
/// [http.Response].
typedef RouteAnswer = Object Function(http.Request request);

/// An [ApiClient] that answers `'METHOD /path'` from [routes] and 404 for
/// anything else, recording every request. For repository tests of the new
/// features against the documented contract.
({ApiClient api, List<http.Request> requests}) routedApi(
  Map<String, RouteAnswer> routes,
) => mockApi((request) async {
  final answer = routes['${request.method} ${request.url.path}'];
  if (answer == null) {
    return jsonResponse(404, {
      'error': {'code': 'NOT_FOUND', 'message': 'Not found'},
    });
  }
  final value = answer(request);
  return value is http.Response ? value : jsonResponse(200, value);
});

/// The API's error envelope.
http.Response apiError(
  int status,
  String code, {
  Map<String, String>? fields,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': 'API says $code', 'fields': ?fields},
    'trace_id': 'trace-1',
  }),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

/// The JSON body a request carried.
Map<String, dynamic> jsonBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;
