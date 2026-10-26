import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/connection_qr_payload.dart';

void main() {
  group('ConnectionQrPayload.tryParse', () {
    test('parses a valid payload', () {
      final payload = ConnectionQrPayload.tryParse('{"server_url":"https://1.2.3.4:8443","bearer_token":"sometoken","cert_sha256":"DEADBEEF"}');
      expect(payload, isNotNull);
      expect(payload!.serverUrl, Uri.parse('https://1.2.3.4:8443'));
      expect(payload.bearerToken, 'sometoken');
      expect(payload.certSha256, 'DEADBEEF');
    });

    test('returns null for non-JSON text', () {
      expect(ConnectionQrPayload.tryParse('not json at all'), isNull);
    });

    test('returns null for JSON that is not an object', () {
      expect(ConnectionQrPayload.tryParse('[1, 2, 3]'), isNull);
    });

    test('returns null when a field is missing', () {
      expect(ConnectionQrPayload.tryParse('{"server_url":"https://1.2.3.4:8443","bearer_token":"sometoken"}'), isNull);
    });

    test('returns null when a field is empty', () {
      expect(ConnectionQrPayload.tryParse('{"server_url":"https://1.2.3.4:8443","bearer_token":"","cert_sha256":"DEADBEEF"}'), isNull);
    });

    test('returns null when server_url is not an absolute URL', () {
      expect(ConnectionQrPayload.tryParse('{"server_url":"not a url","bearer_token":"sometoken","cert_sha256":"DEADBEEF"}'), isNull);
    });

    test('returns null when a field has the wrong type', () {
      expect(ConnectionQrPayload.tryParse('{"server_url":"https://1.2.3.4:8443","bearer_token":123,"cert_sha256":"DEADBEEF"}'), isNull);
    });
  });
}
