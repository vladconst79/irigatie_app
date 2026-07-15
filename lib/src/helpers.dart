part of '../main.dart';

const _zoneColors = [
  Color(0xFF0E7C66),
  Color(0xFF3268A8),
  Color(0xFFD08B2F),
  Color(0xFF7B5EA7),
  Color(0xFFB54747),
  Color(0xFF4E7A32),
];

IrrigationZone _unknownZone(int id) {
  return IrrigationZone(
    id: id,
    name: 'Traseu #$id',
    type: ZoneType.sprinkler,
    enabled: false,
    relayActive: false,
    relayValue: null,
    rainCreditMm: null,
    cyclesWithoutRain: null,
    rainStateUpdatedAt: null,
    lastRainEventId: null,
    color: _zoneColors[id.abs() % _zoneColors.length],
  );
}

DaemonState _daemonStateFromString(Object? value) {
  final text = _asString(value).toLowerCase();
  return DaemonState.values.firstWhere(
    (state) => state.label == text,
    orElse: () => DaemonState.unknown,
  );
}

ZoneType _zoneTypeFromDatabaseValue(Object? value) {
  final text = _asString(value).toLowerCase();
  return value == 2 || text == '2' || text == 'drip' || text == 'picurator'
      ? ZoneType.drip
      : ZoneType.sprinkler;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

int _validTimeoutSeconds(Object? value, {required int fallback}) {
  final seconds = _asInt(value, fallback: fallback);
  return seconds > 0 ? seconds : fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

bool? _nullableBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return null;
}

String _formatRelayValue(double? value) {
  if (value == null) return 'N/A';
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

String _formatManualProgramDuration(ManualProgram program) {
  final totalMinutes = program.zoneDurations.values.fold<int>(
    0,
    (sum, minutes) => sum + minutes,
  );
  final activeZones = program.zoneDurations.values
      .where((minutes) => minutes > 0)
      .length;

  if (activeZones == 0) return '0 min';
  final zoneLabel = activeZones == 1 ? '1 traseu' : '$activeZones trasee';
  return '$totalMinutes min pe $zoneLabel';
}

String _formatSeconds(double? value) {
  if (value == null) return 'N/A';
  if (value < 60) return '${value.round()} sec';
  final minutes = value / 60;
  if (minutes == minutes.roundToDouble()) {
    return '${minutes.round()} min';
  }
  return '${minutes.toStringAsFixed(1)} min';
}

String _formatMillimeters(double? value) {
  if (value == null) return 'N/A';
  return '${value.toStringAsFixed(1)} mm';
}

String _formatCyclesWithoutRain(int? value) {
  if (value == null) return 'N/A';
  if (value == 1) return '1 ciclu';
  return '$value cicluri';
}

String _formatRainStateUpdatedAt(String? value) {
  return value == null || value.isEmpty ? 'N/A' : value;
}

String? _requiredText(String? value) {
  return value == null || value.trim().isEmpty ? 'Camp obligatoriu' : null;
}

String? _scheduleField(
  String? value, {
  required int minimum,
  required int maximum,
  required String fieldName,
  bool allowStep = false,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Camp obligatoriu';
  if (text.length > 10) return 'Maxim 10 caractere';
  if (text == '*') return null;

  for (final rawPart in text.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) return '$fieldName contine o valoare goala';

    if (part.startsWith('*/')) {
      if (!allowStep) return '$fieldName nu accepta sintaxa cu pas';
      final step = int.tryParse(part.substring(2));
      if (step == null || step <= 0) return '$fieldName are pas invalid';
      continue;
    }

    final rangeMatch = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
    if (rangeMatch != null) {
      final start = int.parse(rangeMatch.group(1)!);
      final end = int.parse(rangeMatch.group(2)!);
      if (start < minimum ||
          start > maximum ||
          end < minimum ||
          end > maximum) {
        return '$fieldName trebuie sa fie intre $minimum si $maximum';
      }
      if (start > end) return '$fieldName are interval descrescator';
      continue;
    }

    final number = int.tryParse(part);
    if (number == null) return '$fieldName are sintaxa invalida';
    if (number < minimum || number > maximum) {
      return '$fieldName trebuie sa fie intre $minimum si $maximum';
    }
  }

  return null;
}

String? _positiveInt(String? value, {int? max}) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed <= 0) return 'Introdu un numar pozitiv';
  if (max != null && parsed > max) return 'Maxim $max';
  return null;
}

String? _nonNegativeInt(String? value, {int? max}) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 0) return 'Introdu zero sau mai mult';
  if (max != null && parsed > max) return 'Maxim $max';
  return null;
}

String? _nonNegativeDouble(String? value) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 0) return 'Introdu zero sau mai mult';
  return null;
}

String _trimTrailingSlash(String value) {
  var trimmed = value.trim();
  while (trimmed.endsWith('/') && trimmed.length > 1) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}
