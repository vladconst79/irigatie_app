part of '../main.dart';

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
  const _RelayList({
    required this.statusAvailable,
    required this.transformerRelay,
    required this.zones,
  });

  final bool statusAvailable;
  final RelayStatus? transformerRelay;
  final List<IrrigationZone> zones;

  @override
  Widget build(BuildContext context) {
    final transformer = transformerRelay;

    return Column(
      children: [
        if (!statusAvailable) const _StatusUnavailableRow(),
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

class _StatusUnavailableRow extends StatelessWidget {
  const _StatusUnavailableRow();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.warning_amber_rounded, color: colors.error),
      title: const Text('Status daemon indisponibil'),
      subtitle: const Text('Starea transformatorului nu a putut fi citita.'),
      trailing: _StateChip('status', false),
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

    return Material(
      color: enabled
          ? colors.surface
          : colors.surfaceContainerHighest.withValues(alpha: 0.35),
      child: InkWell(
        onTap: () => _showScheduleDetails(context, enabled: enabled),
        child: DecoratedBox(
          decoration: BoxDecoration(
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
                      _InfoChip(
                        Icons.calendar_month_rounded,
                        schedule.cronLabel,
                      ),
                      _InfoChip(
                        Icons.timer_rounded,
                        '${schedule.durationMinutes} min',
                      ),
                    ],
                  );

                  final trailing = isExecuting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                        );
                  final actions = _ScheduleInlineActions(
                    enabled: enabled,
                    isExecuting: isExecuting,
                    onExecute: onExecute,
                    onEdit: onEdit,
                    onDelete: onDelete,
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _ScheduleTitle(schedule: schedule)),
                            const SizedBox(width: 12),
                            trailing,
                          ],
                        ),
                        const SizedBox(height: 12),
                        summary,
                        const SizedBox(height: 12),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _ScheduleTitle(schedule: schedule),
                      ),
                      Expanded(flex: 4, child: summary),
                      const SizedBox(width: 12),
                      actions,
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showScheduleDetails(BuildContext context, {required bool enabled}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ScheduleDetailsSheet(
        schedule: schedule,
        enabled: enabled,
        isExecuting: isExecuting,
        onExecute: () {
          Navigator.of(sheetContext).pop();
          onExecute();
        },
        onEdit: () {
          Navigator.of(sheetContext).pop();
          onEdit();
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          onDelete();
        },
      ),
    );
  }
}

class _ScheduleInlineActions extends StatelessWidget {
  const _ScheduleInlineActions({
    required this.enabled,
    required this.isExecuting,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
  });

  final bool enabled;
  final bool isExecuting;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
  }
}

class _ScheduleDetailsSheet extends StatelessWidget {
  const _ScheduleDetailsSheet({
    required this.schedule,
    required this.enabled,
    required this.isExecuting,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleProgram schedule;
  final bool enabled;
  final bool isExecuting;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('Program #${schedule.id}'),
                    ],
                  ),
                ),
                _StateChip(enabled ? 'activ' : 'inactiv', enabled),
              ],
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _DetailLine('Luna', schedule.month),
                    _DetailLine('Zi luna', schedule.dayOfMonth),
                    _DetailLine('Zi saptamana', schedule.dayOfWeek),
                    _DetailLine(
                      'Ora',
                      '${schedule.hour}:${schedule.minute.padLeft(2, '0')}',
                    ),
                    _DetailLine('Durata', '${schedule.durationMinutes} minute'),
                    _DetailLine(
                      'Ploaie max',
                      '${schedule.maxRainMm.toStringAsFixed(1)} mm',
                    ),
                    _DetailLine(
                      'Ploaie curenta',
                      '${schedule.currentRainMm.toStringAsFixed(1)} mm',
                    ),
                    _DetailLine(
                      'zile_fp',
                      schedule.daysWithoutRain?.toString() ?? 'N/A',
                    ),
                    _DetailLine(
                      'Traseu activ',
                      schedule.zone.enabled ? 'da' : 'nu',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final executeButton = FilledButton.icon(
                  onPressed: enabled && !isExecuting ? onExecute : null,
                  icon: isExecuting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(isExecuting ? 'Trimit' : 'Executa'),
                );
                final editButton = FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Editeaza'),
                );
                final deleteButton = OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sterge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                  ),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      executeButton,
                      const SizedBox(height: 8),
                      editButton,
                      const SizedBox(height: 8),
                      deleteButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: deleteButton),
                    const SizedBox(width: 8),
                    Expanded(child: editButton),
                    const SizedBox(width: 8),
                    Expanded(child: executeButton),
                  ],
                );
              },
            ),
          ],
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
