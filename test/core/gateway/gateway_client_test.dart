import 'dart:convert';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bodyless completion does not declare an empty JSON payload', () async {
    final client = GatewayClient(
      baseUri: Uri.parse('https://files.example.com'),
      userId: () => 'worker',
      accessToken: () => 'token',
      refresh: () async {},
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyBytes, isEmpty);
        expect(request.headers.containsKey('Content-Type'), isFalse);
        return http.Response('{"complete":true}', 200);
      }),
    );
    expect((await client.json('POST', '/v1/uploads/example/complete'))['complete'],
        isTrue);
  });
  test('preserves Supabase function prefix and never follows redirects',
      () async {
    final client = GatewayClient(
      baseUri:
          Uri.parse('https://project.supabase.co/functions/v1/drive-gateway/'),
      userId: () => 'worker',
      accessToken: () => 'token',
      refresh: () async {},
      client: MockClient((request) async {
        expect(request.url.toString(),
            'https://project.supabase.co/functions/v1/drive-gateway/v1/assignments?after=abc');
        expect(request.followRedirects, isFalse);
        return http.Response('{}', 200);
      }),
    );
    await client.json('GET', '/v1/assignments?after=abc');
    await expectLater(client.json('GET', '/v1/../auth'), throwsArgumentError);
  });

  test('uses app token and renews it once after a 401', () async {
    var token = 'app-old';
    var renewals = 0;
    final observed = <String?>[];
    final client = GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => 'worker',
        accessToken: () => token,
        refresh: () async {
          renewals++;
          token = 'app-new';
        },
        client: MockClient((r) async {
          observed.add(r.headers['Authorization']);
          return token == 'app-old'
              ? http.Response('{"code":"SESSION_EXPIRED"}', 401)
              : http.Response('{"assignments":[]}', 200);
        }));
    expect(await client.json('GET', '/v1/assignments'), {'assignments': []});
    expect(observed, ['Bearer app-old', 'Bearer app-new']);
    expect(renewals, 1);
  });
  test('account change during renewal never sends the old transfer as new user',
      () async {
    var user = 'one';
    var requests = 0;
    final client = GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => user,
        accessToken: () => 'token',
        refresh: () async {
          user = 'two';
        },
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 401);
        }));
    await expectLater(client.json('GET', '/v1/assignments', owner: 'one'),
        throwsA(isA<AuthFailure>()));
    expect(requests, 1);
  });
  test('Drive outage stays a service error, without renewing the worker login',
      () async {
    var renewals = 0;
    final client = GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => 'worker',
        accessToken: () => 'app-token',
        refresh: () async {
          renewals++;
        },
        client: MockClient((_) async => http.Response(
            jsonEncode({'code': 'DRIVE_CONNECTION_UNAVAILABLE'}), 503)));
    await expectLater(
        client.json('GET', '/v1/assignments'), throwsA(isA<NetworkFailure>()));
    expect(renewals, 0);
  });
  test('rejects cleartext non-local server configuration', () {
    expect(
        () => GatewayClient(
            baseUri: Uri.parse('http://files.example.com'),
            userId: () => null,
            accessToken: () => null,
            refresh: () async {}),
        throwsArgumentError);
  });
}
