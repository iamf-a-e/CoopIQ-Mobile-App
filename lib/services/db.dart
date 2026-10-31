import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../core/models.dart';

String _ds(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Every Supabase call in the app goes through here.
class Db {
  Db._();
  static final i = Db._();

  SupabaseClient get _c => Supabase.instance.client;
  String get uid => _c.auth.currentUser!.id;

  // ---- auth ----
  Future<void> signIn(String email, String password) async {
    await _c.auth.signInWithPassword(email: email, password: password);
  }

  /// Returns true when a session started immediately. Returns false when the
  /// project requires email confirmation first.
  Future<bool> signUp(String email, String password, Map<String, dynamic> meta) async {
    final r = await _c.auth.signUp(
      email: email,
      password: password,
      data: meta,
      emailRedirectTo: AppConfig.authRedirectUrl,
    );
    return r.session != null;
  }

  Future<void> resendConfirmation(String email) async {
    await _c.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: AppConfig.authRedirectUrl,
    );
  }

  Future<void> signOut() async {
    await _c.auth.signOut();
  }

  // ---- profile ----
  Future<Map<String, dynamic>?> profile() =>
      _c.from('profiles').select().eq('id', uid).maybeSingle();

  Future<void> updateProfile(Map<String, dynamic> values) async {
    await _c.from('profiles').update(values).eq('id', uid);
  }

  // ---- flocks and vaccinations ----
  Future<Flock?> activeFlock() async {
    final rows = await _c
        .from('flocks')
        .select()
        .eq('owner_id', uid)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Flock.fromRow(rows.first);
  }

  Future<void> createFlock(int birds, DateTime start) async {
    // A database trigger copies the vaccination schedule into the new flock.
    await _c.from('flocks').insert({
      'owner_id': uid,
      'name': 'Broiler batch',
      'flock_type': 'broiler',
      'bird_count': birds,
      'start_date': _ds(start),
    });
  }

  Future<void> updateFlock(Flock f, int birds, DateTime start, List<FlockVax> vax) async {
    await _c.from('flocks').update({'bird_count': birds, 'start_date': _ds(start)}).eq('id', f.id);
    if (_ds(start) != _ds(f.start)) {
      for (final v in vax) {
        await _c
            .from('flock_vaccinations')
            .update({'due_date': _ds(start.add(Duration(days: v.day - 1)))})
            .eq('id', v.id);
      }
    }
  }

  Future<void> closeFlock(String id) async {
    await _c.from('flocks').update({'status': 'closed'}).eq('id', id);
  }

  Future<List<FlockVax>> vaccinations(String flockId) async {
    final rows = await _c.from('flock_vaccinations').select().eq('flock_id', flockId).order('day');
    return rows.map(FlockVax.fromRow).toList();
  }

  Future<void> setVaxDone(String id, bool done) async {
    await _c.from('flock_vaccinations').update({'done_at': done ? _ds(DateTime.now()) : null}).eq('id', id);
  }

  // ---- diagnoses ----
  Future<Diagnosis> saveDiagnosis(
    Diagnosis d, {
    required Uint8List bytes,
    required String mime,
    required String notes,
    String? flockId,
  }) async {
    final ext = mime == 'image/png' ? 'png' : 'jpg';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _c.storage
        .from(AppConfig.diagnosisBucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    final row = await _c
        .from('diagnoses')
        .insert({
          'owner_id': uid,
          'flock_id': flockId,
          'subject': subjectToDb[d.species] ?? 'poultry_droppings',
          'image_path': path,
          'farmer_notes': notes.isEmpty ? null : notes,
          'condition': d.condition,
          'confidence': d.confidence.toLowerCase(),
          'summary': d.summary,
          'recommendation': d.recommendation,
          'isolate': d.isolate,
          'escalate': d.escalate,
          'model': 'gemini-2.5-flash',
        })
        .select()
        .single();
    return Diagnosis.fromRow(row);
  }

  Future<List<Diagnosis>> recentDiagnoses({int limit = 20}) async {
    final rows = await _c
        .from('diagnoses')
        .select()
        .eq('owner_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Diagnosis.fromRow).toList();
  }

  Future<String> signedUrl(String path) =>
      _c.storage.from(AppConfig.diagnosisBucket).createSignedUrl(path, 3600);

  // ---- chat ----
  Future<void> saveMessage({
    required String sessionId,
    required bool fromUser,
    required String content,
    required String language,
    List<String> sources = const [],
  }) async {
    await _c.from('chat_messages').insert({
      'user_id': uid,
      'session_id': sessionId,
      'role': fromUser ? 'user' : 'assistant',
      'content': content,
      'language': language,
      'sources': sources,
    });
  }

  // ---- vet ----
  Future<void> createConsultation({
    required String name,
    required String phone,
    String? email,
    required bool urgent,
    required String details,
    String? diagnosisId,
  }) async {
    await _c.from('consultations').insert({
      'requester_id': uid,
      'name': name,
      'phone': phone,
      'email': (email == null || email.isEmpty) ? null : email,
      'urgency': urgent ? 'urgent' : 'standard',
      'details': details,
      'diagnosis_id': diagnosisId,
    });
  }

  Future<void> createVisit({
    required String name,
    required String phone,
    String? email,
    required String location,
    required String farmType,
    required String reason,
    DateTime? preferredDate,
    String? notes,
    String? diagnosisId,
  }) async {
    await _c.from('farm_visits').insert({
      'requester_id': uid,
      'name': name,
      'phone': phone,
      'email': (email == null || email.isEmpty) ? null : email,
      'farm_location': location,
      'farm_type': farmType.toLowerCase(),
      'reason': reason.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_'),
      'preferred_date': preferredDate == null ? null : _ds(preferredDate),
      'notes': (notes == null || notes.isEmpty) ? null : notes,
      'diagnosis_id': diagnosisId,
    });
  }
}
