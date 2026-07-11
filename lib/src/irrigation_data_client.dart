part of '../main.dart';

class IrrigationDataClient {
  IrrigationDataClient({
    http.Client? httpClient,
    ApiSettings apiSettings = ApiSettings.fromEnvironment,
  }) : _httpClient = httpClient ?? http.Client(),
       apiBaseUrl = _trimTrailingSlash(apiSettings.apiUrl),
       apiToken = apiSettings.apiToken,
       readTimeout = apiSettings.readTimeout,
       writeTimeout = apiSettings.writeTimeout;

  final http.Client _httpClient;
  final String apiBaseUrl;
  final String apiToken;
  final Duration readTimeout;
  final Duration writeTimeout;

  void close() {
    _httpClient.close();
  }

  Future<IrrigationSnapshot> fetchSnapshot() async {
    final uri = _apiUri('/api/snapshot');
    final response = await _httpClient
        .get(uri, headers: _headers())
        .timeout(readTimeout);
    final decoded = _decodeApiObject(response, allowApplicationError: true);

    return IrrigationSnapshot.fromJson(decoded);
  }

  Future<WateringHistoryPage> fetchWateringHistory({
    int limit = 50,
    int? beforeId,
  }) async {
    final uri = _apiUri(
      '/api/watering-history',
      queryParameters: {
        'limit': limit.toString(),
        if (beforeId != null) 'before_id': beforeId.toString(),
      },
    );
    final response = await _httpClient
        .get(uri, headers: _headers())
        .timeout(readTimeout);
    final decoded = _decodeApiObject(response);

    return WateringHistoryPage.fromJson(decoded);
  }

  Future<CommandResult> executeManualProgram(int programId) async {
    final uri = _apiUri('/api/manual/execute');
    final response = await _httpClient
        .post(
          uri,
          headers: _headers(contentTypeJson: true),
          body: jsonEncode({'program_id': programId}),
        )
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> executeZoneTest(int zoneId) async {
    final uri = _apiUri('/api/zones/test');
    final response = await _httpClient
        .post(
          uri,
          headers: _headers(contentTypeJson: true),
          body: jsonEncode({'zone_id': zoneId}),
        )
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> stopWatering() async {
    final uri = _apiUri('/api/stop');
    final response = await _httpClient
        .post(
          uri,
          headers: _headers(contentTypeJson: true),
          body: jsonEncode(<String, Object?>{}),
        )
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> executeSchedule(int scheduleId) async {
    final uri = _apiUri('/api/schedules/$scheduleId/execute');
    final response = await _httpClient
        .post(uri, headers: _headers())
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<WriteResult> updateZone(int zoneId, ZoneWriteRequest request) {
    return _patchWrite('/api/zones/$zoneId', request.toJson());
  }

  Future<WriteResult> createSchedule(ScheduleWriteRequest request) {
    return _postWrite('/api/schedules', request.toJson());
  }

  Future<WriteResult> updateSchedule(
    int scheduleId,
    ScheduleWriteRequest request,
  ) {
    return _patchWrite('/api/schedules/$scheduleId', request.toJson());
  }

  Future<WriteResult> deleteSchedule(int scheduleId) {
    return _deleteWrite('/api/schedules/$scheduleId');
  }

  Future<WriteResult> updateManualProgram(
    int programId,
    ManualProgramWriteRequest request,
  ) {
    return _patchWrite('/api/manual/$programId', request.toJson());
  }

  Future<WriteResult> _postWrite(String path, Map<String, Object?> body) async {
    final uri = _apiUri(path);
    final response = await _httpClient
        .post(
          uri,
          headers: _headers(contentTypeJson: true),
          body: jsonEncode(body),
        )
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return WriteResult.fromJson(decoded);
  }

  Future<WriteResult> _patchWrite(
    String path,
    Map<String, Object?> body,
  ) async {
    final uri = _apiUri(path);
    final response = await _httpClient
        .patch(
          uri,
          headers: _headers(contentTypeJson: true),
          body: jsonEncode(body),
        )
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return WriteResult.fromJson(decoded);
  }

  Future<WriteResult> _deleteWrite(String path) async {
    final uri = _apiUri(path);
    final response = await _httpClient
        .delete(uri, headers: _headers())
        .timeout(writeTimeout);
    final decoded = _decodeApiObject(response);

    return WriteResult.fromJson(decoded);
  }

  Uri _apiUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    if (apiBaseUrl.isEmpty) {
      return Uri.parse(
        normalizedPath,
      ).replace(queryParameters: queryParameters);
    }

    final base = Uri.parse(apiBaseUrl);
    final basePath = _trimTrailingSlash(base.path);
    final endpointPath =
        basePath.endsWith('/api') && normalizedPath.startsWith('/api/')
        ? '$basePath${normalizedPath.substring('/api'.length)}'
        : '$basePath$normalizedPath';

    return base.replace(path: endpointPath, queryParameters: queryParameters);
  }

  Map<String, dynamic> _decodeApiObject(
    http.Response response, {
    bool allowApplicationError = false,
  }) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('API response must be a JSON object');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (!allowApplicationError && decoded['ok'] == false)) {
      throw StateError(
        _asString(
          decoded['error'],
          fallback: 'API ${response.statusCode}: ${response.body}',
        ),
      );
    }

    return decoded;
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return {
      if (contentTypeJson) 'Content-Type': 'application/json',
      if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
    };
  }
}
