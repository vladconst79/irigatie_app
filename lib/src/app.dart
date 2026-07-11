part of '../main.dart';

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

class _IrrigationHomeState extends State<IrrigationHome>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _apiSettings = widget.apiSettings;
    _client = IrrigationDataClient(apiSettings: _apiSettings);
    final initialSnapshot = widget.initialSnapshot;
    if (initialSnapshot != null) {
      _snapshot = initialSnapshot;
      _isLoading = false;
    } else {
      _loadSnapshot();
    }
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _client.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      if (_selectedIndex == 0) {
        _loadSnapshot(showLoading: false);
      }
      return;
    }

    _stopPolling();
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

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_selectedIndex == 0) {
        _loadSnapshot(showLoading: false);
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
    final confirmed = await _confirmPhysicalAction(
      title: 'Executi programul manual?',
      message:
          'Programul "${program.name}" va porni udarea pentru ${_formatManualProgramDuration(program)}.',
      confirmLabel: 'Executa',
    );
    if (!confirmed) return;

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
    final confirmed = await _confirmPhysicalAction(
      title: 'Executi programarea acum?',
      message:
          '${schedule.zone.name} va porni pentru ${schedule.durationMinutes} min.',
      confirmLabel: 'Executa',
    );
    if (!confirmed) return;

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
    final confirmed = await _confirmPhysicalAction(
      title: 'Testezi traseul?',
      message:
          '${zone.name} va porni temporar pentru durata de test configurata.',
      confirmLabel: 'Testeaza',
    );
    if (!confirmed) return;

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
      readTimeoutSeconds: settings.readTimeoutSeconds,
      writeTimeoutSeconds: settings.writeTimeoutSeconds,
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

  Future<bool> _confirmPhysicalAction({
    required String title,
    required String message,
    required String confirmLabel,
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
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(confirmLabel),
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
