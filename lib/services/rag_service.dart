import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../core/models.dart';

/// On-device retrieval over the bundled poultry_rag.jsonl. Works offline, which
/// matches the low-connectivity design used across the Dawa apps.
class RagService {
  RagService._();
  static final instance = RagService._();

  List<Chunk> chunks = [];
  final Map<String, double> _idf = {};
  final Map<String, Map<String, int>> _tf = {};

  static const _stop = {
    'the', 'and', 'for', 'are', 'was', 'with', 'that', 'this', 'from', 'have', 'how',
    'what', 'when', 'can', 'you', 'your', 'not', 'but', 'all', 'any', 'does', 'into',
    'about', 'should', 'will', 'its', 'our', 'out', 'use', 'per', 'has', 'been',
  };

  List<String> _tok(String s) => RegExp(r"[a-z0-9']+")
      .allMatches(s.toLowerCase())
      .map((m) => m.group(0)!)
      .where((t) => t.length > 2 && !_stop.contains(t))
      .toList();

  Future<void> load() async {
    if (chunks.isNotEmpty) return;
    final raw = await rootBundle.loadString('assets/data/poultry_rag.jsonl');
    chunks = raw
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => Chunk.fromJson(jsonDecode(l) as Map<String, dynamic>))
        .toList();
    final df = <String, int>{};
    for (final c in chunks) {
      final counts = <String, int>{};
      for (final t in _tok('${c.topic} ${c.section} ${c.text}')) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
      _tf[c.id] = counts;
      for (final t in counts.keys) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    for (final e in df.entries) {
      _idf[e.key] = log(1 + chunks.length / e.value);
    }
  }

  List<Chunk> search(String query, {int k = 4}) {
    final q = _tok(query).toSet();
    if (q.isEmpty) return [];
    final scored = <MapEntry<Chunk, double>>[];
    for (final c in chunks) {
      final tf = _tf[c.id] ?? const {};
      final head = _tok('${c.topic} ${c.section}').toSet();
      var s = 0.0;
      for (final t in q) {
        final f = tf[t];
        if (f != null) s += (_idf[t] ?? 0) * (1 + log(f));
        if (head.contains(t)) s += (_idf[t] ?? 0) * 1.5;
      }
      if (s > 0) scored.add(MapEntry(c, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(k).map((e) => e.key).toList();
  }

  Map<String, List<Chunk>> bySource() {
    final m = <String, List<Chunk>>{};
    for (final c in chunks) {
      m.putIfAbsent(c.source, () => []).add(c);
    }
    return m;
  }

  List<Chunk> byTopic(String topic) => chunks.where((c) => c.topic == topic).toList();
}
