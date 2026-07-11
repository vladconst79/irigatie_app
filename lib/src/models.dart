part of '../main.dart';

enum DaemonState { idle, running, stopping, interrupted, error, unknown }

extension on DaemonState {
  String get label {
    return switch (this) {
      DaemonState.idle => 'idle',
      DaemonState.running => 'running',
      DaemonState.stopping => 'stopping',
      DaemonState.interrupted => 'interrupted',
      DaemonState.error => 'error',
      DaemonState.unknown => 'unknown',
    };
  }

  _Tone get tone {
    return switch (this) {
      DaemonState.idle || DaemonState.running => _Tone.green,
      DaemonState.stopping || DaemonState.unknown => _Tone.amber,
      DaemonState.interrupted || DaemonState.error => _Tone.red,
    };
  }
}

enum ZoneType { sprinkler, drip }

extension on ZoneType {
  String get label => this == ZoneType.sprinkler ? 'Aspersor' : 'Picurator';
  String get apiValue => this == ZoneType.sprinkler ? 'sprinkler' : 'drip';
}

class IrrigationZone {
  const IrrigationZone({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.relayActive,
    required this.relayValue,
    required this.color,
  });

  final int id;
  final String name;
  final ZoneType type;
  final bool enabled;
  final bool relayActive;
  final double? relayValue;
  final Color color;

  IconData get icon =>
      type == ZoneType.sprinkler ? Icons.water_rounded : Icons.grass_rounded;

  factory IrrigationZone.fromJson(Map<String, dynamic> json, int index) {
    return IrrigationZone(
      id: _asInt(json['id']),
      name: _asString(json['name'], fallback: 'Traseu ${json['id'] ?? index}'),
      type: _zoneTypeFromDatabaseValue(json['type']),
      enabled: _asBool(json['enabled'], fallback: true),
      relayActive: _asBool(json['relay_active']),
      relayValue: _nullableDouble(json['relay_value']),
      color: _zoneColors[index % _zoneColors.length],
    );
  }
}

class RelayStatus {
  const RelayStatus({required this.active, required this.value});

  final bool? active;
  final double? value;

  factory RelayStatus.fromJson(Map<String, dynamic> json) {
    return RelayStatus(
      active: _nullableBool(json['active']),
      value: _nullableDouble(json['value']),
    );
  }
}

class ScheduleProgram {
  const ScheduleProgram({
    required this.id,
    required this.zone,
    required this.month,
    required this.dayOfMonth,
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.maxRainMm,
    required this.currentRainMm,
    required this.enabled,
  });

  final int id;
  final IrrigationZone zone;
  final String month;
  final String dayOfMonth;
  final String dayOfWeek;
  final String hour;
  final String minute;
  final int durationMinutes;
  final double maxRainMm;
  final double currentRainMm;
  final bool enabled;

  String get monthLabel => month == '*' ? 'toate lunile' : 'luna $month';

  String get dayLabel {
    final monthDay = dayOfMonth == '*' ? null : 'zi $dayOfMonth';
    final weekDay = dayOfWeek == '*' ? null : 'DOW $dayOfWeek';

    if (monthDay == null && weekDay == null) return 'zilnic';
    if (monthDay != null && weekDay != null) return '$monthDay / $weekDay';
    return monthDay ?? weekDay!;
  }

  String get cronLabel {
    return '$dayLabel · $hour:${minute.padLeft(2, '0')}';
  }

  factory ScheduleProgram.fromJson(
    Map<String, dynamic> json,
    Map<int, IrrigationZone> zones,
  ) {
    final zoneId = _asInt(json['zone_id']);
    final zone = zones[zoneId] ?? _unknownZone(zoneId);

    return ScheduleProgram(
      id: _asInt(json['id']),
      zone: zone,
      month: _asString(json['month'], fallback: '*'),
      dayOfMonth: _asString(json['day_of_month'], fallback: '*'),
      dayOfWeek: _asString(json['day_of_week'], fallback: '*'),
      hour: _asString(json['hour'], fallback: '0'),
      minute: _asString(json['minute'], fallback: '0'),
      durationMinutes: _asInt(json['duration_minutes']),
      maxRainMm: _asDouble(json['max_rain_mm'], fallback: 0),
      currentRainMm: _asDouble(json['current_rain_mm'], fallback: 0),
      enabled: _asBool(json['enabled'], fallback: true),
    );
  }
}

class ManualProgram {
  const ManualProgram({
    required this.id,
    required this.name,
    required this.zoneDurations,
  });

  final int id;
  final String name;
  final Map<IrrigationZone, int> zoneDurations;

  factory ManualProgram.fromJson(
    Map<String, dynamic> json,
    Map<int, IrrigationZone> zones,
  ) {
    final durations = <IrrigationZone, int>{};
    final rawDurations = json['zone_durations'];
    if (rawDurations is Map) {
      for (final entry in rawDurations.entries) {
        final zoneId = _asInt(entry.key);
        durations[zones[zoneId] ?? _unknownZone(zoneId)] = _asInt(entry.value);
      }
    }

    return ManualProgram(
      id: _asInt(json['id']),
      name: _asString(json['name'], fallback: 'Manual ${json['id'] ?? ''}'),
      zoneDurations: durations,
    );
  }
}

class Rainfall24h {
  const Rainfall24h({required this.openMeteoMm, required this.hardwareMm});

  final double openMeteoMm;
  final double hardwareMm;

  String get openMeteoLabel => '${openMeteoMm.toStringAsFixed(1)} mm';

  String get hardwareLabel => '${hardwareMm.toStringAsFixed(1)} mm';

  static const empty = Rainfall24h(openMeteoMm: 0, hardwareMm: 0);

  factory Rainfall24h.fromJson(
    Map<String, dynamic> json,
    Map<String, dynamic> lastRain,
  ) {
    final sources = _asMap(json['sources']);
    final openMeteo = _sourceAmount(
      json,
      sources,
      aliases: const ['openmeteo', 'open_meteo'],
      directKeys: const ['openmeteo_mm', 'open_meteo_mm'],
    );
    final hardware = _sourceAmount(
      json,
      sources,
      aliases: const ['hardware'],
      directKeys: const ['hardware_mm'],
    );

    if (openMeteo > 0 || hardware > 0 || json.isNotEmpty) {
      return Rainfall24h(openMeteoMm: openMeteo, hardwareMm: hardware);
    }

    final source = _asString(lastRain['source']).toLowerCase();
    final amount = _asDouble(lastRain['amount_mm'], fallback: 0);
    if (source == 'openmeteo' || source == 'open_meteo') {
      return Rainfall24h(openMeteoMm: amount, hardwareMm: 0);
    }
    if (source == 'hardware') {
      return Rainfall24h(openMeteoMm: 0, hardwareMm: amount);
    }

    return empty;
  }

  static double _sourceAmount(
    Map<String, dynamic> json,
    Map<String, dynamic> sources, {
    required List<String> aliases,
    required List<String> directKeys,
  }) {
    for (final key in directKeys) {
      if (json.containsKey(key)) {
        return _asDouble(json[key], fallback: 0);
      }
    }

    for (final alias in aliases) {
      final rawSource = sources[alias];
      if (rawSource is Map) {
        final source = Map<String, dynamic>.from(rawSource);
        return _asDouble(
          source['amount_mm'] ?? source['total_mm'] ?? source['mm'],
          fallback: 0,
        );
      }
      if (rawSource != null) {
        return _asDouble(rawSource, fallback: 0);
      }
    }

    return 0;
  }
}

class WateringHistoryPage {
  const WateringHistoryPage({
    required this.items,
    required this.nextBeforeId,
    required this.hasMore,
  });

  final List<WateringHistoryItem> items;
  final int? nextBeforeId;
  final bool hasMore;

  factory WateringHistoryPage.fromJson(Map<String, dynamic> json) {
    return WateringHistoryPage(
      items: [
        for (final item in _asList(json['items']))
          if (item is Map)
            WateringHistoryItem.fromJson(Map<String, dynamic>.from(item)),
      ],
      nextBeforeId: _nullableInt(json['next_before_id']),
      hasMore: _asBool(json['has_more']),
    );
  }
}

class WateringHistoryItem {
  const WateringHistoryItem({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.source,
    required this.programId,
    required this.programName,
    required this.zoneId,
    required this.zoneName,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.rainCreditMm,
    required this.result,
    required this.error,
  });

  final int id;
  final String startedAt;
  final String endedAt;
  final String source;
  final int? programId;
  final String? programName;
  final int? zoneId;
  final String? zoneName;
  final double? plannedSeconds;
  final double? actualSeconds;
  final double? rainCreditMm;
  final String result;
  final String? error;

  String get programLabel {
    final label = programName;
    if (label != null && label.isNotEmpty) return label;
    final id = programId;
    return id == null ? '' : 'Program #$id';
  }

  String get zoneLabel {
    final label = zoneName;
    if (label != null && label.isNotEmpty) return label;
    final id = zoneId;
    return id == null ? 'Traseu necunoscut' : 'Traseu #$id';
  }

  factory WateringHistoryItem.fromJson(Map<String, dynamic> json) {
    return WateringHistoryItem(
      id: _asInt(json['id']),
      startedAt: _asString(json['started_at'], fallback: 'N/A'),
      endedAt: _asString(json['ended_at'], fallback: 'N/A'),
      source: _asString(json['source'], fallback: 'N/A'),
      programId: _nullableInt(json['program_id']),
      programName: _nullableString(json['program_name']),
      zoneId: _nullableInt(json['zone_id']),
      zoneName: _nullableString(json['zone_name']),
      plannedSeconds: _nullableDouble(json['planned_seconds']),
      actualSeconds: _nullableDouble(json['actual_seconds']),
      rainCreditMm: _nullableDouble(json['rain_credit_mm']),
      result: _asString(json['result'], fallback: 'unknown'),
      error: _nullableString(json['error']),
    );
  }
}

class WriteResult {
  const WriteResult({required this.id, required this.message});

  final int id;
  final String message;

  factory WriteResult.fromJson(Map<String, dynamic> json) {
    return WriteResult(
      id: _asInt(json['id']),
      message: _asString(json['message'], fallback: 'ok'),
    );
  }
}

class ZoneWriteRequest {
  const ZoneWriteRequest({
    required this.name,
    required this.type,
    required this.enabled,
  });

  final String name;
  final ZoneType type;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.apiValue,
    'enabled': enabled,
  };
}

class ScheduleWriteRequest {
  const ScheduleWriteRequest({
    required this.zoneId,
    required this.month,
    required this.dayOfMonth,
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.maxRainMm,
    required this.enabled,
  });

  final int zoneId;
  final String month;
  final String dayOfMonth;
  final String dayOfWeek;
  final String hour;
  final String minute;
  final int durationMinutes;
  final double maxRainMm;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'zone_id': zoneId,
    'month': month,
    'day_of_month': dayOfMonth,
    'day_of_week': dayOfWeek,
    'hour': hour,
    'minute': minute,
    'duration_minutes': durationMinutes,
    'max_rain_mm': maxRainMm,
    'enabled': enabled,
  };
}

class ManualProgramWriteRequest {
  const ManualProgramWriteRequest({
    required this.name,
    required this.zoneDurations,
  });

  final String name;
  final Map<int, int> zoneDurations;

  Map<String, Object?> toJson() => {
    'name': name,
    'zone_durations': {
      for (final entry in zoneDurations.entries)
        entry.key.toString(): entry.value,
    },
  };
}

class CommandResult {
  const CommandResult({required this.command});

  final String command;

  factory CommandResult.fromJson(Map<String, dynamic> json) {
    final gateway = _asMap(json['gateway']);
    return CommandResult(
      command: _asString(
        gateway['command'] ?? json['command'],
        fallback: 'EXEC ${json['program_id']}',
      ),
    );
  }
}

class IrrigationSnapshot {
  const IrrigationSnapshot({
    required this.daemonState,
    required this.gatewayOnline,
    required this.databaseOk,
    required this.currentProgram,
    required this.currentZone,
    required this.remainingSeconds,
    required this.runtimeMessage,
    required this.runtimeSource,
    required this.runtimeCommand,
    required this.heartbeatAt,
    required this.socketPath,
    required this.rainfall24h,
    required this.pendingCommands,
    required this.maxPendingCommands,
    required this.statusAvailable,
    required this.transformerRelay,
    required this.zones,
    required this.schedules,
    required this.manualPrograms,
  });

  final DaemonState daemonState;
  final bool gatewayOnline;
  final bool databaseOk;
  final String? currentProgram;
  final String? currentZone;
  final int remainingSeconds;
  final String runtimeMessage;
  final String runtimeSource;
  final String runtimeCommand;
  final String heartbeatAt;
  final String socketPath;
  final Rainfall24h rainfall24h;
  final int pendingCommands;
  final int maxPendingCommands;
  final bool statusAvailable;
  final RelayStatus? transformerRelay;
  final List<IrrigationZone> zones;
  final List<ScheduleProgram> schedules;
  final List<ManualProgram> manualPrograms;

  String get remainingLabel {
    if (remainingSeconds <= 0) return 'nicio udare activa';
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} ramase';
  }

  factory IrrigationSnapshot.empty() {
    return const IrrigationSnapshot(
      daemonState: DaemonState.unknown,
      gatewayOnline: false,
      databaseOk: false,
      currentProgram: null,
      currentZone: null,
      remainingSeconds: 0,
      runtimeMessage: 'Astept date din MariaDB',
      runtimeSource: 'N/A',
      runtimeCommand: 'N/A',
      heartbeatAt: 'N/A',
      socketPath: 'N/A',
      rainfall24h: Rainfall24h.empty,
      pendingCommands: 0,
      maxPendingCommands: 4,
      statusAvailable: false,
      transformerRelay: null,
      zones: [],
      schedules: [],
      manualPrograms: [],
    );
  }

  factory IrrigationSnapshot.fromJson(Map<String, dynamic> json) {
    final rawZones = _asList(json['zones']);
    final zones = <IrrigationZone>[
      for (var index = 0; index < rawZones.length; index += 1)
        if (rawZones[index] is Map)
          IrrigationZone.fromJson(
            Map<String, dynamic>.from(rawZones[index] as Map),
            index,
          ),
    ];
    final zonesById = {for (final zone in zones) zone.id: zone};

    final rawRuntime = _asMap(json['runtime']);
    final rawRainfall24h = _asMap(json['rain_24h']);
    final rawLastRain = _asMap(json['last_rain']);
    final rawGateway = _asMap(json['gateway']);
    final rawDb = _asMap(json['database']);
    final rawQueue = _asMap(json['queue']);
    final rawSchedules = _asList(json['schedules']);
    final rawManualPrograms = _asList(json['manual_programs']);
    final rawStatus = _asMap(json['status']);
    final rawRelays = _asMap(json['relays']);
    final rawTransformerRelay = _asMap(rawRelays['transformer']);
    final currentZoneId = _nullableInt(rawRuntime['zone_id']);
    final currentProgramId = _nullableInt(rawRuntime['program_id']);

    return IrrigationSnapshot(
      daemonState: _daemonStateFromString(rawRuntime['state']),
      gatewayOnline: _asBool(rawGateway['online']),
      databaseOk: _asBool(rawDb['ok']),
      currentProgram: currentProgramId == null
          ? null
          : 'Program #$currentProgramId',
      currentZone: currentZoneId == null
          ? null
          : zonesById[currentZoneId]?.name ?? 'Traseu #$currentZoneId',
      remainingSeconds: _asInt(rawRuntime['remaining_seconds']),
      runtimeMessage: _asString(rawRuntime['message'], fallback: 'N/A'),
      runtimeSource: _asString(rawRuntime['source'], fallback: 'N/A'),
      runtimeCommand: _asString(rawRuntime['command'], fallback: 'N/A'),
      heartbeatAt: _asString(rawRuntime['heartbeat_at'], fallback: 'N/A'),
      socketPath: _asString(rawGateway['socket_path'], fallback: 'N/A'),
      rainfall24h: Rainfall24h.fromJson(rawRainfall24h, rawLastRain),
      pendingCommands: _asInt(rawQueue['pending']),
      maxPendingCommands: _asInt(rawQueue['max'], fallback: 4),
      statusAvailable: _asBool(rawStatus['available']),
      transformerRelay: rawTransformerRelay.isEmpty
          ? null
          : RelayStatus.fromJson(rawTransformerRelay),
      zones: zones,
      schedules: [
        for (final item in rawSchedules)
          if (item is Map)
            ScheduleProgram.fromJson(
              Map<String, dynamic>.from(item),
              zonesById,
            ),
      ],
      manualPrograms: [
        for (final item in rawManualPrograms)
          if (item is Map)
            ManualProgram.fromJson(Map<String, dynamic>.from(item), zonesById),
      ],
    );
  }

  factory IrrigationSnapshot.sample() {
    const zones = [
      IrrigationZone(
        id: 1,
        name: 'Gazon fata',
        type: ZoneType.sprinkler,
        enabled: true,
        relayActive: true,
        relayValue: 1,
        color: Color(0xFF0E7C66),
      ),
      IrrigationZone(
        id: 2,
        name: 'Gradina legume',
        type: ZoneType.drip,
        enabled: true,
        relayActive: false,
        relayValue: 0,
        color: Color(0xFF3268A8),
      ),
      IrrigationZone(
        id: 3,
        name: 'Livada',
        type: ZoneType.drip,
        enabled: true,
        relayActive: false,
        relayValue: 0,
        color: Color(0xFFD08B2F),
      ),
      IrrigationZone(
        id: 4,
        name: 'Terasa',
        type: ZoneType.sprinkler,
        enabled: false,
        relayActive: false,
        relayValue: 0,
        color: Color(0xFF7B5EA7),
      ),
    ];

    return IrrigationSnapshot(
      daemonState: DaemonState.running,
      gatewayOnline: true,
      databaseOk: true,
      currentProgram: 'Program #12',
      currentZone: 'Gazon fata',
      remainingSeconds: 460,
      runtimeMessage: 'Udare programata in executie',
      runtimeSource: 'scheduled',
      runtimeCommand: 'START',
      heartbeatAt: '2026-07-08 15:42',
      socketPath: '/run/irigatie/control.sock',
      rainfall24h: const Rainfall24h(openMeteoMm: 2.8, hardwareMm: 0.4),
      pendingCommands: 1,
      maxPendingCommands: 4,
      statusAvailable: true,
      transformerRelay: const RelayStatus(active: true, value: 1),
      zones: zones,
      schedules: [
        ScheduleProgram(
          id: 12,
          zone: zones[0],
          month: '*',
          dayOfMonth: '*',
          dayOfWeek: '1,3,5',
          hour: '6',
          minute: '0',
          durationMinutes: 12,
          maxRainMm: 4,
          currentRainMm: 2.8,
          enabled: true,
        ),
        ScheduleProgram(
          id: 14,
          zone: zones[1],
          month: '*',
          dayOfMonth: '*',
          dayOfWeek: '*',
          hour: '21',
          minute: '30',
          durationMinutes: 8,
          maxRainMm: 3.5,
          currentRainMm: 2.8,
          enabled: true,
        ),
        ScheduleProgram(
          id: 19,
          zone: zones[2],
          month: '4-10',
          dayOfMonth: '*/2',
          dayOfWeek: '*',
          hour: '5',
          minute: '45',
          durationMinutes: 15,
          maxRainMm: 6,
          currentRainMm: 2.8,
          enabled: false,
        ),
      ],
      manualPrograms: [
        ManualProgram(
          id: 1,
          name: 'Scurt',
          zoneDurations: {zones[0]: 5, zones[1]: 4, zones[2]: 4, zones[3]: 0},
        ),
        ManualProgram(
          id: 2,
          name: 'Normal',
          zoneDurations: {zones[0]: 12, zones[1]: 8, zones[2]: 15, zones[3]: 6},
        ),
        ManualProgram(
          id: 3,
          name: 'Intens',
          zoneDurations: {
            zones[0]: 18,
            zones[1]: 14,
            zones[2]: 20,
            zones[3]: 10,
          },
        ),
      ],
    );
  }
}
