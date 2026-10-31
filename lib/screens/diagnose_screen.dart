import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/db.dart';
import '../services/gemini_service.dart';
import '../services/rag_service.dart';
import 'storage_image.dart';

/// Display label for a subject. The English label stays the key sent to the
/// server; only what the farmer sees is translated.
String _subjectLabel(BuildContext context, String englishLabel) =>
    context.tr('subj_${subjectToDb[englishLabel] ?? 'poultry_droppings'}');

/// "High" / "Medium" / "Low" come back from the server in English.
String _confLabel(BuildContext context, String c) {
  final key = 'conf_${c.toLowerCase()}';
  final t = context.tr(key);
  return t == key ? c : t;
}

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key});
  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  final _picker = ImagePicker();
  final _notes = TextEditingController();
  String _subject = subjectToDb.keys.first;
  XFile? _image;
  bool _busy = false;
  Diagnosis? _result;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final f = await _picker.pickImage(source: src, maxWidth: 1280, imageQuality: 85);
    if (f != null) {
      setState(() {
        _image = f;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _analyze() async {
    final img = _image;
    if (img == null) return;
    final signInMsg = context.tr('diag_signin');
    final saveFailMsg = context.tr('diag_save_fail');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!GeminiService.instance.enabled) {
        throw Exception(signInMsg);
      }
      final bytes = await img.readAsBytes();
      final mime = img.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final notes = _notes.text.trim();
      final ctx = RagService.instance.search('$_subject disease signs prevention treatment $notes', k: 5);
      var d = await GeminiService.instance.diagnose(
        bytes: bytes,
        mime: mime,
        species: _subject,
        notes: notes,
        imagePath: '',
        contexts: ctx,
      );
      try {
        d = await Db.i.saveDiagnosis(
          d,
          bytes: bytes,
          mime: mime,
          notes: notes,
          flockId: AppState.instance.flock?.id,
        );
        AppState.instance.addDiagnosis(d);
      } catch (_) {
        _error = saveFailMsg;
      }
      if (!mounted) return;
      setState(() => _result = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
      Text(context.tr('nav_diagnose'), style: t.headlineSmall),
      const SizedBox(height: 4),
      Text(context.tr('diag_intro'), style: t.bodyMedium?.copyWith(color: context.muted)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in subjectToDb.keys)
          ChoiceChip(
            label: Text(_subjectLabel(context, s)),
            selected: _subject == s,
            onSelected: (_) => setState(() => _subject = s),
          ),
      ]),
      const SizedBox(height: 16),
      AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.lineColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: _image == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_a_photo_outlined, size: 40, color: context.muted),
                  const SizedBox(height: 8),
                  Text(context.tr('no_photo'), style: t.bodyMedium?.copyWith(color: context.muted)),
                ])
              : Image.file(File(_image!.path), fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(context.tr('camera')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(context.tr('upload')),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        maxLines: 2,
        decoration: InputDecoration(hintText: context.tr('diag_notes_hint')),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _image == null || _busy ? null : _analyze,
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(context.tr('analyse')),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Text(_error!, style: t.bodyMedium?.copyWith(color: context.danger)),
      ],
      if (_result != null) ...[
        const SizedBox(height: 18),
        ResultCard(d: _result!),
      ],
      ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final history = AppState.instance.history;
          if (history.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 26),
            Text(context.tr('recent_checks'), style: t.titleLarge),
            const SizedBox(height: 10),
            for (final h in history.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: StorageImage(path: h.imagePath),
                    title: Text(h.condition),
                    subtitle: Text('${_subjectLabel(context, h.species)}, ${h.at.day}/${h.at.month}'),
                    trailing: Text(_confLabel(context, h.confidence), style: t.labelMedium),
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        child: ResultCard(d: h),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
      const SizedBox(height: 16),
      Text(context.tr('diag_disclaimer'), style: t.bodySmall?.copyWith(color: context.muted)),
    ]);
  }
}

class ResultCard extends StatelessWidget {
  final Diagnosis d;
  const ResultCard({super.key, required this.d});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final warn = d.escalate;
    final accent = warn ? context.danger : CoopColors.leaf;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(warn ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('likely', {'c': d.condition}), style: t.titleLarge)),
          ]),
          const SizedBox(height: 4),
          Text(context.tr('pattern_match', {'c': _confLabel(context, d.confidence)}),
              style: t.labelLarge?.copyWith(color: accent)),
          const SizedBox(height: 12),
          Text(d.summary, style: t.bodyMedium),
          const SizedBox(height: 14),
          Text(context.tr('recommended'), style: t.labelLarge),
          const SizedBox(height: 4),
          Text(d.recommendation, style: t.bodyMedium),
          if (d.isolate) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.call_split, size: 18, color: context.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr('isolate_note'), style: t.bodyMedium)),
            ]),
          ],
          if (d.escalate) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: CoopColors.alert),
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                AppState.instance.escalate(d);
              },
              icon: const Icon(Icons.medical_services_outlined),
              label: Text(context.tr('talk_agrovet')),
            ),
          ],
        ]),
      ),
    );
  }
}
