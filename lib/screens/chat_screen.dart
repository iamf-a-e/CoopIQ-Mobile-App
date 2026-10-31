import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/db.dart';
import '../services/gemini_service.dart';
import '../services/rag_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMsg> _msgs = [];
  bool _busy = false;
  final String _sessionId = const Uuid().v4();

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Words that make up greetings and small talk in English and the local
  // languages. If a message is made up only of these, it is small talk: we skip
  // the library lookup so no unrelated source chips are attached to the reply.
  static const _chatter = <String>{
    'hi', 'hello', 'hey', 'hie', 'howdy', 'yo', 'good', 'morning', 'afternoon', 'evening', 'night',
    'day', 'how', 'hows', "how's", 'are', 'you', 'u', 'doing', 'is', 'it', 'going', 'what', 'whats',
    "what's", 'up', 'sup', 'thanks', 'thank', 'thx', 'ok', 'okay', 'bye', 'goodbye', 'see', 'later',
    'there', 'everyone', 'coopiq', 'please', 'friend', 'sir', 'madam', 'am', 'i', "i'm", 'im', 'fine',
    'well', 'and', 'the', 'nice', 'to', 'meet', 'great', 'cool', 'awesome', 'yes', 'no', 'hmm', 'lol',
    'who', 'your', 'name', 'be', 'much', 'very', 'so', 'today', 'welcome', 'pleased',
    // Nyanja
    'muli', 'bwanji', 'mwauka', 'mwaswera', 'zikomo', 'kwambiri', 'bwino', 'ni',
    // Bemba
    'shani', 'mwashibukeni', 'mwapoleni', 'natotela', 'mwaiseni',
    // Tonga
    'mwabuka', 'buti', 'mwalibizya', 'twalumba',
    // Lozi
    'mwa', 'zuhile', 'shapile', 'lumela', 'itumezi',
  };

  static bool _isSmallTalk(String q) {
    final words = q
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z' ]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return words.isNotEmpty && words.every(_chatter.contains);
  }

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    // Read translated text now, before any await.
    final notFound = context.tr('chat_not_found');
    final librarySays = context.tr('chat_library_says');
    final helloOffline = context.tr('chat_offline_hi');
    _c.clear();
    final history = List<ChatMsg>.of(_msgs);
    setState(() {
      _msgs.add(ChatMsg(true, q));
      _busy = true;
    });
    _toBottom();
    Db.i
        .saveMessage(sessionId: _sessionId, fromUser: true, content: q, language: AppState.instance.language)
        .catchError((_) {});
    final smallTalk = _isSmallTalk(q);
    final List<Chunk> ctx = smallTalk ? <Chunk>[] : RagService.instance.search(q, k: 4);
    String answer;
    try {
      if (!GeminiService.instance.enabled) throw Exception('offline');
      answer = await GeminiService.instance.chat(
        history: history,
        question: q,
        contexts: ctx,
        // No language menu: Gemini detects the language from the question.
        language: GeminiService.autoLanguage,
      );
    } catch (_) {
      answer = smallTalk
          ? helloOffline
          : (ctx.isEmpty ? notFound : '$librarySays\n\n${ctx.take(2).map((c) => c.text).join('\n\n')}');
    }
    Db.i
        .saveMessage(
          sessionId: _sessionId,
          fromUser: false,
          content: answer,
          language: AppState.instance.language,
          sources: ctx.map((c) => c.id).toList(),
        )
        .catchError((_) {});
    if (!mounted) return;
    setState(() {
      _msgs.add(ChatMsg(false, answer, ctx));
      _busy = false;
    });
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final starters = [for (var i = 1; i <= 4; i++) context.tr('starter_$i')];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ask_coopiq'))),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: _msgs.isEmpty
                ? ListView(padding: const EdgeInsets.all(20), children: [
                    Text(context.tr('chat_intro'), style: t.bodyMedium?.copyWith(color: context.muted)),
                    const SizedBox(height: 16),
                    for (final q in starters)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            title: Text(q),
                            trailing: const Icon(Icons.north_east, size: 18),
                            onTap: () => _send(q),
                          ),
                        ),
                      ),
                  ])
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _msgs.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _msgs.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      return _Bubble(_msgs[i]);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(hintText: context.tr('chat_hint')),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () => _send(_c.text),
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMsg m;
  const _Bubble(this.m);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: m.fromUser ? scheme.primary : context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: m.fromUser ? null : Border.all(color: context.lineColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text, style: t.bodyMedium?.copyWith(color: m.fromUser ? Colors.white : scheme.onSurface)),
          if (m.sources.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in m.sources.take(3))
                ActionChip(
                  label: Text(c.section, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.source, style: t.titleMedium),
                        Text(c.section, style: t.bodySmall?.copyWith(color: context.muted)),
                        const SizedBox(height: 10),
                        Text(c.text),
                      ]),
                    ),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Opens the Ask screen on top of whatever tab the user is on.
void openChat(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
}
