import 'package:flutter/material.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/inbox.dart';

// English, Nyanja, Bemba, Lozi, Tonga. Draft translations: have native speakers
// check them. An empty entry falls back to English.
const _tx = <String, List<String>>{
  'title': ['Notifications', 'Zidziwitso', '', '', ''],
  'mark_read': ['Mark all read', 'Zonse zawerengedwa', '', '', ''],
  'empty_title': ["You're all caught up", 'Palibe zatsopano', '', '', ''],
  'empty_body': [
    'Updates about your vet requests and visits will show up here.',
    'Zosintha za zopempha zanu ndi maulendo a vet zidzaoneka apa.',
    '',
    '',
    '',
  ],
};
const _langIndex = {'English': 0, 'Nyanja': 1, 'Bemba': 2, 'Lozi': 3, 'Tonga': 4};

String _s(String key) {
  final v = _tx[key]!;
  final i = _langIndex[Settings.instance.langName] ?? 0;
  return v[i].isEmpty ? v[0] : v[i];
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return '${d.inDays} d';
}

IconData _icon(String kind) {
  if (kind.startsWith('visit')) return Icons.home_work_outlined;
  if (kind.startsWith('request')) return Icons.medical_services_outlined;
  return Icons.notifications_none;
}

/// Drop-in bell for the Home header. Shows a green dot while anything is unread
/// and opens the notifications screen.
class InboxBell extends StatelessWidget {
  const InboxBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Inbox.instance,
      builder: (context, _) {
        final hasUnread = Inbox.instance.unread > 0;
        return InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(alignment: Alignment.center, children: [
              Icon(Icons.notifications_none, size: 28, color: context.brand),
              if (hasUnread)
                Positioned(
                  right: 9,
                  top: 9,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F8F5B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    Inbox.instance.refresh();
  }

  @override
  void dispose() {
    // Mark everything read once the screen has closed, so unread items stay
    // highlighted while the person is looking at them.
    WidgetsBinding.instance.addPostFrameCallback((_) => Inbox.instance.markAllRead());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_s('title')),
        actions: [
          TextButton(onPressed: Inbox.instance.markAllRead, child: Text(_s('mark_read'))),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Inbox.instance,
        builder: (context, _) {
          final items = Inbox.instance.items;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, size: 52, color: context.muted),
                  const SizedBox(height: 12),
                  Text(_s('empty_title'), style: t.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    _s('empty_body'),
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: context.muted),
                  ),
                ]),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: Inbox.instance.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final n = items[i];
                return Card(
                  child: ListTile(
                    leading: Icon(_icon(n.kind), color: n.unread ? const Color(0xFF3F8F5B) : context.muted),
                    title: Text(n.title, style: TextStyle(fontWeight: n.unread ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: n.body == null ? null : Text(n.body!),
                    trailing: Text(_ago(n.at), style: t.bodySmall?.copyWith(color: context.muted)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
