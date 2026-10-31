import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/strings.dart';

/// Talks to the gemini-proxy Edge Function. The Gemini key stays on the server.
/// Kept under the old name so the screens did not need to change.
class GeminiService {
  GeminiService._();
  static final instance = GeminiService._();

  /// Sent as the `language` for chat. The gemini-proxy treats anything that is
  /// not a known language name as "detect it from the question".
  static const autoLanguage = 'auto';

  SupabaseClient get _c => Supabase.instance.client;

  /// The function only answers signed-in users.
  bool get enabled => _c.auth.currentSession != null;

  String _t(String key) => Strings.lookup(Settings.instance.lang, key);

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _c.functions.invoke('gemini-proxy', body: body);
      final d = res.data;
      if (d is Map<String, dynamic>) return d;
      if (d is String) return jsonDecode(d) as Map<String, dynamic>;
      throw Exception(_t('err_unexpected'));
    } on FunctionException catch (e) {
      if (e.status == 429) throw Exception(_t('err_limit'));
      if (e.status == 401) throw Exception(_t('err_signin_again'));
      throw Exception(_t('err_unavailable'));
    }
  }

  List<Map<String, String>> _ctx(List<Chunk> chunks) => [
        for (final c in chunks) {'source': c.source, 'section': c.section, 'text': c.text},
      ];

  Future<String> chat({
    required List<ChatMsg> history,
    required String question,
    required List<Chunk> contexts,
    required String language,
  }) async {
    final d = await _call({
      'action': 'chat',
      'question': question,
      'language': language,
      'history': [
        for (final m in history.takeLast(8)) {'fromUser': m.fromUser, 'text': m.text},
      ],
      'contexts': _ctx(contexts),
    });
    return (d['text'] ?? '').toString().trim();
  }

  Future<Diagnosis> diagnose({
    required Uint8List bytes,
    required String mime,
    required String species,
    required String notes,
    required String imagePath,
    required List<Chunk> contexts,
  }) async {
    final d = await _call({
      'action': 'diagnose',
      'image_base64': base64Encode(bytes),
      'mime': mime,
      'subject': species,
      'notes': notes,
      'language': Settings.instance.langName,
      'contexts': _ctx(contexts),
    });
    return Diagnosis(
      species: species,
      condition: (d['condition'] ?? 'Unclear').toString(),
      confidence: (d['confidence'] ?? 'Low').toString(),
      summary: (d['summary'] ?? '').toString(),
      recommendation: (d['recommendation'] ?? '').toString(),
      isolate: d['isolate'] == true,
      escalate: d['escalate'] == true,
      imagePath: imagePath,
      at: DateTime.now(),
    );
  }
}

extension _Tail<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
