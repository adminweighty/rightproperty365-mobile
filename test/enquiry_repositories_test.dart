import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/features/directory/data/business_enquiry_repository.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';

import 'support.dart';

const requestReceipt = {
  'request_id': '0195c0de-1111-7000-8000-000000000001',
  'reference': 'RP-8VXWDQJG',
  'status': 'RECEIVED',
  'created_at': '2026-11-13T09:00:00Z',
};

const enquiryReceipt = {
  'enquiry_id': '0195c0de-2222-7000-8000-000000000001',
  'reference': 'RP-3KQ7M2XT',
  'status': 'RECEIVED',
  'created_at': '2026-11-13T09:00:00Z',
};

const contact = EnquiryContact(
  name: 'Test Customer',
  email: 'test@example.com',
);

PropertyRequestDraft request({String message = 'Hello'}) =>
    PropertyRequestDraft(
      listingId: '0195c0de-0000-7000-8000-000000000001',
      requestType: RequestType.enquiry,
      message: message,
      contactMethod: ContactMethod.email,
      contact: contact,
      consentAccepted: true,
      privacyVersion: 'v1',
    );

BusinessEnquiryDraft enquiry({String message = 'Hello', String? service}) =>
    BusinessEnquiryDraft(
      recipient: sampleDirectory().find(
        DirectoryKind.serviceProviders,
        'sample-plumbers',
      )!,
      service: service,
      message: message,
      contactMethod: ContactMethod.whatsapp,
      contact: const EnquiryContact(
        name: 'Test Customer',
        email: 'test@example.com',
        phone: '+263 77 123 4567',
      ),
      consentAccepted: true,
      privacyVersion: 'v1',
    );

TypeMatcher<ApiFailure> failure(
  int status, {
  String? message,
  String? traceId,
}) => isA<ApiFailure>()
    .having((f) => f.status, 'status', status)
    .having((f) => f.message, 'message', message ?? anything)
    .having((f) => f.traceId, 'traceId', traceId ?? anything);

http.Response error(int status, String code, {Map<String, String>? fields}) =>
    jsonResponse(status, {
      'error': {
        'code': code,
        'message': 'raw server message',
        'fields': ?fields,
      },
      'trace_id': 'trace-1',
    });

void main() {
  group('property requests', () {
    ApiPropertyRequestRepository build(ApiClient api) =>
        ApiPropertyRequestRepository(api, newKey: countingKeys());

    test(
      '201 returns the receipt and posts with the idempotency key',
      () async {
        final (:api, :requests) = mockApi(
          (_) async => jsonResponse(201, requestReceipt),
        );

        final receipt = await build(api).submit(request());

        expect(receipt.reference, 'RP-8VXWDQJG');
        expect(receipt.status, 'RECEIVED');
        final sent = requests.single;
        expect(sent.method, 'POST');
        expect(sent.url.toString(), 'http://api.test/v1/property-requests');
        expect(sent.headers['Idempotency-Key'], 'key-1-padding');
        expect(jsonDecode(sent.body)['idempotency_key'], 'key-1-padding');
        expect(sent.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('200 replay is treated as the same receipt', () async {
      final (:api, requests: _) = mockApi(
        (_) async => jsonResponse(200, requestReceipt),
      );
      expect(
        (await build(api).submit(request())).id,
        requestReceipt['request_id'],
      );
    });

    test('sends the bearer token when signed in', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(201, requestReceipt),
      );
      api.bearerToken = 'token-abc';
      await build(api).submit(request());
      expect(requests.single.headers['Authorization'], 'Bearer token-abc');
    });

    test('400 surfaces field errors and the trace id', () async {
      final (:api, requests: _) = mockApi(
        (_) async => error(
          400,
          'VALIDATION_FAILED',
          fields: {'guest_contact.phone': 'is required'},
        ),
      );
      await expectLater(
        build(api).submit(request()),
        throwsA(
          failure(400, traceId: 'trace-1').having((f) => f.fields, 'fields', {
            'guest_contact.phone': 'is required',
          }),
        ),
      );
    });

    test('410 explains that the listing is no longer available', () async {
      final (:api, requests: _) = mockApi(
        (_) async => error(410, 'LISTING_UNAVAILABLE'),
      );
      await expectLater(
        build(api).submit(request()),
        throwsA(
          failure(
            410,
            message: 'This listing is no longer available for enquiries.',
          ),
        ),
      );
    });

    test('a network failure is reported as such', () async {
      final (:api, requests: _) = mockApi(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        build(api).submit(request()),
        throwsA(
          isA<ApiFailure>().having((f) => f.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });

    test(
      'a retry of unchanged content reuses the key; an edit gets a new one',
      () async {
        var fail = true;
        final (:api, :requests) = mockApi((_) async {
          if (fail) throw http.ClientException('offline');
          return jsonResponse(201, requestReceipt);
        });
        final repository = build(api);

        await expectLater(
          repository.submit(request()),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(
          repository.submit(request()),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(
          repository.submit(request(message: 'Edited')),
          throwsA(isA<ApiFailure>()),
        );
        fail = false;
        await repository.submit(request(message: 'Edited'));
        await repository.submit(request(message: 'Edited'));

        expect(requests.map((r) => r.headers['Idempotency-Key']), [
          'key-1-padding', // first attempt
          'key-1-padding', // retry, same content
          'key-2-padding', // content changed
          'key-2-padding', // retry succeeds
          'key-3-padding', // a new request after success
        ]);
      },
    );
  });

  group('business enquiries', () {
    ApiBusinessEnquiryRepository build(ApiClient api) =>
        ApiBusinessEnquiryRepository(api, newKey: countingKeys());

    test('201 returns the receipt and posts the documented body', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(201, enquiryReceipt),
      );

      final receipt = await build(api).submit(enquiry(service: 'Geysers'));

      expect(receipt.id, enquiryReceipt['enquiry_id']);
      expect(receipt.reference, 'RP-3KQ7M2XT');
      final sent = requests.single;
      expect(sent.url.toString(), 'http://api.test/v1/business-enquiries');
      expect(sent.headers['Idempotency-Key'], 'key-1-padding');
      expect(jsonDecode(sent.body), {
        'recipient': {'kind': 'service-providers', 'slug': 'sample-plumbers'},
        'service': 'Geysers',
        'message': 'Hello',
        'preferred_contact_method': 'WHATSAPP',
        'idempotency_key': 'key-1-padding',
        'guest_contact': {
          'name': 'Test Customer',
          'email': 'test@example.com',
          'phone': '+263771234567',
        },
        'consent': {'privacy_version': 'v1', 'accepted': true},
      });
    });

    test('service is left out when none was chosen', () async {
      final (:api, :requests) = mockApi(
        (_) async => jsonResponse(201, enquiryReceipt),
      );
      await build(api).submit(enquiry());
      expect(
        (jsonDecode(requests.single.body) as Map).containsKey('service'),
        isFalse,
      );
    });

    test(
      '404 (endpoint not deployed yet) is explained without a server message',
      () async {
        final (:api, requests: _) = mockApi(
          (_) async => error(404, 'NOT_FOUND'),
        );
        await expectLater(
          build(api).submit(enquiry()),
          throwsA(
            failure(
              404,
              message: 'Enquiries to this profile are not available yet. Please try again later.',
              traceId: 'trace-1',
            ),
          ),
        );
      },
    );

    test('a 404 with no JSON body is handled the same way', () async {
      final (:api, requests: _) = mockApi(
        (_) async => http.Response('404 page not found', 404),
      );
      await expectLater(build(api).submit(enquiry()), throwsA(failure(404)));
    });

    test('400 keeps field errors so the form can show them', () async {
      final (:api, requests: _) = mockApi(
        (_) async =>
            error(400, 'VALIDATION_FAILED', fields: {'message': 'is required'}),
      );
      await expectLater(
        build(api).submit(enquiry()),
        throwsA(
          failure(400)
              .having((f) => f.fields, 'fields', {'message': 'is required'}),
        ),
      );
    });

    test(
      'a network failure is reported, and the retry reuses the key',
      () async {
        var fail = true;
        final (:api, :requests) = mockApi((_) async {
          if (fail) throw http.ClientException('offline');
          return jsonResponse(201, enquiryReceipt);
        });
        final repository = build(api);

        await expectLater(
          repository.submit(enquiry()),
          throwsA(
            isA<ApiFailure>().having((f) => f.isNetwork, 'isNetwork', isTrue),
          ),
        );
        fail = false;
        await repository.submit(enquiry());

        expect(requests.map((r) => r.headers['Idempotency-Key']), [
          'key-1-padding',
          'key-1-padding',
        ]);
      },
    );
  });
}
