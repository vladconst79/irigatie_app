import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irigatie_app/main.dart';

void main() {
  test(
    'fetchSnapshot normalizes /api base URL and parses status relay',
    () async {
      final requested = <Uri>[];
      final client = IrrigationDataClient(
        apiSettings: const ApiSettings(
          apiUrl: 'https://irigatie.example.com/api/',
          apiToken: 'token',
        ),
        httpClient: MockClient((request) async {
          requested.add(request.url);
          expect(request.headers['Authorization'], 'Bearer token');

          if (request.url.path == '/api/snapshot') {
            return _jsonResponse(_snapshotJson());
          }
          if (request.url.path == '/api/status') {
            return _jsonResponse(_statusJson());
          }
          return http.Response('not found', 404);
        }),
      );

      final snapshot = await client.fetchSnapshot();

      expect(requested.map((uri) => uri.toString()).toList(), [
        'https://irigatie.example.com/api/snapshot',
        'https://irigatie.example.com/api/status',
      ]);
      expect(snapshot.statusAvailable, isTrue);
      expect(snapshot.transformerRelay?.active, isTrue);
      expect(snapshot.transformerRelay?.value, 1);
      expect(snapshot.rainfall24h.openMeteoMm, 2.5);
      expect(snapshot.rainfall24h.hardwareMm, 0.4);
    },
  );

  test('fetchSnapshot degrades when status endpoint fails', () async {
    final client = IrrigationDataClient(
      apiSettings: const ApiSettings(
        apiUrl: 'https://irigatie.example.com',
        apiToken: '',
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/snapshot') {
          return _jsonResponse(_snapshotJson());
        }
        if (request.url.path == '/api/status') {
          return http.Response(
            jsonEncode({'ok': false, 'error': 'status unavailable'}),
            503,
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final snapshot = await client.fetchSnapshot();

    expect(snapshot.statusAvailable, isFalse);
    expect(snapshot.transformerRelay, isNull);
    expect(snapshot.gatewayOnline, isTrue);
  });

  test(
    'fetchWateringHistory sends query parameters on relative API URL',
    () async {
      final requested = <Uri>[];
      final client = IrrigationDataClient(
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return _jsonResponse({
            'ok': true,
            'items': [],
            'next_before_id': null,
            'has_more': false,
          });
        }),
      );

      final page = await client.fetchWateringHistory(limit: 25, beforeId: 12);

      expect(page.items, isEmpty);
      expect(requested.single.path, '/api/watering-history');
      expect(requested.single.queryParameters, {
        'limit': '25',
        'before_id': '12',
      });
    },
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> _snapshotJson() {
  return {
    'ok': true,
    'database': {'ok': true, 'name': 'irigatie'},
    'gateway': {'online': true, 'socket_path': '/run/irigatie/control.sock'},
    'queue': {'pending': 1, 'max': 4},
    'runtime': {
      'state': 'running',
      'source': 'scheduled',
      'command': 'START',
      'program_id': 12,
      'zone_id': 1,
      'remaining_seconds': 120,
      'heartbeat_at': '2026-07-11 12:00:00',
      'message': 'running',
    },
    'last_rain': {
      'source': 'N/A',
      'event_time': 'N/A',
      'amount_mm': 0,
      'raw_value': null,
    },
    'rain_24h': {
      'window_hours': 24,
      'window_start': '2026-07-10 12:00:00',
      'window_end': '2026-07-11 12:00:00',
      'sources': {
        'openmeteo': {
          'amount_mm': 2.5,
          'event_count': 2,
          'latest_event_time': '2026-07-11 06:00:00',
        },
        'hardware': {
          'amount_mm': 0.4,
          'event_count': 1,
          'latest_event_time': '2026-07-11 05:00:00',
        },
      },
    },
    'zones': [
      {
        'id': 1,
        'name': 'Gazon',
        'type': 'sprinkler',
        'enabled': true,
        'relay_active': true,
        'relay_value': 1,
      },
    ],
    'schedules': [
      {
        'id': 12,
        'zone_id': 1,
        'month': '*',
        'day_of_month': '*',
        'day_of_week': '1,3,5',
        'hour': '6',
        'minute': '0',
        'duration_minutes': 12,
        'max_rain_mm': 4,
        'current_rain_mm': 2.5,
        'enabled': true,
      },
    ],
    'manual_programs': [
      {
        'id': 1,
        'name': 'Scurt',
        'zone_durations': {'1': 5},
      },
    ],
  };
}

Map<String, Object?> _statusJson() {
  return {
    'ok': true,
    'gateway': {
      'state': 'running',
      'socket_path': '/run/irigatie/control.sock',
      'socket_exists': true,
      'daemon_status_supported': true,
    },
    'daemon': {
      'ok': true,
      'daemon_state': 'running',
      'current_program': 12,
      'current_zone': 1,
      'remaining_seconds': 120,
      'last_rain_update': null,
      'db': {'ok': true, 'error': null},
      'relay_state': {
        'transformer': {'active': true, 'value': 1},
        'zones': {
          '1': {'active': true, 'value': 1},
        },
      },
      'runtime': null,
      'queue': {
        'pending_watering_commands': 0,
        'max_pending_watering_commands': 4,
      },
      'schedule_reload': {
        'state': 'ok',
        'last_started_at': null,
        'last_finished_at': null,
        'error': null,
      },
      'checks': {
        'daemon_ok': true,
        'db_ok': true,
        'socket_ok': true,
        'relay_safety_ok': true,
        'queue_ok': true,
      },
    },
  };
}
