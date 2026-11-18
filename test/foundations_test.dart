import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/core/config.dart';
import 'package:rightproperty365/core/push/push_messaging.dart';

import 'api_routes.dart';
import 'support.dart';

void main() {
  test('push is off without a Firebase project', () async {
    expect(PushConfig.configured, isFalse);
    final push = await FirebasePushMessaging.start();
    expect(push, isA<NoPushMessaging>());
    expect(await push.state(), PushState.unavailable);
    expect(await push.requestPermission(), PushState.unavailable);
    expect(await push.token(), isNull);
    expect(TestServices().services.push, isA<NoPushMessaging>());
  });

  test('the map is off until a tile source and attribution are set', () {
    expect(AppConfig.mapEnabled, isFalse);
  });

  test('routed API answers known routes and 404s the rest', () async {
    final (:api, :requests) = routedApi({
      'POST /v1/thing': (request) => {'echo': jsonBody(request)['a']},
    });
    expect((await api.postJson('/v1/thing', {'a': 1})).body, {'echo': 1});
    await expectLater(api.get('/v1/missing'), throwsA(anything));
    expect(requests, hasLength(2));
  });
}
