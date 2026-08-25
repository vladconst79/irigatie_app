part of '../main.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.snapshot,
    required this.isStopping,
    required this.onStop,
    required this.onShowWateringHistory,
    required this.onShowRainHistory,
    required this.onShowEtDetails,
  });

  final IrrigationSnapshot snapshot;
  final bool isStopping;
  final VoidCallback onStop;
  final VoidCallback onShowWateringHistory;
  final ValueChanged<String> onShowRainHistory;
  final VoidCallback onShowEtDetails;

  @override
  Widget build(BuildContext context) {
    final etSummary = _EtSummary.fromZones(snapshot.zones);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResponsiveGrid(
          minTileWidth: 220,
          maxColumns: 5,
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
              tooltipMessage: 'Istoric udari',
              tapIcon: Icons.history_rounded,
            ),
            _RainfallMetricTile(
              rainfall: snapshot.rainfall24h,
              onShowHistory: onShowRainHistory,
            ),
            _MetricTile(
              icon: Icons.local_florist_rounded,
              title: 'Necesar apa',
              value: etSummary.valueLabel,
              detail: etSummary.detailLabel,
              tone: etSummary.tone,
              onTap: onShowEtDetails,
              tooltipMessage: 'Detalii ET',
              tapIcon: Icons.info_outline_rounded,
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
                child: _RelayList(
                  statusAvailable: snapshot.statusAvailable,
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

class _EtStateSheet extends StatelessWidget {
  const _EtStateSheet({required this.snapshot});

  final IrrigationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final zones = [...snapshot.zones]
      ..sort((left, right) {
        final leftDeficit = left.waterDeficitMm;
        final rightDeficit = right.waterDeficitMm;
        if (leftDeficit == null && rightDeficit == null) return 0;
        if (leftDeficit == null) return 1;
        if (rightDeficit == null) return -1;
        return rightDeficit.compareTo(leftDeficit);
      });

    return FractionallySizedBox(
      heightFactor: 0.82,
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
                      'Stare ET',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
            Expanded(
              child: zones.isEmpty
                  ? const Center(child: Text('Nu exista date ET pentru zone.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      itemCount: zones.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return const _EtStateNotice();
                        }

                        return _EtStateRow(zone: zones[index - 1]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EtStateNotice extends StatelessWidget {
  const _EtStateNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: const Text(
        'Backend-ul expune starea ET curenta, nu un istoric ET paginat.',
      ),
    );
  }
}

class _EtStateRow extends StatelessWidget {
  const _EtStateRow({required this.zone});

  final IrrigationZone zone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: zone.color.withValues(alpha: 0.16),
                child: Icon(zone.icon, color: zone.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  zone.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StateChip(zone.enabled ? 'activ' : 'inactiv', zone.enabled),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine('Deficit apa', _formatMillimeters(zone.waterDeficitMm)),
          _DetailLine('Ultimul ET0', _formatMillimeters(zone.lastEt0Mm)),
          _DetailLine(
            'Actualizat ET',
            _formatStateUpdatedAt(zone.lastEtUpdate),
          ),
          _DetailLine('Ploaie credit', _formatMillimeters(zone.rainCreditMm)),
          _DetailLine(
            'Fara ploaie',
            _formatCyclesWithoutRain(zone.cyclesWithoutRain),
          ),
        ],
      ),
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

class _RainHistorySheet extends StatefulWidget {
  const _RainHistorySheet({required this.client, required this.source});

  final IrrigationDataClient client;
  final String source;

  @override
  State<_RainHistorySheet> createState() => _RainHistorySheetState();
}

class _RainHistorySheetState extends State<_RainHistorySheet> {
  final _items = <RainHistoryItem>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int? _nextBeforeId;
  String? _error;

  String get _sourceLabel => _rainSourceLabel(widget.source);

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
      final page = await widget.client.fetchRainHistory(
        source: widget.source,
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
                      'Istoric ploaie · $_sourceLabel',
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
              'Istoricul de ploaie nu poate fi incarcat.',
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
      return Center(
        child: Text('Nu exista evenimente de ploaie pentru $_sourceLabel.'),
      );
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

        return _RainHistoryRow(item: _items[index]);
      },
    );
  }
}

class _RainHistoryRow extends StatelessWidget {
  const _RainHistoryRow({required this.item});

  final RainHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rawValue = item.rawValue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloudy_snowing, color: _Tone.amber.color(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatMillimeters(item.amountMm),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _rainSourceLabel(item.source),
                    item.eventTime,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                if (rawValue != null) ...[
                  const SizedBox(height: 10),
                  _InfoChip(
                    Icons.sensors_rounded,
                    'raw ${rawValue.toStringAsFixed(2)}',
                  ),
                ],
              ],
            ),
          ),
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

String _rainSourceLabel(String source) {
  final normalized = source.toLowerCase();
  if (normalized == 'openmeteo' || normalized == 'open_meteo') {
    return 'Open-Meteo';
  }
  if (normalized == 'hardware') return 'Hardware';
  return source.isEmpty ? 'N/A' : source;
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiTokenController;
  late final TextEditingController _readTimeoutController;
  late final TextEditingController _writeTimeoutController;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: widget.settings.apiUrl);
    _apiTokenController = TextEditingController(text: widget.settings.apiToken);
    _readTimeoutController = TextEditingController(
      text: widget.settings.readTimeoutSeconds.toString(),
    );
    _writeTimeoutController = TextEditingController(
      text: widget.settings.writeTimeoutSeconds.toString(),
    );
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
    if (oldWidget.settings.readTimeoutSeconds !=
        widget.settings.readTimeoutSeconds) {
      _readTimeoutController.text = widget.settings.readTimeoutSeconds
          .toString();
    }
    if (oldWidget.settings.writeTimeoutSeconds !=
        widget.settings.writeTimeoutSeconds) {
      _writeTimeoutController.text = widget.settings.writeTimeoutSeconds
          .toString();
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiTokenController.dispose();
    _readTimeoutController.dispose();
    _writeTimeoutController.dispose();
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
        child: Form(
          key: _formKey,
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
              const SizedBox(height: 14),
              _TwoColumnFields(
                children: [
                  TextFormField(
                    controller: _readTimeoutController,
                    decoration: const InputDecoration(
                      labelText: 'Timeout citire secunde',
                      prefixIcon: Icon(Icons.timer_rounded),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: _positiveInt,
                  ),
                  TextFormField(
                    controller: _writeTimeoutController,
                    decoration: const InputDecoration(
                      labelText: 'Timeout scriere secunde',
                      prefixIcon: Icon(Icons.timer_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: _positiveInt,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(
      ApiSettings(
        apiUrl: _apiUrlController.text,
        apiToken: _apiTokenController.text,
        readTimeoutSeconds: int.parse(_readTimeoutController.text.trim()),
        writeTimeoutSeconds: int.parse(_writeTimeoutController.text.trim()),
      ),
    );
  }
}
