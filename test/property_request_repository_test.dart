import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';

const receiptJson = {
  'request_id': '0195c0de-1111-7000-8000-000000000001',
  'reference': 'RP-8VXWDQJG',
  'status': 'RECEIVED',
  'created_at': '2026-11-13T09:00:00Z',
};

PropertyRequestDraft draft({String message = 'Hello'}) => PropertyRequestDraft(
  listingId: '0195c0de-0000-7000-8000-000000000001',
  requestType: RequestType.enquiry,
  message: message,
  contactMethod: ContactMethod.email,
  name: 'Test Customer',
  email: 'test@example.com',
  consentAccepted: true,
  privacyVersion: 'v1',
);

/// A repository whose HTTP calls are answered by [handler]; every request is
/// recorded in [requests].
({ApiPropertyRequestRepository repository, List<http.Request> requests}) build(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  var keys = 0;
  final client = MockClient((request) {
    requests.add(request);
    return handler(request);
  });
  return (
    repository: ApiPropertyRequestRepository(
      ApiClient(baseUrl: 'http://api.test/', httpClient: client),
      newKey: () => 'key-${++keys}-padding',
    ),
    requests: requests,
  );
}

http.Response json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    '201 returns the receipt and posts to the API with the idempotency key',
    () async {
      final (:repository, :requests) = build(
        (_) async => json(201, receiptJson),
      );

      final receipt = await repository.submit(draft());

      expect(receipt.reference, 'RP-8VXWDQJG');
      expect(receipt.status, 'RECEIVED');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://api.test/v1/property-requests');
      expect(request.headers['Idempotency-Key'], 'key-1-padding');
      expect(jsonDecode(request.body)['idempotency_key'], 'key-1-padding');
    },
  );

  test('200 replay is treated as the same receipt', () async {
    final (:repository, requests: _) = build(
      (_) async => json(200, receiptJson),
    );
    expect(
      (await repository.submit(draft())).requestId,
      receiptJson['request_id'],
    );
  });

  test('400 surfaces field errors and the trace id', () async {
    final (:repository, requests: _) = build(
      (_) async => json(400, {
        'error': {
          'code': 'VALIDATION_FAILED',
          'message': 'The request is invalid.',
          'fields': {
            'guest_contact.phone': 'is required when the preferred contact method is PHONE or WHATSAPP',
          },
        },
        'trace_id': 'trace-1',
      }),
    );

    await expectLater(
      repository.submit(draft()),
      throwsA(
        isA<ApiFailure>()
            .having((f) => f.status, 'status', 400)
            .having((f) => f.code, 'code', 'VALIDATION_FAILED')
            .having((f) => f.fields.keys, 'fields', ['guest_contact.phone'])
            .having((f) => f.traceId, 'traceId', 'trace-1'),
      ),
    );
  });

  test('410 explains that the listing is no longer available', () async {
    final (:repository, requests: _) = build(
      (_) async => json(410, {
        'error': {
          'code': 'LISTING_UNAVAILABLE',
          'message': 'listing is not published',
        },
        'trace_id': 'trace-2',
      }),
    );

    await expectLater(
      repository.submit(draft()),
      throwsA(
        isA<ApiFailure>()
            .having((f) => f.status, 'status', 410)
            .having(
              (f) => f.message,
              'message',
              'This listing is no longer available for enquiries.',
            )
            .having((f) => f.traceId, 'traceId', 'trace-2'),
      ),
    );
  });

  test('a network failure is reported as such', () async {
    final (:repository, requests: _) = build(
      (_) async => throw http.ClientException('offline'),
    );

    await expectLater(
      repository.submit(draft()),
      throwsA(
        isA<ApiFailure>().having((f) => f.isNetwork, 'isNetwork', isTrue),
      ),
    );
  });

  test(
    'a retry of unchanged content reuses the key; an edit gets a new one',
    () async {
      var fail = true;
      final (:repository, :requests) = build((_) async {
        if (fail) throw http.ClientException('offline');
        return json(201, receiptJson);
      });

      await expectLater(repository.submit(draft()), throwsA(isA<ApiFailure>()));
      await expectLater(repository.submit(draft()), throwsA(isA<ApiFailure>()));
      await expectLater(
        repository.submit(draft(message: 'Edited')),
        throwsA(isA<ApiFailure>()),
      );
      fail = false;
      await repository.submit(draft(message: 'Edited'));
      await repository.submit(draft(message: 'Edited'));

      expect(requests.map((r) => r.headers['Idempotency-Key']), [
        'key-1-padding', // first attempt
        'key-1-padding', // retry, same content
        'key-2-padding', // content changed
        'key-2-padding', // retry succeeds
        'key-3-padding', // a new request after success
      ]);
    },
  );
}
