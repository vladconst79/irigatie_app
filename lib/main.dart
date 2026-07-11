import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiSettings = await ApiSettings.load();
  runApp(IrrigationApp(apiSettings: apiSettings));
}

class ApiSettings {
  const ApiSettings({required this.apiUrl, required this.apiToken});

  static const _apiUrlKey = 'irigatie.apiUrl';
  static const _apiTokenKey = 'irigatie.apiToken';

  final String apiUrl;
  final String apiToken;

  static const fromEnvironment = ApiSettings(
    apiUrl: String.fromEnvironment('IRIGATIE_API_URL'),
    apiToken: String.fromEnvironment('IRIGATIE_API_TOKEN'),
  );

  static Future<ApiSettings> load() async {
    ApiSettings assetSettings;
    try {
      assetSettings = await _loadAsset();
    } catch (e) {
      // Fall back to an empty string so the URL resolves perfectly to '/api/snapshot'
      assetSettings = ApiSettings(apiUrl: '', apiToken: '');
    }

    final preferences = await SharedPreferences.getInstance();
    final savedApiUrl = preferences.getString(_apiUrlKey);
    final savedApiToken = preferences.getString(_apiTokenKey);

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
      );
    } catch (_) {
      return fromEnvironment;
    }
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_apiUrlKey, _trimTrailingSlash(apiUrl));
    await preferences.setString(_apiTokenKey, apiToken);
  }

  Future<void> clearSaved() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_apiUrlKey);
    await preferences.remove(_apiTokenKey);
  }
}

class IrrigationApp extends StatelessWidget {
  const IrrigationApp({
    super.key,
    this.initialSnapshot,
    this.apiSettings = ApiSettings.fromEnvironment,
  });

  final IrrigationSnapshot? initialSnapshot;
  final ApiSettings apiSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Irigatie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7C66),
          primary: const Color(0xFF0E7C66),
          secondary: const Color(0xFF3268A8),
          tertiary: const Color(0xFFD08B2F),
          surface: const Color(0xFFF7F8F5),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F1),
        fontFamily: 'Roboto',
      ),
      home: IrrigationHome(
        initialSnapshot: initialSnapshot,
        apiSettings: apiSettings,
      ),
    );
  }
}

class IrrigationHome extends StatefulWidget {
  const IrrigationHome({
    super.key,
    this.initialSnapshot,
    required this.apiSettings,
  });

  final IrrigationSnapshot? initialSnapshot;
  final ApiSettings apiSettings;

  @override
  State<IrrigationHome> createState() => _IrrigationHomeState();
}

class _IrrigationHomeState extends State<IrrigationHome> {
  static const _pollInterval = Duration(seconds: 3);

  int _selectedIndex = 0;
  late ApiSettings _apiSettings;
  late IrrigationDataClient _client;
  IrrigationSnapshot? _snapshot;
  String? _loadError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isStopping = false;
  int? _executingManualProgramId;
  int? _executingScheduleId;
  int? _testingZoneId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _apiSettings = widget.apiSettings;
    _client = IrrigationDataClient(apiSettings: _apiSettings);
    final initialSnapshot = widget.initialSnapshot;
    if (initialSnapshot != null) {
      _snapshot = initialSnapshot;
      _isLoading = false;
    } else {
      _loadSnapshot();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        if (_selectedIndex == 0) {
          _loadSnapshot(showLoading: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final destination = _destinations[_selectedIndex];
    final snapshot = _snapshot ?? IrrigationSnapshot.empty();

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              _DesktopNavigation(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectDestination,
              ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      title: destination.label,
                      snapshot: snapshot,
                      isLoading: _isLoading,
                      onRefresh: _loadSnapshot,
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 28 : 16,
                      8,
                      isWide ? 28 : 16,
                      28,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _ScreenBody(
                        selectedIndex: _selectedIndex,
                        snapshot: snapshot,
                        isLoading: _isLoading,
                        loadError: _loadError,
                        onRetry: _loadSnapshot,
                        executingManualProgramId: _executingManualProgramId,
                        onExecuteManualProgram: _executeManualProgram,
                        executingScheduleId: _executingScheduleId,
                        onExecuteSchedule: _executeSchedule,
                        onAddSchedule: _addSchedule,
                        onEditSchedule: _editSchedule,
                        onDeleteSchedule: _deleteSchedule,
                        onEditManualProgram: _editManualProgram,
                        testingZoneId: _testingZoneId,
                        onTestZone: _testZone,
                        onEditZone: _editZone,
                        isStopping: _isStopping,
                        onStop: _stopWatering,
                        onShowWateringHistory: _showWateringHistory,
                        apiSettings: _apiSettings,
                        onSaveApiSettings: _saveApiSettings,
                        onResetApiSettings: _resetApiSettings,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: _destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _showWateringHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WateringHistorySheet(client: _client),
    );
  }

  Future<void> _loadSnapshot({bool showLoading = true}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final snapshot = await _client.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _executeManualProgram(ManualProgram program) async {
    if (_executingManualProgramId != null) return;

    setState(() => _executingManualProgramId = program.id);
    try {
      final command = await _client.executeManualProgram(program.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trimis: ${command.command}')));
      await _loadSnapshot();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Executia a esuat: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _executingManualProgramId = null);
      }
    }
  }

  Future<void> _executeSchedule(ScheduleProgram schedule) async {
    if (_executingScheduleId != null) return;

    setState(() => _executingScheduleId = schedule.id);
    try {
      final command = await _client.executeSchedule(schedule.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trimis: ${command.command}')));
      await _loadSnapshot();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Executia a esuat: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _executingScheduleId = null);
      }
    }
  }

  Future<void> _addSchedule() async {
    final snapshot = _snapshot ?? IrrigationSnapshot.empty();
    final request = await showDialog<ScheduleWriteRequest>(
      context: context,
      builder: (context) => ScheduleDialog(zones: snapshot.zones),
    );
    if (request == null) return;
    await _runWrite(
      () => _client.createSchedule(request),
      successMessage: 'Programarea a fost adaugata',
      errorPrefix: 'Adaugarea programarii a esuat',
    );
  }

  Future<void> _editSchedule(ScheduleProgram schedule) async {
    final snapshot = _snapshot ?? IrrigationSnapshot.empty();
    final request = await showDialog<ScheduleWriteRequest>(
      context: context,
      builder: (context) =>
          ScheduleDialog(zones: snapshot.zones, schedule: schedule),
    );
    if (request == null) return;
    await _runWrite(
      () => _client.updateSchedule(schedule.id, request),
      successMessage: 'Programarea a fost salvata',
      errorPrefix: 'Salvarea programarii a esuat',
    );
  }

  Future<void> _deleteSchedule(ScheduleProgram schedule) async {
    final confirmed = await _confirmDelete(
      title: 'Stergi programarea?',
      message:
          'Programarea #${schedule.id} pentru ${schedule.zone.name} va fi stearsa.',
    );
    if (!confirmed) return;
    await _runWrite(
      () => _client.deleteSchedule(schedule.id),
      successMessage: 'Programarea a fost stearsa',
      errorPrefix: 'Stergerea programarii a esuat',
    );
  }

  Future<void> _editManualProgram(ManualProgram program) async {
    final snapshot = _snapshot ?? IrrigationSnapshot.empty();
    final request = await showDialog<ManualProgramWriteRequest>(
      context: context,
      builder: (context) =>
          ManualProgramDialog(zones: snapshot.zones, program: program),
    );
    if (request == null) return;
    await _runWrite(
      () => _client.updateManualProgram(program.id, request),
      successMessage: 'Programul manual a fost salvat',
      errorPrefix: 'Salvarea programului manual a esuat',
    );
  }

  Future<void> _testZone(IrrigationZone zone) async {
    if (_testingZoneId != null) return;

    setState(() => _testingZoneId = zone.id);
    try {
      final command = await _client.executeZoneTest(zone.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trimis: ${command.command}')));
      await _loadSnapshot();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Testul a esuat: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testingZoneId = null);
      }
    }
  }

  Future<void> _editZone(IrrigationZone zone) async {
    final request = await showDialog<ZoneWriteRequest>(
      context: context,
      builder: (context) => ZoneDialog(zone: zone),
    );
    if (request == null) return;
    await _runWrite(
      () => _client.updateZone(zone.id, request),
      successMessage: 'Traseul a fost salvat',
      errorPrefix: 'Salvarea traseului a esuat',
    );
  }

  Future<void> _stopWatering() async {
    if (_isStopping) return;

    setState(() => _isStopping = true);
    try {
      final command = await _client.stopWatering();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trimis: ${command.command}')));
      await _loadSnapshot();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stop a esuat: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isStopping = false);
      }
    }
  }

  Future<void> _saveApiSettings(ApiSettings settings) async {
    final updated = ApiSettings(
      apiUrl: _trimTrailingSlash(settings.apiUrl),
      apiToken: settings.apiToken,
    );
    await updated.save();
    _client.close();
    _client = IrrigationDataClient(apiSettings: updated);
    if (!mounted) return;
    setState(() {
      _apiSettings = updated;
      _snapshot = null;
      _loadError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuratia a fost salvata')),
    );
    await _loadSnapshot();
  }

  Future<void> _resetApiSettings() async {
    await _apiSettings.clearSaved();
    final loaded = await ApiSettings.load();
    _client.close();
    _client = IrrigationDataClient(apiSettings: loaded);
    if (!mounted) return;
    setState(() {
      _apiSettings = loaded;
      _snapshot = null;
      _loadError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuratia a fost resetata')),
    );
    await _loadSnapshot();
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuleaza'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sterge'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runWrite(
    Future<WriteResult> Function() action, {
    required String successMessage,
    required String errorPrefix,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _loadSnapshot();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$errorPrefix: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _ScreenBody extends StatelessWidget {
  const _ScreenBody({
    required this.selectedIndex,
    required this.snapshot,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
    required this.executingManualProgramId,
    required this.onExecuteManualProgram,
    required this.executingScheduleId,
    required this.onExecuteSchedule,
    required this.onAddSchedule,
    required this.onEditSchedule,
    required this.onDeleteSchedule,
    required this.onEditManualProgram,
    required this.testingZoneId,
    required this.onTestZone,
    required this.onEditZone,
    required this.isStopping,
    required this.onStop,
    required this.onShowWateringHistory,
    required this.apiSettings,
    required this.onSaveApiSettings,
    required this.onResetApiSettings,
  });

  final int selectedIndex;
  final IrrigationSnapshot snapshot;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;
  final int? executingManualProgramId;
  final ValueChanged<ManualProgram> onExecuteManualProgram;
  final int? executingScheduleId;
  final ValueChanged<ScheduleProgram> onExecuteSchedule;
  final VoidCallback onAddSchedule;
  final ValueChanged<ScheduleProgram> onEditSchedule;
  final ValueChanged<ScheduleProgram> onDeleteSchedule;
  final ValueChanged<ManualProgram> onEditManualProgram;
  final int? testingZoneId;
  final ValueChanged<IrrigationZone> onTestZone;
  final ValueChanged<IrrigationZone> onEditZone;
  final bool isStopping;
  final VoidCallback onStop;
  final VoidCallback onShowWateringHistory;
  final ApiSettings apiSettings;
  final ValueChanged<ApiSettings> onSaveApiSettings;
  final VoidCallback onResetApiSettings;

  @override
  Widget build(BuildContext context) {
    if (selectedIndex == 4) {
      return ConfigurationScreen(
        settings: apiSettings,
        onSave: onSaveApiSettings,
        onReset: onResetApiSettings,
      );
    }

    if (isLoading && snapshot.zones.isEmpty) {
      return const _LoadingState();
    }

    final error = loadError;
    if (error != null && snapshot.zones.isEmpty) {
      return _ErrorState(message: error, onRetry: onRetry);
    }

    return switch (selectedIndex) {
      0 => DashboardScreen(
        snapshot: snapshot,
        isStopping: isStopping,
        onStop: onStop,
        onShowWateringHistory: onShowWateringHistory,
      ),
      1 => ScheduleScreen(
        snapshot: snapshot,
        executingScheduleId: executingScheduleId,
        onExecuteSchedule: onExecuteSchedule,
        onAddSchedule: onAddSchedule,
        onEditSchedule: onEditSchedule,
        onDeleteSchedule: onDeleteSchedule,
      ),
      2 => ManualScreen(
        snapshot: snapshot,
        executingProgramId: executingManualProgramId,
        onExecuteProgram: onExecuteManualProgram,
        onEditProgram: onEditManualProgram,
      ),
      3 => ZonesScreen(
        snapshot: snapshot,
        testingZoneId: testingZoneId,
        onTestZone: onTestZone,
        onEditZone: onEditZone,
      ),
      _ => DashboardScreen(
        snapshot: snapshot,
        isStopping: isStopping,
        onStop: onStop,
        onShowWateringHistory: onShowWateringHistory,
      ),
    };
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.snapshot,
    required this.isStopping,
    required this.onStop,
    required this.onShowWateringHistory,
  });

  final IrrigationSnapshot snapshot;
  final bool isStopping;
  final VoidCallback onStop;
  final VoidCallback onShowWateringHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResponsiveGrid(
          minTileWidth: 220,
          children: [
            _MetricTile(
              icon: Icons.power_settings_new_rounded,
              title: 'Daemon',
              value: snapshot.daemonState.label,
              detail: snapshot.runtimeMessage,
              tone: snapshot.daemonState.tone,
            ),
            _MetricTile(
              icon: Icons.water_drop_rounded,
              title: 'Program curent',
              value: snapshot.currentProgram ?? 'In asteptare',
              detail: '${snapshot.remainingLabel} · istoric udari',
              tone: _Tone.blue,
              onTap: onShowWateringHistory,
            ),
            _RainfallMetricTile(rainfall: snapshot.rainfall24h),
            _MetricTile(
              icon: Icons.queue_rounded,
              title: 'Coada',
              value:
                  '${snapshot.pendingCommands}/${snapshot.maxPendingCommands}',
              detail: 'comenzi in asteptare',
              tone: _Tone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 960;
            final children = [
              _Panel(
                title: 'Relee si zone',
                child: _RelayList(
                  transformerRelay: snapshot.transformerRelay,
                  zones: snapshot.zones,
                ),
              ),
              _Panel(
                title: 'Runtime',
                action: FilledButton.tonalIcon(
                  onPressed: isStopping ? null : onStop,
                  icon: isStopping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle_outlined),
                  label: Text(isStopping ? 'Stop...' : 'Stop'),
                ),
                child: _RuntimeDetails(snapshot: snapshot),
              ),
            ];

            if (!twoColumns) {
              return Column(
                children: [
                  children[0],
                  const SizedBox(height: 18),
                  children[1],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 18),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WateringHistorySheet extends StatefulWidget {
  const _WateringHistorySheet({required this.client});

  final IrrigationDataClient client;

  @override
  State<_WateringHistorySheet> createState() => _WateringHistorySheetState();
}

class _WateringHistorySheetState extends State<_WateringHistorySheet> {
  final _items = <WateringHistoryItem>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int? _nextBeforeId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_isLoadingMore) return;
    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await widget.client.fetchWateringHistory(
        beforeId: reset ? null : _nextBeforeId,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _nextBeforeId = page.nextBeforeId;
        _hasMore = page.hasMore && page.nextBeforeId != null;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Istoric udari',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : () => _load(reset: true),
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Inchide',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Istoricul nu poate fi incarcat.',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(child: Text('Nu exista evenimente de udare.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Center(
            child: FilledButton.tonalIcon(
              onPressed: _isLoadingMore ? null : () => _load(reset: false),
              icon: _isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                _isLoadingMore ? 'Se incarca...' : 'Incarca mai multe',
              ),
            ),
          );
        }

        return _WateringHistoryRow(item: _items[index]);
      },
    );
  }
}

class _WateringHistoryRow extends StatelessWidget {
  const _WateringHistoryRow({required this.item});

  final WateringHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = item.zoneLabel;
    final subtitle = [
      item.programLabel,
      item.source,
      item.startedAt,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _HistoryResultChip(item.result),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                Icons.timer_rounded,
                'real ${_formatSeconds(item.actualSeconds)}',
              ),
              _InfoChip(
                Icons.schedule_rounded,
                'plan ${_formatSeconds(item.plannedSeconds)}',
              ),
              _InfoChip(
                Icons.water_drop_rounded,
                'ploaie ${_formatMillimeters(item.rainCreditMm)}',
              ),
            ],
          ),
          if (item.error != null && item.error!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryResultChip extends StatelessWidget {
  const _HistoryResultChip(this.result);

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'completed' || 'test_completed' => const Color(0xFF0E7C66),
      'interrupted' || 'test_interrupted' => const Color(0xFFD08B2F),
      'skipped_rain' ||
      'skipped_inactive' ||
      'skipped_disabled' => const Color(0xFF747A83),
      _ => Theme.of(context).colorScheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Se incarca datele',
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Conectare la API si MariaDB...')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Date indisponibile',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({
    super.key,
    required this.snapshot,
    required this.executingScheduleId,
    required this.onExecuteSchedule,
    required this.onAddSchedule,
    required this.onEditSchedule,
    required this.onDeleteSchedule,
  });

  final IrrigationSnapshot snapshot;
  final int? executingScheduleId;
  final ValueChanged<ScheduleProgram> onExecuteSchedule;
  final VoidCallback onAddSchedule;
  final ValueChanged<ScheduleProgram> onEditSchedule;
  final ValueChanged<ScheduleProgram> onDeleteSchedule;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Programari automate',
      action: Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onAddSchedule,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adauga'),
          ),
        ],
      ),
      child: Column(
        children: snapshot.schedules
            .map(
              (schedule) => _ScheduleRow(
                schedule: schedule,
                isExecuting: executingScheduleId == schedule.id,
                onExecute: () => onExecuteSchedule(schedule),
                onEdit: () => onEditSchedule(schedule),
                onDelete: () => onDeleteSchedule(schedule),
              ),
            )
            .toList(),
      ),
    );
  }
}

class ManualScreen extends StatelessWidget {
  const ManualScreen({
    super.key,
    required this.snapshot,
    required this.executingProgramId,
    required this.onExecuteProgram,
    required this.onEditProgram,
  });

  final IrrigationSnapshot snapshot;
  final int? executingProgramId;
  final ValueChanged<ManualProgram> onExecuteProgram;
  final ValueChanged<ManualProgram> onEditProgram;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveGrid(
      minTileWidth: 320,
      children: snapshot.manualPrograms
          .map(
            (program) => _ManualProgramCard(
              program: program,
              isExecuting: executingProgramId == program.id,
              onExecute: () => onExecuteProgram(program),
              onEdit: () => onEditProgram(program),
            ),
          )
          .toList(),
    );
  }
}

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({
    super.key,
    required this.snapshot,
    required this.testingZoneId,
    required this.onTestZone,
    required this.onEditZone,
  });

  final IrrigationSnapshot snapshot;
  final int? testingZoneId;
  final ValueChanged<IrrigationZone> onTestZone;
  final ValueChanged<IrrigationZone> onEditZone;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Trasee',
      child: Column(
        children: snapshot.zones
            .map(
              (zone) => _ZoneEditorRow(
                zone: zone,
                isTesting: testingZoneId == zone.id,
                onTest: () => onTestZone(zone),
                onEdit: () => onEditZone(zone),
              ),
            )
            .toList(),
      ),
    );
  }
}

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onReset,
  });

  final ApiSettings settings;
  final ValueChanged<ApiSettings> onSave;
  final VoidCallback onReset;

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiTokenController;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: widget.settings.apiUrl);
    _apiTokenController = TextEditingController(text: widget.settings.apiToken);
  }

  @override
  void didUpdateWidget(ConfigurationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.apiUrl != widget.settings.apiUrl) {
      _apiUrlController.text = widget.settings.apiUrl;
    }
    if (oldWidget.settings.apiToken != widget.settings.apiToken) {
      _apiTokenController.text = widget.settings.apiToken;
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Configuratie API',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: widget.onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Salveaza'),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                prefixIcon: Icon(Icons.link_rounded),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _apiTokenController,
              obscureText: !_showToken,
              decoration: InputDecoration(
                labelText: 'API token',
                prefixIcon: const Icon(Icons.key_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showToken = !_showToken),
                  tooltip: _showToken ? 'Ascunde token' : 'Arata token',
                  icon: Icon(
                    _showToken
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    widget.onSave(
      ApiSettings(
        apiUrl: _apiUrlController.text,
        apiToken: _apiTokenController.text,
      ),
    );
  }
}

class ZoneDialog extends StatefulWidget {
  const ZoneDialog({super.key, this.zone});

  final IrrigationZone? zone;

  @override
  State<ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<ZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ZoneType _type;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final zone = widget.zone;
    _nameController = TextEditingController(text: zone?.name ?? '');
    _type = zone?.type ?? ZoneType.sprinkler;
    _enabled = zone?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.zone != null;

    return AlertDialog(
      title: Text(editing ? 'Editeaza traseu' : 'Adauga traseu'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nume',
                  prefixIcon: Icon(Icons.label_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: _requiredText,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<ZoneType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Tip',
                  prefixIcon: Icon(Icons.alt_route_rounded),
                  border: OutlineInputBorder(),
                ),
                items: ZoneType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _type = value ?? ZoneType.sprinkler),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activ'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuleaza'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Salveaza' : 'Adauga'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ZoneWriteRequest(
        name: _nameController.text.trim(),
        type: _type,
        enabled: _enabled,
      ),
    );
  }
}

class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({super.key, required this.zones, this.schedule});

  final List<IrrigationZone> zones;
  final ScheduleProgram? schedule;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _monthController;
  late final TextEditingController _dayOfMonthController;
  late final TextEditingController _dayOfWeekController;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  late final TextEditingController _durationController;
  late final TextEditingController _maxRainController;
  late int _zoneId;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _zoneId =
        schedule?.zone.id ?? (widget.zones.isEmpty ? 0 : widget.zones.first.id);
    _enabled = schedule?.enabled ?? true;
    _monthController = TextEditingController(text: schedule?.month ?? '*');
    _dayOfMonthController = TextEditingController(
      text: schedule?.dayOfMonth ?? '*',
    );
    _dayOfWeekController = TextEditingController(
      text: schedule?.dayOfWeek ?? '*',
    );
    _hourController = TextEditingController(text: schedule?.hour ?? '6');
    _minuteController = TextEditingController(text: schedule?.minute ?? '0');
    _durationController = TextEditingController(
      text: (schedule?.durationMinutes ?? 10).toString(),
    );
    _maxRainController = TextEditingController(
      text: (schedule?.maxRainMm ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _monthController.dispose();
    _dayOfMonthController.dispose();
    _dayOfWeekController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _durationController.dispose();
    _maxRainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.schedule != null;

    return AlertDialog(
      title: Text(editing ? 'Editeaza programare' : 'Adauga programare'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _zoneId == 0 ? null : _zoneId,
                  decoration: const InputDecoration(
                    labelText: 'Traseu',
                    prefixIcon: Icon(Icons.alt_route_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.zones
                      .map(
                        (zone) => DropdownMenuItem(
                          value: zone.id,
                          child: Text(zone.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _zoneId = value ?? 0),
                  validator: (value) =>
                      value == null ? 'Alege un traseu' : null,
                ),
                const SizedBox(height: 14),
                _TwoColumnFields(
                  children: [
                    _textField(
                      _monthController,
                      'Luna',
                      Icons.calendar_view_month_rounded,
                    ),
                    _textField(
                      _dayOfMonthController,
                      'Zi luna',
                      Icons.today_rounded,
                    ),
                    _textField(
                      _dayOfWeekController,
                      'Zi saptamana',
                      Icons.date_range_rounded,
                    ),
                    _textField(_hourController, 'Ora', Icons.schedule_rounded),
                    _textField(
                      _minuteController,
                      'Minut',
                      Icons.more_time_rounded,
                    ),
                    TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(
                        labelText: 'Durata minute',
                        prefixIcon: Icon(Icons.timer_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => _positiveInt(value, max: 120),
                    ),
                    TextFormField(
                      controller: _maxRainController,
                      decoration: const InputDecoration(
                        labelText: 'Ploaie max mm',
                        prefixIcon: Icon(Icons.cloudy_snowing),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: _nonNegativeDouble,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activ'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuleaza'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Salveaza' : 'Adauga'),
        ),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: _requiredText,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ScheduleWriteRequest(
        zoneId: _zoneId,
        month: _monthController.text.trim(),
        dayOfMonth: _dayOfMonthController.text.trim(),
        dayOfWeek: _dayOfWeekController.text.trim(),
        hour: _hourController.text.trim(),
        minute: _minuteController.text.trim(),
        durationMinutes: int.parse(_durationController.text.trim()),
        maxRainMm: double.parse(_maxRainController.text.trim()),
        enabled: _enabled,
      ),
    );
  }
}

class ManualProgramDialog extends StatefulWidget {
  const ManualProgramDialog({super.key, required this.zones, this.program});

  final List<IrrigationZone> zones;
  final ManualProgram? program;

  @override
  State<ManualProgramDialog> createState() => _ManualProgramDialogState();
}

class _ManualProgramDialogState extends State<ManualProgramDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final Map<int, TextEditingController> _durationControllers;

  @override
  void initState() {
    super.initState();
    final program = widget.program;
    _nameController = TextEditingController(text: program?.name ?? '');
    final existingDurations = {
      for (final entry
          in program?.zoneDurations.entries ??
              const <MapEntry<IrrigationZone, int>>[])
        entry.key.id: entry.value,
    };
    _durationControllers = {
      for (final zone in widget.zones)
        zone.id: TextEditingController(
          text: (existingDurations[zone.id] ?? 0).toString(),
        ),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _durationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.program != null;

    return AlertDialog(
      title: Text(
        editing ? 'Editeaza program manual' : 'Adauga program manual',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nume',
                    prefixIcon: Icon(Icons.label_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredText,
                ),
                const SizedBox(height: 14),
                ...widget.zones.map(
                  (zone) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _durationControllers[zone.id],
                      decoration: InputDecoration(
                        labelText: '${zone.name} minute',
                        prefixIcon: Icon(zone.icon),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => _nonNegativeInt(value, max: 120),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuleaza'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Salveaza' : 'Adauga'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ManualProgramWriteRequest(
        name: _nameController.text.trim(),
        zoneDurations: {
          for (final entry in _durationControllers.entries)
            entry.key: int.parse(entry.value.text.trim()),
        },
      ),
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map(
                (child) => SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.snapshot,
    required this.isLoading,
    required this.onRefresh,
  });

  final String title;
  final IrrigationSnapshot snapshot;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Irigatie',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: isLoading ? null : onRefresh,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              _StatusPill(
                icon: Icons.dns_rounded,
                label: 'Gateway',
                value: snapshot.gatewayOnline ? 'online' : 'offline',
                active: snapshot.gatewayOnline,
              ),
              _StatusPill(
                icon: Icons.storage_rounded,
                label: 'DB',
                value: snapshot.databaseOk ? 'ok' : 'eroare',
                active: snapshot.databaseOk,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      color: Theme.of(context).colorScheme.surface,
      child: NavigationRail(
        extended: true,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          child: Row(
            children: [
              const Icon(Icons.water_drop_rounded, size: 30),
              const SizedBox(width: 10),
              Text(
                'Controller',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        destinations: _destinations
            .map(
              (item) => NavigationRailDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: Text(item.label),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                ?action,
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.tone,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final _Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone.color(context);

    final borderRadius = BorderRadius.circular(8);
    final child = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              if (onTap != null) ...[
                const Spacer(),
                Icon(Icons.history_rounded, color: color, size: 22),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );

    final tile = Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 148),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) return tile;

    return Tooltip(message: 'Istoric udari', child: tile);
  }
}

class _RainfallMetricTile extends StatelessWidget {
  const _RainfallMetricTile({required this.rainfall});

  final Rainfall24h rainfall;

  @override
  Widget build(BuildContext context) {
    final color = _Tone.amber.color(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final valueStyle = textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final labelStyle = textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.cloudy_snowing, color: color, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ploaie 24h',
                style: textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _RainfallSourceValue(
                      label: 'Open-Meteo',
                      value: rainfall.openMeteoLabel,
                      valueStyle: valueStyle,
                      labelStyle: labelStyle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _RainfallSourceValue(
                      label: 'Hardware',
                      value: rainfall.hardwareLabel,
                      valueStyle: valueStyle,
                      labelStyle: labelStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RainfallSourceValue extends StatelessWidget {
  const _RainfallSourceValue({
    required this.label,
    required this.value,
    required this.valueStyle,
    required this.labelStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: valueStyle,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
      ],
    );
  }
}

class _RelayList extends StatelessWidget {
  const _RelayList({required this.transformerRelay, required this.zones});

  final RelayStatus? transformerRelay;
  final List<IrrigationZone> zones;

  @override
  Widget build(BuildContext context) {
    final transformer = transformerRelay;

    return Column(
      children: [
        _RelayRow(
          name: 'Transformator',
          icon: Icons.electrical_services_rounded,
          active: transformer?.active,
          value: transformer?.value,
        ),
        ...zones.map(
          (zone) => _RelayRow(
            name: zone.name,
            icon: zone.type == ZoneType.sprinkler
                ? Icons.water_rounded
                : Icons.grass_rounded,
            active: zone.relayActive,
            value: zone.relayValue,
          ),
        ),
      ],
    );
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({
    required this.name,
    required this.icon,
    required this.active,
    required this.value,
  });

  final String name;
  final IconData icon;
  final bool? active;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final isActive = active ?? false;

    return ListTile(
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text('GPIO value ${_formatRelayValue(value)}'),
      trailing: _StateChip(
        active == null ? 'necunoscut' : (isActive ? 'activ' : 'oprit'),
        isActive,
      ),
    );
  }
}

class _RuntimeDetails extends StatelessWidget {
  const _RuntimeDetails({required this.snapshot});

  final IrrigationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _DetailLine('Sursa', snapshot.runtimeSource),
          _DetailLine('Comanda', snapshot.runtimeCommand),
          _DetailLine('Program', snapshot.currentProgram ?? 'N/A'),
          _DetailLine('Traseu', snapshot.currentZone ?? 'N/A'),
          _DetailLine('Heartbeat', snapshot.heartbeatAt),
          _DetailLine('Socket', snapshot.socketPath),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
    required this.isExecuting,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleProgram schedule;
  final bool isExecuting;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = schedule.enabled && schedule.zone.enabled;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled
            ? null
            : colors.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;

              final summary = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StateChip(enabled ? 'activ' : 'inactiv', enabled),
                  _InfoChip(
                    Icons.calendar_view_month_rounded,
                    schedule.monthLabel,
                  ),
                  _InfoChip(Icons.calendar_month_rounded, schedule.cronLabel),
                  _InfoChip(
                    Icons.timer_rounded,
                    '${schedule.durationMinutes} min',
                  ),
                  _InfoChip(
                    Icons.cloudy_snowing,
                    'max ${schedule.maxRainMm.toStringAsFixed(1)} mm',
                  ),
                  _InfoChip(
                    Icons.water_drop_outlined,
                    '${schedule.currentRainMm.toStringAsFixed(1)} mm',
                  ),
                ],
              );

              final actions = Wrap(
                spacing: 8,
                children: [
                  IconButton.filledTonal(
                    onPressed: onEdit,
                    tooltip: 'Editeaza',
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton.filledTonal(
                    onPressed: onDelete,
                    tooltip: 'Sterge',
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  IconButton.filled(
                    onPressed: enabled && !isExecuting ? onExecute : null,
                    tooltip: 'Executa acum',
                    icon: isExecuting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ScheduleTitle(schedule: schedule),
                    const SizedBox(height: 12),
                    summary,
                    const SizedBox(height: 12),
                    actions,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: _ScheduleTitle(schedule: schedule)),
                  Expanded(flex: 4, child: summary),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScheduleTitle extends StatelessWidget {
  const _ScheduleTitle({required this.schedule});

  final ScheduleProgram schedule;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: schedule.zone.color.withValues(alpha: 0.16),
          child: Icon(schedule.zone.icon, color: schedule.zone.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                schedule.zone.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('Program #${schedule.id}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManualProgramCard extends StatelessWidget {
  const _ManualProgramCard({
    required this.program,
    required this.isExecuting,
    required this.onExecute,
    required this.onEdit,
  });

  final ManualProgram program;
  final bool isExecuting;
  final VoidCallback onExecute;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  program.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: onEdit,
                tooltip: 'Editeaza',
                icon: const Icon(Icons.edit_rounded),
              ),
              FilledButton.icon(
                onPressed: isExecuting ? null : onExecute,
                icon: isExecuting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(isExecuting ? 'Trimit' : 'Executa'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...program.zoneDurations.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DurationBar(zone: entry.key, minutes: entry.value),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationBar extends StatelessWidget {
  const _DurationBar({required this.zone, required this.minutes});

  final IrrigationZone zone;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = 20;
    final fraction = (minutes / maxMinutes).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(zone.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: fraction,
              color: zone.color,
              backgroundColor: zone.color.withValues(alpha: 0.12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            '$minutes min',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ZoneEditorRow extends StatelessWidget {
  const _ZoneEditorRow({
    required this.zone,
    required this.isTesting,
    required this.onTest,
    required this.onEdit,
  });

  final IrrigationZone zone;
  final bool isTesting;
  final VoidCallback onTest;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: zone.enabled
            ? null
            : colors.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Opacity(
        opacity: zone.enabled ? 1 : 0.62,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: zone.color.withValues(alpha: 0.16),
            child: Icon(zone.icon, color: zone.color),
          ),
          title: Text(zone.name),
          subtitle: Text(zone.type.label),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StateChip(zone.enabled ? 'activ' : 'inactiv', zone.enabled),
              IconButton.filled(
                onPressed: zone.enabled && !isTesting ? onTest : null,
                tooltip: 'Testeaza zona',
                icon: isTesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
              ),
              IconButton.filledTonal(
                onPressed: onEdit,
                tooltip: 'Editeaza',
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF0E7C66) : const Color(0xFFB54747);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text('$label $value', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.label, this.active);

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF0E7C66) : const Color(0xFF747A83);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, required this.minTileWidth});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: minTileWidth >= 300 ? 260 : 178,
          ),
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}

enum _Tone { green, blue, amber, red, neutral }

extension on _Tone {
  Color color(BuildContext context) {
    return switch (this) {
      _Tone.green => const Color(0xFF0E7C66),
      _Tone.blue => const Color(0xFF3268A8),
      _Tone.amber => const Color(0xFFD08B2F),
      _Tone.red => const Color(0xFFB54747),
      _Tone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

class _DestinationItem {
  const _DestinationItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _DestinationItem('Status', Icons.dashboard_outlined, Icons.dashboard_rounded),
  _DestinationItem(
    'Programari',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
  ),
  _DestinationItem(
    'Manual',
    Icons.play_circle_outline_rounded,
    Icons.play_circle_rounded,
  ),
  _DestinationItem('Trasee', Icons.alt_route_outlined, Icons.alt_route_rounded),
  _DestinationItem(
    'Configuratie',
    Icons.settings_outlined,
    Icons.settings_rounded,
  ),
];

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

class IrrigationDataClient {
  IrrigationDataClient({
    http.Client? httpClient,
    ApiSettings apiSettings = ApiSettings.fromEnvironment,
  }) : _httpClient = httpClient ?? http.Client(),
       apiBaseUrl = _trimTrailingSlash(apiSettings.apiUrl),
       apiToken = apiSettings.apiToken;

  final http.Client _httpClient;
  final String apiBaseUrl;
  final String apiToken;

  void close() {
    _httpClient.close();
  }

  Future<IrrigationSnapshot> fetchSnapshot() async {
    final uri = _apiUri('/api/snapshot');
    final response = await _httpClient.get(uri, headers: _headers());
    final decoded = _decodeApiObject(response, allowApplicationError: true);
    final status = await _fetchStatusOrNull();

    return IrrigationSnapshot.fromJson(decoded, statusJson: status);
  }

  Future<Map<String, dynamic>?> _fetchStatusOrNull() async {
    try {
      final uri = _apiUri('/api/status');
      final response = await _httpClient.get(uri, headers: _headers());
      return _decodeApiObject(response);
    } catch (_) {
      return null;
    }
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
    final response = await _httpClient.get(uri, headers: _headers());
    final decoded = _decodeApiObject(response);

    return WateringHistoryPage.fromJson(decoded);
  }

  Future<CommandResult> executeManualProgram(int programId) async {
    final uri = _apiUri('/api/manual/execute');
    final response = await _httpClient.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode({'program_id': programId}),
    );
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> executeZoneTest(int zoneId) async {
    final uri = _apiUri('/api/zones/test');
    final response = await _httpClient.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode({'zone_id': zoneId}),
    );
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> stopWatering() async {
    final uri = _apiUri('/api/stop');
    final response = await _httpClient.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, Object?>{}),
    );
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Future<CommandResult> executeSchedule(int scheduleId) async {
    final uri = _apiUri('/api/schedules/$scheduleId/execute');
    final response = await _httpClient.post(uri, headers: _headers());
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
    final response = await _httpClient.post(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    final decoded = _decodeApiObject(response);

    return WriteResult.fromJson(decoded);
  }

  Future<WriteResult> _patchWrite(
    String path,
    Map<String, Object?> body,
  ) async {
    final uri = _apiUri(path);
    final response = await _httpClient.patch(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(body),
    );
    final decoded = _decodeApiObject(response);

    return WriteResult.fromJson(decoded);
  }

  Future<WriteResult> _deleteWrite(String path) async {
    final uri = _apiUri(path);
    final response = await _httpClient.delete(uri, headers: _headers());
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
      transformerRelay: null,
      zones: [],
      schedules: [],
      manualPrograms: [],
    );
  }

  factory IrrigationSnapshot.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? statusJson,
  }) {
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
    final rawStatusDaemon = _asMap(statusJson?['daemon']);
    final rawRelayState = _asMap(rawStatusDaemon['relay_state']);
    final rawTransformerRelay = _asMap(rawRelayState['transformer']);
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

String? _requiredText(String? value) {
  return value == null || value.trim().isEmpty ? 'Camp obligatoriu' : null;
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
