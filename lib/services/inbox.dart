import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  final String id, kind, title;
  final String? body;
  final DateTime at;
  final DateTime? readAt;
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.at,
    this.body,
    this.readAt,
  });

  bool get unread => readAt == null;

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        kind: (r['kind'] ?? '').toString(),
        title: (r['title'] ?? '').toString(),
        body: r['body'] as String?,
        at: DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
        readAt: r['read_at'] == null ? null : DateTime.tryParse(r['read_at'].toString())?.toLocal(),
      );
}

/// The signed-in user's notifications. Call Inbox.instance.init() once in main(),
/// straight after Supabase.initialize(). It loads on sign-in, listens for new
/// ones live, and clears on sign-out.
class Inbox extends ChangeNotifier {
  Inbox._();
  static final instance = Inbox._();

  List<AppNotification> items = [];
  RealtimeChannel? _channel;
  String? _uid;
  bool _listening = false;

  SupabaseClient get _c => Supabase.instance.client;

  int get unread => items.where((n) => n.unread).length;

  void init() {
    if (_listening) return;
    _listening = true;
    _c.auth.onAuthStateChange.listen((data) {
      final id = data.session?.user.id;
      if (data.event == AuthChangeEvent.signedOut || id == null) {
        _stop();
      } else if (id != _uid) {
        _start(id);
      }
    });
    final id = _c.auth.currentUser?.id;
    if (id != null) _start(id);
  }

  Future<void> _start(String uid) async {
    _uid = uid;
    await refresh();
    if (_channel != null) await _c.removeChannel(_channel!);
    _channel = _c
        .channel('inbox-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) {
            items = [AppNotification.fromRow(payload.newRecord), ...items];
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> _stop() async {
    _uid = null;
    if (_channel != null) {
      await _c.removeChannel(_channel!);
      _channel = null;
    }
    items = [];
    notifyListeners();
  }

  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _c
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      items = rows.map(AppNotification.fromRow).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final ids = items.where((n) => n.unread).map((n) => n.id).toList();
    if (ids.isEmpty) return;
    final now = DateTime.now();
    items = [
      for (final n in items)
        n.unread
            ? AppNotification(id: n.id, kind: n.kind, title: n.title, body: n.body, at: n.at, readAt: now)
            : n,
    ];
    notifyListeners();
    try {
      await _c
          .from('notifications')
          .update({'read_at': now.toUtc().toIso8601String()}).inFilter('id', ids);
    } catch (_) {}
  }
}
