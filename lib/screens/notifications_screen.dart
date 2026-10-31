import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import 'profile_pages.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notifications')),
        actions: [
          IconButton(
            tooltip: context.tr('notif_prefs'),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPrefsScreen()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, Settings.instance]),
        builder: (context, _) {
          final next = Settings.instance.remindersOn ? s.nextVax : null;
          if (next == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none_rounded, size: 56, color: context.muted),
                  const SizedBox(height: 12),
                  Text(context.tr('no_notifs'), style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text(context.tr('no_notifs_sub'),
                      textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.muted)),
                ]),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.all(20), children: [
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Icon(Icons.vaccines_outlined, color: context.brand, size: 30),
                title: Text(context.tr('vax_reminder'), style: t.titleMedium),
                subtitle: Text(context.tr('next_vax', {'vaccine': next.vaccine, 'day': '${next.day}'})),
                onTap: () {
                  s.go(2);
                  Navigator.pop(context);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
