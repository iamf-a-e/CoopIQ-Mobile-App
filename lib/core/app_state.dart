import 'package:flutter/foundation.dart';
import '../services/db.dart';
import 'models.dart';

/// In-memory view of the signed-in user's data. Supabase is the source of truth.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  int tab = 0;
  int agrovetMode = 0; // 0 = talk to a vet, 1 = farm visit
  String? agrovetPrefill;
  String? agrovetDiagnosisId;

  String fullName = '';
  String email = '';
  String phone = '';
  String language = 'English';

  Flock? flock;
  List<FlockVax> vaccinations = [];
  List<Diagnosis> history = [];

  Future<void> load() async {
    try {
      final p = await Db.i.profile();
      if (p != null) {
        fullName = (p['full_name'] ?? '').toString();
        email = (p['email'] ?? '').toString();
        phone = (p['phone'] ?? '').toString();
        language = (p['language'] ?? 'English').toString();
      }
    } catch (_) {}
    try {
      await refreshFlock(notify: false);
    } catch (_) {}
    try {
      history = await Db.i.recentDiagnoses();
    } catch (_) {}
    notifyListeners();
  }

  void reset() {
    tab = 0;
    agrovetMode = 0;
    agrovetPrefill = null;
    agrovetDiagnosisId = null;
    fullName = email = phone = '';
    language = 'English';
    flock = null;
    vaccinations = [];
    history = [];
  }

  Future<void> refreshFlock({bool notify = true}) async {
    flock = await Db.i.activeFlock();
    vaccinations = flock == null ? [] : await Db.i.vaccinations(flock!.id);
    if (notify) notifyListeners();
  }

  Future<void> updateDetails(String name, String phone) async {
    await Db.i.updateProfile({'full_name': name, 'phone': phone});
    fullName = name;
    this.phone = phone;
    notifyListeners();
  }

  String get firstName => fullName.trim().isEmpty ? '' : fullName.trim().split(' ').first;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  void go(int t) {
    tab = t;
    notifyListeners();
  }

  void setLanguage(String l) {
    language = l;
    notifyListeners();
    Db.i.updateProfile({'language': l}).catchError((_) {});
  }

  /// Creates the batch, or edits the current one.
  Future<void> saveBatch(DateTime start, int count) async {
    final f = flock;
    if (f == null) {
      await Db.i.createFlock(count, start);
    } else {
      await Db.i.updateFlock(f, count, start, vaccinations);
    }
    await refreshFlock();
  }

  Future<void> clearBatch() async {
    final f = flock;
    if (f == null) return;
    await Db.i.closeFlock(f.id);
    await refreshFlock();
  }

  Future<void> toggleVax(FlockVax v) async {
    await Db.i.setVaxDone(v.id, !v.done);
    await refreshFlock();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int? get batchDay => flock == null ? null : _today.difference(flock!.start).inDays + 1;

  /// First vaccination not yet ticked off (overdue ones come first).
  FlockVax? get nextVax {
    for (final v in vaccinations) {
      if (!v.done) return v;
    }
    return null;
  }

  void addDiagnosis(Diagnosis d) {
    history.insert(0, d);
    if (history.length > 20) history = history.sublist(0, 20);
    notifyListeners();
  }

  void openAgrovet({String? prefill, String? diagnosisId, int mode = 0}) {
    agrovetPrefill = prefill;
    agrovetDiagnosisId = diagnosisId;
    agrovetMode = mode;
    tab = 3; // Vet tab
    notifyListeners();
  }

  void escalate(Diagnosis d) => openAgrovet(
        prefill:
            'Photo diagnosis flagged ${d.condition} (${d.confidence} confidence) on ${d.species.toLowerCase()}. ${d.summary}',
        diagnosisId: d.id,
      );
}
