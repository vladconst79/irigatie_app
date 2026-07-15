import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irigatie_app/main.dart';

void main() {
  test(
    'fetchSnapshot normalizes /api base URL and parses relay state',
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
          return http.Response('not found', 404);
        }),
      );

      final snapshot = await client.fetchSnapshot();

      expect(requested.map((uri) => uri.toString()).toList(), [
        'https://irigatie.example.com/api/snapshot',
      ]);
      expect(snapshot.statusAvailable, isTrue);
      expect(snapshot.transformerRelay?.active, isTrue);
      expect(snapshot.transformerRelay?.value, 1);
      expect(snapshot.rainfall24h.openMeteoMm, 2.5);
      expect(snapshot.rainfall24h.hardwareMm, 0.4);
      expect(snapshot.zones.single.rainCreditMm, 1.25);
      expect(snapshot.zones.single.cyclesWithoutRain, 3);
      expect(snapshot.zones.single.rainStateUpdatedAt, '2026-07-11 06:00:00');
      expect(snapshot.zones.single.lastRainEventId, 42);
      expect(snapshot.schedules.single.daysWithoutRain, 3);
    },
  );

  test(
    'fetchSnapshot reflects unavailable status from snapshot payload',
    () async {
      final client = IrrigationDataClient(
        apiSettings: const ApiSettings(
          apiUrl: 'https://irigatie.example.com',
          apiToken: '',
        ),
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/snapshot') {
            return _jsonResponse(_snapshotJson(statusAvailable: false));
          }
          return http.Response('not found', 404);
        }),
      );

      final snapshot = await client.fetchSnapshot();

      expect(snapshot.statusAvailable, isFalse);
      expect(snapshot.transformerRelay?.active, isNull);
      expect(snapshot.transformerRelay?.value, isNull);
      expect(snapshot.gatewayOnline, isTrue);
    },
  );

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

Map<String, Object?> _snapshotJson({bool statusAvailable = true}) {
  return {
    'ok': true,
    'database': {'ok': true, 'name': 'irigatie'},
    'gateway': {'online': true, 'socket_path': '/run/irigatie/control.sock'},
    'status': {
      'available': statusAvailable,
      'error': statusAvailable ? null : 'status_unavailable',
    },
    'relays': {
      'transformer': {
        'active': statusAvailable ? true : null,
        'value': statusAvailable ? 1 : null,
      },
    },
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
        'rain_credit_mm': 1.25,
        'cycles_without_rain': 3,
        'rain_state_updated_at': '2026-07-11 06:00:00',
        'last_rain_event_id': 42,
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
        'zile_fp': 3,
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
