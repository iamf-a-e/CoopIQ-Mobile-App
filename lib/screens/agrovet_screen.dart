import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state.dart';
import '../core/config.dart';
import '../core/notify.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/db.dart';

class AgrovetScreen extends StatefulWidget {
  const AgrovetScreen({super.key});
  @override
  State<AgrovetScreen> createState() => _AgrovetScreenState();
}

class _AgrovetScreenState extends State<AgrovetScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _details = TextEditingController();
  bool _urgent = false;
  String _farmType = 'Poultry';
  String _reason = 'Immunization';
  DateTime? _date;
  final _key = GlobalKey<FormState>();
  String? _lastPrefill;

  // The English values are what gets saved and sent to the vet. Only the
  // labels the farmer sees are translated.
  static const _farmTypes = {
    'Poultry': 'farm_poultry',
    'Livestock': 'farm_livestock',
    'Both': 'farm_both',
  };
  static const _reasons = {
    'Immunization': 'reason_immunization',
    'Treatment': 'reason_treatment',
    'Follow-up': 'reason_followup',
    'Other': 'reason_other',
  };

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    _name.text = s.fullName;
    _phone.text = s.phone;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _send(bool visit) async {
    if (!_key.currentState!.validate()) return;
    final st = AppState.instance;
    try {
      if (visit) {
        await Db.i.createVisit(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: st.email,
          location: _location.text.trim(),
          farmType: _farmType,
          reason: _reason,
          preferredDate: _date,
          notes: _details.text.trim(),
          diagnosisId: st.agrovetDiagnosisId,
        );
      } else {
        await Db.i.createConsultation(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: st.email,
          urgent: _urgent,
          details: _details.text.trim(),
          diagnosisId: st.agrovetDiagnosisId,
        );
      }
    } catch (e) {
      debugPrint('Vet request save failed: $e');
      if (mounted) {
        await showNotice(
          context,
          title: 'Request not sent',
          message:
              'Could not send your request. Check your connection and try again.',
          error: true,
        );
      }
      return; // keep the form filled in so nothing is lost
    }
    st.agrovetDiagnosisId = null;
    st.agrovetPrefill = null;
    _lastPrefill = null;
    _details.clear();
    if (mounted) {
      await showNotice(
        context,
        title: visit ? 'Visit requested' : 'Request sent',
        message: visit
            ? 'We will notify you when it is scheduled.'
            : 'A vet will reply soon.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.agrovetPrefill != null && s.agrovetPrefill != _lastPrefill) {
          _lastPrefill = s.agrovetPrefill;
          _details.text = s.agrovetPrefill!;
          _urgent = true;
        }
        final visit = s.agrovetMode == 1;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text(context.tr('nav_agrovet'), style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(context.tr('agrovet_intro'), style: t.bodyMedium?.copyWith(color: context.muted)),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(context.tr('act_agrovet')), icon: const Icon(Icons.chat_outlined)),
              ButtonSegment(value: 1, label: Text(context.tr('farm_visit')), icon: const Icon(Icons.home_work_outlined)),
            ],
            selected: {s.agrovetMode},
            onSelectionChanged: (v) => s.openAgrovet(prefill: s.agrovetPrefill, mode: v.first),
          ),
          const SizedBox(height: 18),
          Form(
            key: _key,
            child: Column(children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr('name')),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: context.tr('phone')),
                validator: _req,
              ),
              const SizedBox(height: 12),
              if (visit) ...[
                TextFormField(
                  controller: _location,
                  decoration: InputDecoration(labelText: context.tr('farm_location')),
                  validator: _req,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _farmType,
                  decoration: InputDecoration(labelText: context.tr('farm_type')),
                  items: _farmTypes.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(context.tr(e.value))))
                      .toList(),
                  onChanged: (v) => setState(() => _farmType = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _reason,
                  decoration: InputDecoration(labelText: context.tr('reason')),
                  items: _reasons.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(context.tr(e.value))))
                      .toList(),
                  onChanged: (v) => setState(() => _reason = v!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_date == null
                      ? context.tr('preferred_date')
                      : '${_date!.day}/${_date!.month}/${_date!.year}'),
                ),
                const SizedBox(height: 12),
              ] else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _urgent,
                  activeColor: context.danger,
                  title: Text(context.tr('urgent')),
                  onChanged: (v) => setState(() => _urgent = v),
                ),
              ],
              TextFormField(
                controller: _details,
                maxLines: 4,
                decoration: InputDecoration(labelText: visit ? context.tr('notes') : context.tr('whats_going_on')),
                validator: visit ? null : _req,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _send(visit),
                child: Text(visit ? context.tr('request_visit') : context.tr('send_agrovet')),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null;
}