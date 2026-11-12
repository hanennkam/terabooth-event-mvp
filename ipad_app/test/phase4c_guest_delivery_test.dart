import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';

void main() {
  Map<String, dynamic> job({String? url}) => {
    'job_id': 'job_1',
    'state': 'completed',
    'completion': 'confirmed',
    'attempts': 1,
    'session_id': 'ses_1',
    'event_id': 'evt_1',
    'template': 'strip_2x6_3up_v1',
    'copies': 1,
    'event_title': 'Acme Gala',
    'event_date': '14 Nov 2026',
    'created_at': '2026-11-14T18:00:00Z',
    'updated_at': '2026-11-14T18:01:00Z',
    'error': null,
    'reprint_of': null,
    'gif_state': 'ready',
    'gif_bytes': 1200,
    'delivery_url': url,
    'delivery_available': url != null,
    'images': <dynamic>[],
  };

  test('guest delivery link can be revoked and regenerated', () async {
    var revokeCalls = 0;
    var regenerateCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/delivery/revoke')) {
        revokeCalls++;
        return http.Response(jsonEncode(job()), 200);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/delivery/regenerate')) {
        regenerateCalls++;
        return http.Response(
          jsonEncode(job(url: 'http://192.168.8.50:8787/d/newtoken')),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final bridge = BridgeClient(
      baseUrl: 'http://192.168.8.50:8787',
      client: client,
    );

    final revoked = await bridge.revokeDelivery('job_1');
    expect(revokeCalls, 1);
    expect(revoked.deliveryUrl, isNull);

    final regenerated = await bridge.regenerateDelivery('job_1');
    expect(regenerateCalls, 1);
    expect(regenerated.deliveryUrl, contains('/d/newtoken'));
    expect(regenerated.deliveryUrl, isNot(contains('localhost')));
  });
}
