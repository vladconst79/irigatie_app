part of '../main.dart';

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
              if (editing) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _ZoneRainStateDetails(zone: widget.zone!),
              ],
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

class _ZoneRainStateDetails extends StatelessWidget {
  const _ZoneRainStateDetails({required this.zone});

  final IrrigationZone zone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailLine('Ploaie', _formatMillimeters(zone.rainCreditMm)),
        _DetailLine(
          'Fara ploaie',
          _formatCyclesWithoutRain(zone.cyclesWithoutRain),
        ),
        _DetailLine(
          'Actualizat',
          _formatRainStateUpdatedAt(zone.rainStateUpdatedAt),
        ),
        _DetailLine(
          'Eveniment ploaie',
          zone.lastRainEventId?.toString() ?? 'N/A',
        ),
      ],
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
    _dayOfMonthController.addListener(_revalidateScheduleFields);
    _dayOfWeekController.addListener(_revalidateScheduleFields);
  }

  @override
  void dispose() {
    _dayOfMonthController.removeListener(_revalidateScheduleFields);
    _dayOfWeekController.removeListener(_revalidateScheduleFields);
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
                      validator: (value) => _scheduleField(
                        value,
                        minimum: 1,
                        maximum: 12,
                        fieldName: 'Luna',
                      ),
                    ),
                    _textField(
                      _dayOfMonthController,
                      'Zi luna',
                      Icons.today_rounded,
                      validator: _validateDayOfMonth,
                    ),
                    _textField(
                      _dayOfWeekController,
                      'Zi saptamana',
                      Icons.date_range_rounded,
                      validator: _validateDayOfWeek,
                    ),
                    _textField(
                      _hourController,
                      'Ora',
                      Icons.schedule_rounded,
                      validator: (value) => _scheduleField(
                        value,
                        minimum: 0,
                        maximum: 23,
                        fieldName: 'Ora',
                      ),
                    ),
                    _textField(
                      _minuteController,
                      'Minut',
                      Icons.more_time_rounded,
                      validator: (value) => _scheduleField(
                        value,
                        minimum: 0,
                        maximum: 59,
                        fieldName: 'Minut',
                      ),
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
    IconData icon, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: validator ?? _requiredText,
    );
  }

  void _revalidateScheduleFields() {
    _formKey.currentState?.validate();
  }

  String? _validateDayOfMonth(String? value) {
    final expressionError = _scheduleField(
      value,
      minimum: 1,
      maximum: 31,
      fieldName: 'Zi luna',
      allowStep: true,
    );
    if (expressionError != null) return expressionError;
    return _validateDayRestrictionCombination();
  }

  String? _validateDayOfWeek(String? value) {
    final expressionError = _scheduleField(
      value,
      minimum: 0,
      maximum: 7,
      fieldName: 'Zi saptamana',
      allowStep: true,
    );
    if (expressionError != null) return expressionError;
    return _validateDayRestrictionCombination();
  }

  String? _validateDayRestrictionCombination() {
    if (_dayOfMonthController.text.trim() != '*' &&
        _dayOfWeekController.text.trim() != '*') {
      return 'Foloseste * aici sau la celalalt camp de zi';
    }
    return null;
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
