import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/rag_service.dart';

class FlockScreen extends StatelessWidget {
  const FlockScreen({super.key});

  void _snack(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _setup(BuildContext context) async {
    final s = AppState.instance;
    final count = TextEditingController(text: (s.flock?.birds ?? 0) > 0 ? '${s.flock!.birds}' : '');
    var date = s.flock?.start ?? DateTime.now();
    var saving = false;
    final saveFailMsg = context.tr('batch_save_fail');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ctx.tr('broiler_batch'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: count,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: ctx.tr('chick_count')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 60)),
                  lastDate: DateTime.now(),
                );
                if (d != null) set(() => date = d);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(ctx.tr('chicks_arrived', {'date': '${date.day}/${date.month}/${date.year}'})),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      set(() => saving = true);
                      try {
                        await s.saveBatch(date, int.tryParse(count.text) ?? 0);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (_) {
                        set(() => saving = false);
                        if (context.mounted) _snack(context, saveFailMsg);
                      }
                    },
              child: Text(saving ? ctx.tr('saving') : ctx.tr('save_batch')),
            ),
          ]),
        ),
      ),
    );
  }

  void _growth(BuildContext context) {
    final rows = RagService.instance.byTopic('Weekly Growth Tracking');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
          Text(ctx.tr('growth_targets'), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final r in rows) ...[Text(r.text), const SizedBox(height: 14)],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final day = s.batchDay;
        final today = DateTime.now();
        final todayOnly = DateTime(today.year, today.month, today.day);
        return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
          Text(context.tr('nav_flock'), style: t.headlineSmall),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.flock == null) ...[
                  Text(context.tr('no_batch'), style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text(context.tr('no_batch_sub'), style: t.bodyMedium?.copyWith(color: context.muted)),
                ] else ...[
                  Text(context.tr('day_of', {'day': '$day'}), style: t.titleLarge),
                  const SizedBox(height: 4),
                  Text(context.tr('birds_count', {'n': '${s.flock!.birds}'}),
                      style: t.bodyMedium?.copyWith(color: context.muted)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: ((day ?? 0) / 42).clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: CoopColors.leaf,
                    backgroundColor: context.lineColor,
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  TextButton(
                    onPressed: () => _setup(context),
                    child: Text(s.flock == null ? context.tr('start_batch') : context.tr('edit_batch')),
                  ),
                  if (s.flock != null)
                    TextButton(
                      onPressed: () async {
                        final failMsg = context.tr('close_fail');
                        try {
                          await s.clearBatch();
                        } catch (_) {
                          if (context.mounted) _snack(context, failMsg);
                        }
                      },
                      child: Text(context.tr('close_batch')),
                    ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          Text(context.tr('vax_schedule'), style: t.titleLarge),
          if (s.flock != null) ...[
            const SizedBox(height: 4),
            Text(context.tr('vax_tap_hint'), style: t.bodySmall?.copyWith(color: context.muted)),
          ],
          const SizedBox(height: 10),
          if (s.flock != null)
            for (final v in s.vaccinations)
              _VaxTile(
                day: v.day,
                vaccine: v.vaccine,
                how: v.method,
                done: v.done,
                state: v.done
                    ? _VaxState.done
                    : (v.due == todayOnly ? _VaxState.today : (v.due.isBefore(todayOnly) ? _VaxState.overdue : _VaxState.upcoming)),
                onTap: () async {
                  final failMsg = context.tr('update_fail');
                  try {
                    await s.toggleVax(v);
                  } catch (_) {
                    if (context.mounted) _snack(context, failMsg);
                  }
                },
              )
          else
            for (final v in broilerVaccination)
              _VaxTile(day: v.day, vaccine: v.vaccine, how: v.how, done: false, state: _VaxState.upcoming),
          const SizedBox(height: 6),
          Text(context.tr('vax_water_note'), style: t.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => _growth(context),
            icon: const Icon(Icons.show_chart),
            label: Text(context.tr('growth_targets')),
          ),
        ]);
      },
    );
  }
}

enum _VaxState { done, today, overdue, upcoming }

class _VaxTile extends StatelessWidget {
  final int day;
  final String vaccine, how;
  final bool done;
  final _VaxState state;
  final VoidCallback? onTap;
  const _VaxTile({required this.day, required this.vaccine, required this.how, required this.done, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _VaxState.done => CoopColors.leaf,
      _VaxState.today => CoopColors.amber,
      _VaxState.overdue => context.danger,
      _VaxState.upcoming => context.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: color.withAlpha(40),
            child: Text('$day', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
          title: Text(vaccine),
          subtitle: Text(how),
          trailing: switch (state) {
            _VaxState.done => const Icon(Icons.check_circle, color: CoopColors.leaf),
            _VaxState.today => Text(context.tr('today'), style: const TextStyle(color: CoopColors.amber, fontWeight: FontWeight.w700)),
            _VaxState.overdue => Text(context.tr('overdue'), style: TextStyle(color: context.danger, fontWeight: FontWeight.w700)),
            _VaxState.upcoming => null,
          },
        ),
      ),
    );
  }
}
