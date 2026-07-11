part of '../main.dart';

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
