import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/rag_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final rag = RagService.instance;
    final t = Theme.of(context).textTheme;
    final List<Chunk> hits = _q.trim().isEmpty ? [] : rag.search(_q, k: 12);
    final groups = rag.bySource();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('act_library'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(hintText: context.tr('lib_search'), prefixIcon: const Icon(Icons.search)),
        ),
        const SizedBox(height: 16),
        if (_q.trim().isNotEmpty)
          for (final c in hits) _ChunkTile(c)
        else
          for (final e in groups.entries)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(e.key, style: t.titleMedium),
                subtitle: Text(context.tr('entries', {'n': '${e.value.length}'}),
                    style: t.bodySmall?.copyWith(color: context.muted)),
                children: [for (final c in e.value) _ChunkTile(c)],
              ),
            ),
      ]),
    );
  }
}

class _ChunkTile extends StatelessWidget {
  final Chunk c;
  const _ChunkTile(this.c);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ExpansionTile(
            shape: const Border(),
            title: Text(c.topic),
            subtitle: Text(c.section, style: Theme.of(context).textTheme.bodySmall),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(c.text)],
          ),
        ),
      );
}
