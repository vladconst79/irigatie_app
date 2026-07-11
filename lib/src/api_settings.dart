part of '../main.dart';

class ApiSettings {
  const ApiSettings({
    required this.apiUrl,
    required this.apiToken,
    this.readTimeoutSeconds = defaultReadTimeoutSeconds,
    this.writeTimeoutSeconds = defaultWriteTimeoutSeconds,
  });

  static const _apiUrlKey = 'irigatie.apiUrl';
  static const _apiTokenKey = 'irigatie.apiToken';
  static const _readTimeoutSecondsKey = 'irigatie.readTimeoutSeconds';
  static const _writeTimeoutSecondsKey = 'irigatie.writeTimeoutSeconds';
  static const _secureStorage = FlutterSecureStorage();

  static const defaultReadTimeoutSeconds = 30;
  static const defaultWriteTimeoutSeconds = 60;

  final String apiUrl;
  final String apiToken;
  final int readTimeoutSeconds;
  final int writeTimeoutSeconds;

  static const fromEnvironment = ApiSettings(
    apiUrl: String.fromEnvironment('IRIGATIE_API_URL'),
    apiToken: String.fromEnvironment('IRIGATIE_API_TOKEN'),
    readTimeoutSeconds: int.fromEnvironment(
      'IRIGATIE_READ_TIMEOUT_SECONDS',
      defaultValue: defaultReadTimeoutSeconds,
    ),
    writeTimeoutSeconds: int.fromEnvironment(
      'IRIGATIE_WRITE_TIMEOUT_SECONDS',
      defaultValue: defaultWriteTimeoutSeconds,
    ),
  );

  static Future<ApiSettings> load() async {
    ApiSettings assetSettings;
    try {
      assetSettings = await _loadAsset();
    } catch (e) {
      // Fall back to an empty string so the URL resolves perfectly to '/api/snapshot'
      assetSettings = const ApiSettings(apiUrl: '', apiToken: '');
    }

    final preferences = await SharedPreferences.getInstance();
    final savedApiUrl = preferences.getString(_apiUrlKey);
    final savedApiToken = await _loadSavedToken(preferences);
    final savedReadTimeoutSeconds = preferences.getInt(_readTimeoutSecondsKey);
    final savedWriteTimeoutSeconds = preferences.getInt(
      _writeTimeoutSecondsKey,
    );

    // 1. Prioritize local storage if populated
    // 2. If empty, fall back to asset JSON
    // 3. Absolute ultimate fallback is an empty string ''
    String finalUrl = '';
    if (savedApiUrl != null && savedApiUrl.trim().isNotEmpty) {
      finalUrl = savedApiUrl;
    } else if (assetSettings.apiUrl.isNotEmpty) {
      finalUrl = assetSettings.apiUrl;
    }

    final finalToken =
        (savedApiToken != null && savedApiToken.trim().isNotEmpty)
        ? savedApiToken
        : assetSettings.apiToken;

    return ApiSettings(
      apiUrl: _trimTrailingSlash(finalUrl.trim()),
      apiToken: finalToken,
      readTimeoutSeconds: _validTimeoutSeconds(
        savedReadTimeoutSeconds ?? assetSettings.readTimeoutSeconds,
        fallback: defaultReadTimeoutSeconds,
      ),
      writeTimeoutSeconds: _validTimeoutSeconds(
        savedWriteTimeoutSeconds ?? assetSettings.writeTimeoutSeconds,
        fallback: defaultWriteTimeoutSeconds,
      ),
    );
  }

  static Future<ApiSettings> _loadAsset() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/config/irigatie_app.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return fromEnvironment;
      }

      return ApiSettings(
        apiUrl: _trimTrailingSlash(
          _asString(
            decoded['apiUrl'] ?? decoded['api_url'],
            fallback: fromEnvironment.apiUrl,
          ),
        ),
        apiToken: _asString(
          decoded['apiToken'] ?? decoded['api_token'],
          fallback: fromEnvironment.apiToken,
        ),
        readTimeoutSeconds: _validTimeoutSeconds(
          decoded['readTimeoutSeconds'] ?? decoded['read_timeout_seconds'],
          fallback: fromEnvironment.readTimeoutSeconds,
        ),
        writeTimeoutSeconds: _validTimeoutSeconds(
          decoded['writeTimeoutSeconds'] ?? decoded['write_timeout_seconds'],
          fallback: fromEnvironment.writeTimeoutSeconds,
        ),
      );
    } catch (_) {
      return fromEnvironment;
    }
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_apiUrlKey, _trimTrailingSlash(apiUrl));
    await _saveToken(preferences, apiToken);
    await preferences.setInt(
      _readTimeoutSecondsKey,
      _validTimeoutSeconds(
        readTimeoutSeconds,
        fallback: defaultReadTimeoutSeconds,
      ),
    );
    await preferences.setInt(
      _writeTimeoutSecondsKey,
      _validTimeoutSeconds(
        writeTimeoutSeconds,
        fallback: defaultWriteTimeoutSeconds,
      ),
    );
  }

  Future<void> clearSaved() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_apiUrlKey);
    await _clearSavedToken(preferences);
    await preferences.remove(_readTimeoutSecondsKey);
    await preferences.remove(_writeTimeoutSecondsKey);
  }

  Duration get readTimeout => Duration(seconds: readTimeoutSeconds);

  Duration get writeTimeout => Duration(seconds: writeTimeoutSeconds);

  static bool get _usesSecureTokenStorage {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  static Future<String?> _loadSavedToken(SharedPreferences preferences) async {
    final prefsToken = preferences.getString(_apiTokenKey);
    if (!_usesSecureTokenStorage) return prefsToken;

    final secureToken = await _secureStorage.read(key: _apiTokenKey);
    if (secureToken != null && secureToken.trim().isNotEmpty) {
      return secureToken;
    }

    if (prefsToken != null && prefsToken.trim().isNotEmpty) {
      await _secureStorage.write(key: _apiTokenKey, value: prefsToken);
      await preferences.remove(_apiTokenKey);
      return prefsToken;
    }

    return null;
  }

  static Future<void> _saveToken(
    SharedPreferences preferences,
    String token,
  ) async {
    if (!_usesSecureTokenStorage) {
      await preferences.setString(_apiTokenKey, token);
      return;
    }

    await _secureStorage.write(key: _apiTokenKey, value: token);
    await preferences.remove(_apiTokenKey);
  }

  static Future<void> _clearSavedToken(SharedPreferences preferences) async {
    await preferences.remove(_apiTokenKey);
    if (_usesSecureTokenStorage) {
      await _secureStorage.delete(key: _apiTokenKey);
    }
  }
}
