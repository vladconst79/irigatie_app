import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const IrrigationApp());
}

class IrrigationApp extends StatelessWidget {
  const IrrigationApp({super.key, this.initialSnapshot});

  final IrrigationSnapshot? initialSnapshot;

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
      home: IrrigationHome(initialSnapshot: initialSnapshot),
    );
  }
}

class IrrigationHome extends StatefulWidget {
  const IrrigationHome({super.key, this.initialSnapshot});

  final IrrigationSnapshot? initialSnapshot;

  @override
  State<IrrigationHome> createState() => _IrrigationHomeState();
}

class _IrrigationHomeState extends State<IrrigationHome> {
  static const _pollInterval = Duration(seconds: 3);

  int _selectedIndex = 0;
  final IrrigationDataClient _client = IrrigationDataClient();
  IrrigationSnapshot? _snapshot;
  String? _loadError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  int? _executingManualProgramId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
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
  });

  final int selectedIndex;
  final IrrigationSnapshot snapshot;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;
  final int? executingManualProgramId;
  final ValueChanged<ManualProgram> onExecuteManualProgram;

  @override
  Widget build(BuildContext context) {
    if (isLoading && snapshot.zones.isEmpty) {
      return const _LoadingState();
    }

    final error = loadError;
    if (error != null && snapshot.zones.isEmpty) {
      return _ErrorState(message: error, onRetry: onRetry);
    }

    return switch (selectedIndex) {
      0 => DashboardScreen(snapshot: snapshot),
      1 => ScheduleScreen(snapshot: snapshot),
      2 => ManualScreen(
        snapshot: snapshot,
        executingProgramId: executingManualProgramId,
        onExecuteProgram: onExecuteManualProgram,
      ),
      _ => ZonesScreen(snapshot: snapshot),
    };
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.snapshot});

  final IrrigationSnapshot snapshot;

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
              detail: snapshot.remainingLabel,
              tone: _Tone.blue,
            ),
            _MetricTile(
              icon: Icons.cloudy_snowing,
              title: 'Ultima ploaie',
              value: '${snapshot.lastRainMm.toStringAsFixed(1)} mm',
              detail: '${snapshot.lastRainSource} · ${snapshot.lastRainTime}',
              tone: _Tone.amber,
            ),
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
                action: FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                child: _RelayList(zones: snapshot.zones),
              ),
              _Panel(
                title: 'Runtime',
                action: FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
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
  const ScheduleScreen({super.key, required this.snapshot});

  final IrrigationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Programari automate',
      action: Wrap(
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Reload'),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adauga'),
          ),
        ],
      ),
      child: Column(
        children: snapshot.schedules
            .map((schedule) => _ScheduleRow(schedule: schedule))
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
  });

  final IrrigationSnapshot snapshot;
  final int? executingProgramId;
  final ValueChanged<ManualProgram> onExecuteProgram;

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
            ),
          )
          .toList(),
    );
  }
}

class ZonesScreen extends StatelessWidget {
  const ZonesScreen({super.key, required this.snapshot});

  final IrrigationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Trasee',
      action: FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: const Text('Adauga'),
      ),
      child: Column(
        children: snapshot.zones
            .map((zone) => _ZoneEditorRow(zone: zone))
            .toList(),
      ),
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
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone.color(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
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
  }
}

class _RelayList extends StatelessWidget {
  const _RelayList({required this.zones});

  final List<IrrigationZone> zones;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RelayRow(
          name: 'Transformator',
          icon: Icons.electrical_services_rounded,
          active: zones.any((zone) => zone.relayActive),
          value: zones.any((zone) => zone.relayActive) ? 1 : 0,
        ),
        ...zones.map(
          (zone) => _RelayRow(
            name: zone.name,
            icon: zone.type == ZoneType.sprinkler
                ? Icons.water_rounded
                : Icons.grass_rounded,
            active: zone.relayActive,
            value: zone.relayActive ? 1 : 0,
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
  final bool active;
  final int value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text('GPIO value $value'),
      trailing: _StateChip(active ? 'activ' : 'oprit', active),
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
  const _ScheduleRow({required this.schedule});

  final ScheduleProgram schedule;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;

            final summary = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                  onPressed: () {},
                  tooltip: 'Editeaza',
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton.filled(
                  onPressed: () {},
                  tooltip: 'Executa acum',
                  icon: const Icon(Icons.play_arrow_rounded),
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
  });

  final ManualProgram program;
  final bool isExecuting;
  final VoidCallback onExecute;

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
  const _ZoneEditorRow({required this.zone});

  final IrrigationZone zone;

  @override
  Widget build(BuildContext context) {
    return ListTile(
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
          IconButton.filledTonal(
            onPressed: () {},
            tooltip: 'Editeaza',
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
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
}

class IrrigationZone {
  const IrrigationZone({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.relayActive,
    required this.color,
  });

  final int id;
  final String name;
  final ZoneType type;
  final bool enabled;
  final bool relayActive;
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
      color: _zoneColors[index % _zoneColors.length],
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

  String get cronLabel {
    final days = dayOfWeek == '*' ? 'zilnic' : 'DOW $dayOfWeek';
    return '$days · $hour:${minute.padLeft(2, '0')}';
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

class IrrigationDataClient {
  IrrigationDataClient({
    http.Client? httpClient,
    this.apiBaseUrl = _defaultApiBaseUrl,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String apiBaseUrl;

  void close() {
    _httpClient.close();
  }

  Future<IrrigationSnapshot> fetchSnapshot() async {
    final uri = Uri.parse('$apiBaseUrl/api/snapshot');
    final response = await _httpClient.get(uri);
    final decoded = _decodeApiObject(response);

    return IrrigationSnapshot.fromJson(decoded);
  }

  Future<CommandResult> executeManualProgram(int programId) async {
    final uri = Uri.parse('$apiBaseUrl/api/manual/execute');
    final response = await _httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'program_id': programId}),
    );
    final decoded = _decodeApiObject(response);

    return CommandResult.fromJson(decoded);
  }

  Map<String, dynamic> _decodeApiObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('API response must be a JSON object');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] == false) {
      throw StateError(
        _asString(
          decoded['error'],
          fallback: 'API ${response.statusCode}: ${response.body}',
        ),
      );
    }

    return decoded;
  }
}

class CommandResult {
  const CommandResult({required this.command});

  final String command;

  factory CommandResult.fromJson(Map<String, dynamic> json) {
    final gateway = _asMap(json['gateway']);
    return CommandResult(
      command: _asString(
        gateway['command'],
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
    required this.lastRainMm,
    required this.lastRainSource,
    required this.lastRainTime,
    required this.pendingCommands,
    required this.maxPendingCommands,
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
  final double lastRainMm;
  final String lastRainSource;
  final String lastRainTime;
  final int pendingCommands;
  final int maxPendingCommands;
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
      lastRainMm: 0,
      lastRainSource: 'N/A',
      lastRainTime: 'N/A',
      pendingCommands: 0,
      maxPendingCommands: 4,
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
    final rawLastRain = _asMap(json['last_rain']);
    final rawGateway = _asMap(json['gateway']);
    final rawDb = _asMap(json['database']);
    final rawQueue = _asMap(json['queue']);
    final rawSchedules = _asList(json['schedules']);
    final rawManualPrograms = _asList(json['manual_programs']);
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
      lastRainMm: _asDouble(rawLastRain['amount_mm'], fallback: 0),
      lastRainSource: _asString(rawLastRain['source'], fallback: 'N/A'),
      lastRainTime: _asString(rawLastRain['event_time'], fallback: 'N/A'),
      pendingCommands: _asInt(rawQueue['pending']),
      maxPendingCommands: _asInt(rawQueue['max'], fallback: 4),
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
        color: Color(0xFF0E7C66),
      ),
      IrrigationZone(
        id: 2,
        name: 'Gradina legume',
        type: ZoneType.drip,
        enabled: true,
        relayActive: false,
        color: Color(0xFF3268A8),
      ),
      IrrigationZone(
        id: 3,
        name: 'Livada',
        type: ZoneType.drip,
        enabled: true,
        relayActive: false,
        color: Color(0xFFD08B2F),
      ),
      IrrigationZone(
        id: 4,
        name: 'Terasa',
        type: ZoneType.sprinkler,
        enabled: false,
        relayActive: false,
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
      lastRainMm: 2.8,
      lastRainSource: 'openmeteo',
      lastRainTime: 'azi 06:10',
      pendingCommands: 1,
      maxPendingCommands: 4,
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

const _defaultApiBaseUrl = String.fromEnvironment(
  'IRIGATIE_API_URL',
  defaultValue: 'http://127.0.0.1:8091',
);

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
  return value == 2 || value == '2' ? ZoneType.drip : ZoneType.sprinkler;
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

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}
