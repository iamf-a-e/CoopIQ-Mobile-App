class Chunk {
  final String id, text, source, section, topic;
  const Chunk({required this.id, required this.text, required this.source, required this.section, required this.topic});
  factory Chunk.fromJson(Map<String, dynamic> j) => Chunk(
        id: j['id'] ?? '',
        text: j['text'] ?? '',
        source: j['source'] ?? '',
        section: j['section'] ?? '',
        topic: j['topic'] ?? '',
      );
}

class ChatMsg {
  final bool fromUser;
  final String text;
  final List<Chunk> sources;
  const ChatMsg(this.fromUser, this.text, [this.sources = const []]);
}

/// UI label -> diagnosis_subject enum in the database.
const subjectToDb = {
  'Poultry droppings': 'poultry_droppings',
  'Poultry bird': 'poultry_bird',
  'Cattle': 'cattle',
  'Goat or sheep': 'goat_sheep',
  'Pig': 'pig',
};
final dbToSubject = {for (final e in subjectToDb.entries) e.value: e.key};

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

DateTime _dateOnly(dynamic v) {
  final p = DateTime.parse(v.toString().substring(0, 10));
  return DateTime(p.year, p.month, p.day);
}

class Diagnosis {
  final String? id;
  final String species, condition, confidence, summary, recommendation, imagePath;
  final bool isolate, escalate;
  final DateTime at;
  const Diagnosis({
    this.id,
    required this.species,
    required this.condition,
    required this.confidence,
    required this.summary,
    required this.recommendation,
    required this.isolate,
    required this.escalate,
    required this.imagePath,
    required this.at,
  });

  factory Diagnosis.fromRow(Map<String, dynamic> r) => Diagnosis(
        id: r['id'] as String?,
        species: dbToSubject[r['subject']] ?? 'Poultry droppings',
        condition: (r['condition'] ?? 'Unclear').toString(),
        confidence: _cap((r['confidence'] ?? 'low').toString()),
        summary: (r['summary'] ?? '').toString(),
        recommendation: (r['recommendation'] ?? '').toString(),
        imagePath: (r['image_path'] ?? '').toString(),
        isolate: r['isolate'] == true,
        escalate: r['escalate'] == true,
        at: DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      );
}

class Flock {
  final String id, name;
  final int birds;
  final DateTime start;
  const Flock({required this.id, required this.name, required this.birds, required this.start});
  factory Flock.fromRow(Map<String, dynamic> r) => Flock(
        id: r['id'] as String,
        name: (r['name'] ?? 'Batch').toString(),
        birds: (r['bird_count'] ?? 0) as int,
        start: _dateOnly(r['start_date']),
      );
}

class FlockVax {
  final String id, vaccine, method;
  final int day;
  final DateTime due;
  final DateTime? doneAt;
  const FlockVax({
    required this.id,
    required this.vaccine,
    required this.method,
    required this.day,
    required this.due,
    required this.doneAt,
  });
  bool get done => doneAt != null;
  factory FlockVax.fromRow(Map<String, dynamic> r) => FlockVax(
        id: r['id'] as String,
        vaccine: (r['vaccine'] ?? '').toString(),
        method: (r['method'] ?? '').toString(),
        day: (r['day'] ?? 0) as int,
        due: _dateOnly(r['due_date']),
        doneAt: r['done_at'] == null ? null : _dateOnly(r['done_at']),
      );
}

class VaxStep {
  final int day;
  final String vaccine, how;
  const VaxStep(this.day, this.vaccine, this.how);
}

/// Shown on the Flock tab before a batch exists. Same schedule the database
/// copies into each new flock (doc3_vaccination_001 in the grounding file).
const broilerVaccination = [
  VaxStep(1, "Marek's and Newcastle", 'Given at the hatchery'),
  VaxStep(7, 'Gumboro, 1st dose', 'In clean drinking water with skimmed milk powder'),
  VaxStep(14, 'Newcastle, 1st dose', 'Drinking water or eye drops'),
  VaxStep(18, 'Gumboro, 2nd booster', 'In drinking water'),
  VaxStep(24, 'Newcastle, 2nd booster', 'In drinking water'),
];
const vaccineWaterNote =
    'Never use water with chlorine or tap chemicals for vaccines. Use borehole water, or let tap water stand uncovered for 24 hours first.';
