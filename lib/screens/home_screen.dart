import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/rag_service.dart';
import 'chat_screen.dart';
import 'coop_logo.dart';
import 'library_screen.dart';
import 'notifications_screen.dart';
//import 'inbox_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Chunk? _tip() {
    final pool = RagService.instance.chunks
        .where((c) => c.section.contains('Biosecurity') || c.section.contains('Disease') || c.section.contains('Health'))
        .toList();
    if (pool.isEmpty) return null;
    return pool[DateTime.now().day % pool.length];
  }

  String _greeting(BuildContext context) {
    final h = DateTime.now().hour;
    if (h < 12) return context.tr('greet_morning');
    if (h < 17) return context.tr('greet_afternoon');
    return context.tr('greet_evening');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final t = Theme.of(context).textTheme;
    final tip = _tip();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
      children: [
        // Header: big logo with bell and profile on the right, greeting underneath
        ListenableBuilder(
          listenable: Listenable.merge([s, Settings.instance]),
          builder: (context, _) {
            final hasAlert = Settings.instance.remindersOn && s.nextVax != null;
            final outline = Theme.of(context).colorScheme.outlineVariant;
            return Row(children: [
              // Logo flush with the left edge, like the profile circle on the right.
              // The logo image has empty space on both sides of the mark, so we crop
              // to its centre. Make widthFactor smaller to hug the mark tighter, or
              // larger if the mark looks cut off.
              ClipRect(
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 0.5,
                  child: CoopLogo(height: 56),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Centred in the space between the logo and the bell.
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _greeting(context),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(color: context.muted),
                  ),
                  Text(
                    s.firstName.isEmpty ? context.tr('farmer') : s.firstName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: outline, width: 1.5)),
                  child: Badge(
                    isLabelVisible: hasAlert,
                    smallSize: 9,
                    backgroundColor: CoopColors.alert,
                    child: Icon(Icons.notifications_none_rounded, color: context.brand, size: 25),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => s.go(4),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.brand.withAlpha(24),
                    border: Border.all(color: CoopColors.leaf, width: 2),
                  ),
                  child: Text(s.initials,
                      style: t.titleSmall?.copyWith(color: context.brand, fontWeight: FontWeight.w700)),
                ),
              ),
            ]);
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: CoopColors.forest, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('hero_label'),
                style: t.titleMedium?.copyWith(color: CoopColors.amber, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(context.tr('hero_title'), style: t.headlineMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            Text(context.tr('hero_sub'), style: t.bodyMedium?.copyWith(color: Colors.white70)),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: CoopColors.amber, foregroundColor: CoopColors.ink),
              onPressed: () => s.go(1),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(context.tr('check_photo')),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _Action(Icons.chat_bubble_outline, context.tr('act_ask'), () => openChat(context))),
          const SizedBox(width: 12),
          Expanded(child: _Action(Icons.medical_services_outlined, context.tr('act_agrovet'), () => s.openAgrovet())),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Action(Icons.home_work_outlined, context.tr('act_visit'), () => s.openAgrovet(mode: 1))),
          const SizedBox(width: 12),
          Expanded(
            child: _Action(Icons.menu_book_outlined, context.tr('act_library'), () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen()));
            }),
          ),
        ]),
        const SizedBox(height: 22),
        ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final day = s.batchDay;
            final next = s.nextVax;
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => s.go(2),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const Icon(Icons.event_available, color: CoopColors.leaf, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          day == null ? context.tr('track_batch') : context.tr('batch_day', {'day': '$day'}),
                          style: t.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day == null
                              ? context.tr('track_batch_sub')
                              : (next == null
                                  ? context.tr('vax_done')
                                  : context.tr('next_vax', {'vaccine': next.vaccine, 'day': '${next.day}'})),
                          style: t.bodyMedium?.copyWith(color: context.muted),
                        ),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            );
          },
        ),
        if (tip != null) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('today_farm'), style: t.titleMedium),
                const SizedBox(height: 8),
                Text(tip.text, style: t.bodyMedium, maxLines: 6, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text('${tip.source}, ${tip.section}', style: t.bodySmall?.copyWith(color: context.muted)),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Column(children: [
              Icon(icon, color: context.brand, size: 28),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
            ]),
          ),
        ),
      );
}