// supabase/functions/rudo-chat/index.ts
//
// Rudo voice/text chat relay + appointment agent.
//
// Voice turns: audio -> DAWAMOM_VOICE_BACKEND_URL (Sahara STT/TTS via Vercel)
//   -> transcript + backend reply -> runAppointmentAgent(transcript) ->
//   final reply (agent reply if it acted/asked something, otherwise the
//   backend's own reply) -> stored + returned to the Flutter client.
//
// Text turns: no Sahara involved, so the transcript IS the user's message.
//   Same runAppointmentAgent path applies.
//
// Booking safety model (do not relax without re-reading the design notes):
//   1. The model NEVER writes to `encounters` directly. Every propose_*
//      tool only builds a `pending_action` object and asks a confirmation
//      question. Nothing touches the DB until the user's *next* turn is
//      a clear "yes".
//   2. Both invariants (mother has no other 'scheduled' encounter; the
//      target doctor/date/time slot is still free) are re-checked at
//      *execution* time, not just at proposal time, because two voice
//      turns pass in between and state can change (race with the manual
//      booking button in HomeWidget, or a second voice session).
//   3. All Supabase calls in this file use the client built from the
//      caller's own Authorization header (never a service-role client),
//      so RLS enforces "only your own records" as a hard backstop even
//      if the resolve-mother/doctor logic above has a bug.
//
// Voice backend contract (api/voice.py on Vercel, Flask):
//   - Expects multipart/form-data, NOT JSON.
//   - Required form fields: 'user_id' (string), 'audio' (file, field name
//     'audio' or 'audio_file').
//   - fetch()'s FormData body sets the multipart boundary automatically —
//     never set Content-Type manually when sending FormData, or Flask's
//     multipart parser will fail to split the body correctly.
//
// Language model:
//   - `body.language` selects the reply language. Only "en" and "sn"
//     (Shona) are supported right now; anything else falls back to "en".
//   - Canned agent replies (booking/cancel/reschedule confirmations, slot
//     checks, doctor lookups, etc.) are hardcoded per-language strings in
//     STRINGS/t() below — Gemini never generates these, so translation
//     quality depends entirely on what's hardcoded there.
//   - The Gemini call whose OUTPUT is actually shown to the user
//     (generalGeminiReply) gets an explicit language instruction injected
//     into its system prompt.
//   - IMPORTANT: runGeminiWithTools() must NOT get a "respond only in
//     Shona" instruction. Its job is to decide whether to emit a
//     functionCall, not to produce user-facing text — its own text output
//     (if any) is discarded entirely. Telling it to "respond in Shona"
//     previously made the model satisfy that instruction by writing plain
//     Shona prose instead of calling a tool, which broke booking/cancel/
//     reschedule intent detection for non-English turns. Understanding the
//     user's Shona input is fine and expected; constraining the model's
//     OUTPUT language is not, since that output is never surfaced.
//
// DEBUG LOGGING NOTE (added while diagnosing agent-bypass issue):
//   `runAppointmentAgent` has two silent `engaged: false` exits (no
//   mother row found; Gemini returned no functionCall). Both previously
//   produced zero logs, so a bypassed turn was indistinguishable from a
//   genuinely unrelated message. Every bypass path and the raw Gemini
//   tool-call response are now logged with a "[rudo-agent]" prefix so
//   Edge Function logs show exactly which branch fired for a given
//   transcript.
//
// MULTI-TURN SLOT-FILLING NOTE (added after diagnosing "picks a doctor,
// falls back to Q&A" bug):
//   Previously, `list_doctors` wiped `newSessionState` to `{}`, so the
//   very next turn — the user naming one of the doctors just listed —
//   arrived with zero memory of what was offered. Fixed via:
//     1. `doctor_candidates` in SessionState: the last set of doctors
//        offered via list_doctors, cleared once a propose_* tool resolves
//        a concrete doctor.
//     2. `recent_turns` in SessionState: a short rolling window of raw
//        user transcripts, so Gemini can connect "Dr. Chikwanda" (turn 2)
//        back to earlier context like a previously-mentioned date/time.
//   Session state is now MERGED across turns in runAppointmentAgent
//   rather than replaced wholesale by whatever a single tool handler
//   returns.
//
// AWAITING-DATETIME SLOT NOTE (added as a follow-up to the above):
//   Even with doctor_candidates + recent_turns, if a doctor gets picked
//   but no date/time has ever been mentioned, Gemini has nothing to call
//   propose_booking with usefully. Rather than rely on Gemini + the
//   generic fallback to stay coherent in that gap, propose_booking's
//   tool schema no longer REQUIRES date/time: it can be called with just
//   a doctor_id. When date or time is missing, executeAgentTool sets an
//   explicit `pending_action: { type: "awaiting_datetime", doctor_id,
//   ... }` and asks a deterministic "when would you like to see Dr. X?"
//   question. The NEXT turn is routed — before the generic yes/no
//   confirmation logic — through extractDateTime(), a small Gemini call
//   that pulls a date/time (handling relative phrasing like "tomorrow")
//   out of the reply. Once both are resolved, it falls into the same
//   proposeBookingFlow() used by propose_booking's direct path, so the
//   already-scheduled / slot-taken checks and the final confirm question
//   are not duplicated logic.
//
// APPOINTMENTS-TABLE REWRITE NOTE (added after diagnosing "appointment
// booked but not showing in the app" bug):
//   This file originally wrote bookings/cancellations/reschedules
//   directly to `encounters` — but the Flutter app's appointments screens
//   (AppointmentRepository / AppointmentDetailsWidget) read from a
//   completely separate `appointments` table, which also backs the
//   dawa-clinician integration (external confirm/decline/reschedule sync,
//   result summaries, etc). `encounters` turned out to be the clinical
//   visit record populated by clinicians after a visit, unrelated to
//   patient-initiated booking. A row inserted into `encounters` by this
//   file was therefore never going to appear anywhere in the app, no
//   matter how correct the agent logic around it was.
//
//   Fixed by retargeting every booking/cancel/reschedule read+write in
//   this file at `appointments` instead. This is not a 1:1 field rename —
//   `appointments` has a meaningfully different shape and RLS model:
//
//   - clinician_id/clinic_id are NOT NULL FKs to doctors(id)/clinics(id).
//     Every doctor offered for booking must have clinic_id set, or the
//     insert fails outright — see the Doctor.clinic_id filtering added to
//     listDoctors/resolvePrimaryDoctor/getDoctorById.
//   - There's no single appointment_time column — start_time/end_time is
//     a real range (CHECK end_time > start_time), with no DB-level
//     overlap/exclusion constraint. Since rudo-chat only ever collects a
//     single spoken time, APPOINTMENT_DURATION_MINUTES below fixes a
//     default appointment length, and isSlotTaken checks for a genuine
//     time-range overlap against existing active appointments rather
//     than an exact match.
//   - RLS's appointments_insert_owner policy forces every patient-created
//     row to status = 'pending' — there is no RLS path for a patient to
//     insert directly as confirmed/scheduled. So a "book" pending_action
//     now results in a *request* that the clinic still has to confirm,
//     not an instant booking — the booking_success copy reflects this.
//   - There is NO RLS UPDATE policy letting a patient change date/time on
//     an existing appointment while keeping it non-cancelled — the only
//     patient-side UPDATE policy (appointments_cancel_owner) only allows
//     a transition to status = 'cancelled'. So "reschedule" is now
//     implemented as cancel the old appointment + insert a brand new
//     pending one, rather than an UPDATE. This is two separate
//     statements, not atomic — if the insert fails after the cancel
//     succeeds, the user is left with neither an old nor a new
//     appointment, which executePendingAction logs loudly and reports
//     distinctly (see reschedule_partial_failure) rather than silently
//     retrying or masking it as an ordinary failure.
//
// UNCLEAR-YES-NO ESCAPE HATCH NOTE (added after diagnosing a "stuck asking
// yes or no forever" bug):
//   The yes/no confirmation branch used to have exactly two exits (yes /
//   no) plus a re-ask on "unclear" — with no way for the user to instead
//   correct or restate their request while a pending_action was active.
//   Garbled STT output surfaced this hard: real user turns like "boke
//   reapment ... mangwanani" (a mangled "book appointment ... in the
//   morning") were classified "unclear" and just triggered the same
//   re-ask forever, because classifyYesNo has no way to say "this isn't
//   a yes/no reply at all, it's a new/changed request."
//   Fixed by treating "unclear" as a soft reset rather than a dead end:
//   pending_action is cleared and the transcript gets a second pass
//   through the normal fresh-turn Gemini tool-classification path (the
//   same one a brand-new "book an appointment" message would take). If
//   THAT also finds nothing actionable — i.e. the transcript really was
//   noise, not a correction — the original pending_action is restored
//   and the same yes/no question is re-asked, so a truly ambiguous
//   utterance still degrades to the old safe behavior instead of
//   silently losing the user's in-progress booking/cancel/reschedule.
//
// ONE-SHOT DATE/TIME RESOLUTION NOTE (added after diagnosing "book an
// appointment for 2pm tomorrow" not resolving in a single turn):
//   runGeminiWithTools previously had no anchor for "today" at all —
//   unlike extractDateTime (used only in the awaiting_datetime follow-up
//   path), it was never told the current date. So when a user gave a
//   date/time in their very first booking message using relative phrasing
//   ("tomorrow", "2pm"), Gemini had no reliable way to resolve it into an
//   absolute YYYY-MM-DD / HH:MM pair and would typically omit date/time
//   from the propose_booking call — safe (falls into awaiting_datetime),
//   but forced an unnecessary extra round-trip every time. Fixed by
//   injecting the same "today's date is X" anchor into
//   runGeminiWithTools's system prompt, plus an explicit instruction (with
//   a worked example) to resolve relative phrasing itself and pass both
//   date and time into propose_booking right away when the user already
//   gave them. The awaiting_datetime flow is unchanged and still serves as
//   the fallback for turns where date/time genuinely weren't mentioned yet.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Env / constants
// ---------------------------------------------------------------------------

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

const SUPABASE_URL = requireEnv("SUPABASE_URL");
const SUPABASE_ANON_KEY = requireEnv("SUPABASE_ANON_KEY");
const GEMINI_API_KEY = requireEnv("GEMINI_API_KEY");
const DAWAMOM_VOICE_BACKEND_URL = requireEnv("DAWAMOM_VOICE_BACKEND_URL");
const GEMINI_MODEL = "gemini-2.5-flash";

// appointments.start_time/end_time is a real range (CHECK end_time >
// start_time), but rudo-chat only ever collects a single spoken time from
// the user — so every booking gets this fixed default duration. Not
// configurable per-doctor/per-visit-type today; revisit if that's ever
// needed.
const APPOINTMENT_DURATION_MINUTES = 30;

// Statuses that count as "this appointment is still live" for booking
// conflict checks (hasScheduledAppointment / isSlotTaken) and for finding
// the "upcoming appointment" to cancel/reschedule. Matches
// appointments_cancel_owner's RLS qual, which only allows cancelling from
// one of these three.
const ACTIVE_APPOINTMENT_STATUSES = ["pending", "confirmed", "rescheduled"];

// Adds `minutes` to a "HH:MM" 24-hour time string, wrapping at midnight.
// Used to derive appointments.end_time from the single start time the
// user gives, since the table requires a real range.
function addMinutesToTime(time: string, minutes: number): string {
  const [h, m] = time.split(":").map((n) => parseInt(n, 10));
  const totalMinutes = h * 60 + m + minutes;
  const wrapped = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60);
  const hh = Math.floor(wrapped / 60).toString().padStart(2, "0");
  const mm = (wrapped % 60).toString().padStart(2, "0");
  return `${hh}:${mm}`;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ChatRequestBody {
  session_id: string;
  message?: string; // text turn
  audio_base64?: string; // voice turn
  filename?: string; // optional original filename for the voice note
  mime_type?: string; // optional mime type for the voice note
  phone_number?: string;
  user_name?: string;
  language?: string;
  source?: string;
}

type Lang = "en" | "sn";

function resolveLang(body: ChatRequestBody): Lang {
  return body.language?.toLowerCase().startsWith("sn") ? "sn" : "en";
}

interface PendingAction {
  type: "book" | "cancel" | "reschedule" | "awaiting_datetime";
  doctor_id?: string; // maps to appointments.clinician_id
  doctorName?: string;
  clinicName?: string;
  // appointments.clinic_id — required NOT NULL FK, captured at proposal
  // time from the resolved Doctor so executePendingAction doesn't need to
  // re-look-up the doctor to build the insert payload.
  clinicId?: string;
  date?: string; // YYYY-MM-DD — appointments.appointment_date
  time?: string; // HH:MM — appointments.start_time (end_time is derived,
  // see APPOINTMENT_DURATION_MINUTES)
  // Target row in `appointments` for cancel/reschedule. Named
  // appointment_id (not encounter_id) since rudo-chat no longer touches
  // `encounters` at all for booking/cancel/reschedule — see the
  // APPOINTMENTS-TABLE REWRITE note at the top of this file.
  appointment_id?: string;
  new_date?: string;
  new_time?: string;
  // Generated once when a "book" pending_action is first proposed, and
  // reused if the confirm step is retried — reduces (though, absent a DB
  // uniqueness constraint on client_idempotency_key today, does not
  // fully guarantee against) duplicate inserts on a retried confirmation.
  idempotencyKey?: string;
  // Language the pending action was proposed in, so the confirmation turn
  // (which arrives without body.language necessarily matching) replies in
  // the same language it asked the question in.
  lang?: Lang;
}

// A doctor offered via list_doctors, kept around just long enough for the
// user to name one back in their next turn.
interface DoctorCandidate {
  id: string;
  name: string;
  clinic_name_legacy: string | null;
}

interface SessionState {
  last_backend_response?: unknown;
  pending_action?: PendingAction | null;
  // Doctors most recently offered via list_doctors, so a bare name in the
  // NEXT turn ("Dr. Chikwanda") can be resolved to a doctor_id. Cleared
  // once a propose_* tool resolves a concrete doctor.
  doctor_candidates?: DoctorCandidate[] | null;
  // Short rolling window of raw user transcripts (oldest first, current
  // turn's transcript included as the last element).
  recent_turns?: string[];
  [key: string]: unknown;
}

interface AgentTurnResult {
  reply: string;
  actionTaken?: string;
  newSessionState: SessionState;
}

interface Doctor {
  id: string;
  name: string;
  clinic_name_legacy: string | null;
  // appointments.clinic_id is a NOT NULL FK to clinics(id) — every doctor
  // offered for booking must have this set, or the insert will fail the
  // FK/NOT NULL constraint. See listDoctors/resolvePrimaryDoctor/
  // getDoctorById, which now filter doctors missing this out entirely.
  clinic_id: string | null;
}

// ---------------------------------------------------------------------------
// Hardcoded reply strings (English + Shona)
// ---------------------------------------------------------------------------

const STRINGS = {
  no_upcoming: {
    en: "You don't have any upcoming appointments scheduled.",
    sn: "Hauna zvirongwa zvekuongororwa zvakarongwa.",
  },
  next_appointment: {
    en: (doctorName: string, date: string, time: string) =>
      `Your next appointment is with ${doctorName} on ${date} at ${time}.`,
    sn: (doctorName: string, date: string, time: string) =>
      `Musangano wako unotevera ndewa${doctorName} pa${date} na${time}.`,
  },
  no_doctors_found: {
    en: "I couldn't find any doctors matching that.",
    sn: "Handina kuwana chiremba anoenderana neizvi.",
  },
  which_doctor: {
    en: (names: string) => `I found ${names}. Who would you like to book with?`,
    sn: (names: string) => `Ndawana ${names}. Ndeupi wauri kuda kubhuka naye?`,
  },
  which_doctor_check: {
    en: "Which doctor would you like me to check?",
    sn: "Ndeupi chiremba waunoda kuti nditarise?",
  },
  slot_taken: {
    en: (date: string, time: string) =>
      `That slot on ${date} at ${time} is already taken — want another time?`,
    sn: (date: string, time: string) =>
      `Nguva iyoyo pa${date} na${time} yatotorwa — unoda nguva imwe?`,
  },
  slot_free: {
    en: (date: string, time: string) =>
      `${date} at ${time} looks free — should I book it?`,
    sn: (date: string, time: string) =>
      `${date} na${time} zvinoita sezvisina munhu — ndibhuke here?`,
  },
  which_doctor_book: {
    en: "Which doctor would you like to book with?",
    sn: "Ndeupi chiremba waunoda kubhuka naye?",
  },
  ask_datetime: {
    en: (doctorName: string) =>
      `Great — when would you like to see ${doctorName}? Give me a date and time.`,
    sn: (doctorName: string) =>
      `Zvakanaka — unoda kuona ${doctorName} rini? Ndipe zuva nenguva.`,
  },
  ask_datetime_retry: {
    en: (doctorName: string) =>
      `Sorry, I didn't catch a date and time for ${doctorName} — could you give me both?`,
    sn: (doctorName: string) =>
      `Ndine hurombo, handina kunzwa zuva nenguva zvakanaka zve${doctorName} — unganditaurira zvese here?`,
  },
  already_scheduled: {
    en: "You already have a scheduled appointment, so I can't book another one right now.",
    sn: "Une zvarongwa zvekuongororwa zvatoripo, saka handikwanise kubhuka zvimwe izvozvi.",
  },
  doctor_not_free: {
    en: (doctorName: string, date: string, time: string) =>
      `${doctorName} isn't free on ${date} at ${time} — want to try another time?`,
    sn: (doctorName: string, date: string, time: string) =>
      `${doctorName} haasi kuwanikwa pa${date} na${time} — unoda kuedza imwe nguva?`,
  },
  confirm_booking: {
    en: (doctorName: string, date: string, time: string) =>
      `Book you with ${doctorName} on ${date} at ${time} — should I confirm?`,
    sn: (doctorName: string, date: string, time: string) =>
      `Ndikubhuke na${doctorName} pa${date} na${time} — ndisimbise here?`,
  },
  no_appointment_cancel: {
    en: "You don't have an appointment to cancel.",
    sn: "Hauna musangano wekukanzura.",
  },
  confirm_cancel: {
    en: "Should I go ahead and cancel your appointment?",
    sn: "Ndoenderera mberi here ndokanzura musangano wako?",
  },
  no_appointment_reschedule: {
    en: "You don't have an appointment to reschedule.",
    sn: "Hauna musangano wekuchinja nguva.",
  },
  confirm_reschedule: {
    en: (date: string, time: string) =>
      `Move your appointment to ${date} at ${time} — should I confirm?`,
    sn: (date: string, time: string) =>
      `Ndochinja musangano wako kuenda pa${date} na${time} — ndisimbise here?`,
  },
  already_scheduled_execute: {
    en: "You already have a scheduled appointment, so I couldn't book this one.",
    sn: "Une musangano watorongwa kare, saka handina kukwanisa kubhuka uyu.",
  },
  slot_taken_execute: {
    en: "That slot was just taken — want me to find another time?",
    sn: "Nguva iyoyo yangotorwa — unoda kuti nditsvage imwe nguva?",
  },
  booking_failed: {
    en: "Something went wrong booking that — mind trying again?",
    sn: "Pane zvakanganisika pakubhuka — ungaedza zvakare here?",
  },
  booking_success: {
    // appointments_insert_owner's RLS forces every patient-created row to
    // status = 'pending' — there is no RLS path to insert as confirmed.
    // So this is a request sent to the clinic, not an instant booking;
    // copy reflects that rather than promising something not guaranteed.
    en: (doctorName: string, date: string, time: string) =>
      `Request sent — I've asked ${doctorName} to confirm ${date} at ${time}. You'll be notified once it's confirmed.`,
    sn: (doctorName: string, date: string, time: string) =>
      `Chikumbiro chatumirwa — ndakumbira ${doctorName} kuti asimbise ${date} na${time}. Uchazivswa kana zvasimbiswa.`,
  },
  nothing_to_cancel: {
    en: "That appointment isn't there anymore — nothing to cancel.",
    sn: "Musangano uyu hauchisipo — hapana chekukanzura.",
  },
  cancel_failed: {
    en: "Something went wrong cancelling that — mind trying again?",
    sn: "Pane zvakanganisika pakukanzura — ungaedza zvakare here?",
  },
  cancel_success: {
    en: "Done — your appointment is cancelled.",
    sn: "Zvaitwa — musangano wako wakanzurwa.",
  },
  not_found_reschedule: {
    en: "I couldn't find that appointment anymore, so I didn't move it.",
    sn: "Handina kuwana musangano iwoyo, saka handina kuuchinja.",
  },
  new_time_taken: {
    en: "That new time isn't free either — want to pick another one?",
    sn: "Nguva itsva iyoyo haisi kuwanikwawo — unoda kusarudza imwe?",
  },
  reschedule_failed: {
    en: "Something went wrong moving that — mind trying again?",
    sn: "Pane zvakanganisika pakuchinja — ungaedza zvakare here?",
  },
  reschedule_success: {
    en: (date: string, time: string) =>
      `Done — your old appointment is cancelled and I've requested ${date} at ${time}. You'll be notified once it's confirmed.`,
    sn: (date: string, time: string) =>
      `Zvaitwa — musangano wako wekare wakanzurwa uye ndakumbira ${date} na${time}. Uchazivswa kana zvasimbiswa.`,
  },
  // Reschedule is implemented as cancel-old + insert-new (two separate
  // statements — no RLS path exists for a patient to UPDATE date/time in
  // place). This is the case where the cancel succeeded but the new
  // request failed to insert, leaving the user with neither appointment —
  // a real partial-failure state, surfaced distinctly rather than masked
  // as an ordinary "something went wrong, try again".
  reschedule_partial_failure: {
    en: "Your old appointment was cancelled, but I couldn't create the new request. Please try booking again — sorry for the trouble.",
    sn: "Musangano wako wekare wakanzurwa, asi handina kukwanisa kugadzira chikumbiro chitsva. Ndapota edza kubhuka zvakare — tine urombo nedambudziko iri.",
  },
  nothing_pending: {
    en: "Nothing pending to confirm.",
    sn: "Hapana chakamirira kusimbiswa.",
  },
  unclear_yes_no: {
    en: "Sorry, was that a yes or a no?",
    sn: "Ndine hurombo, wanga uchiti ehe kana kwete?",
  },
  cancelled_nothing_changed: {
    en: "Okay, cancelled — nothing was changed.",
    sn: "Zvakanaka, zvakanzurwa — hapana chachinja.",
  },
} as const;

function t<K extends keyof typeof STRINGS>(
  key: K,
  lang: Lang,
  ...args: typeof STRINGS[K]["en"] extends (...a: infer A) => string ? A : []
): string {
  const entry = STRINGS[key][lang] ?? STRINGS[key].en;
  return typeof entry === "function"
    ? (entry as (...a: any[]) => string)(...args)
    : (entry as string);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    // Client built with the *caller's* JWT, not a service-role key, so RLS
    // scopes every read/write below to the calling user's own rows.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();
    if (authError || !user) {
      console.log("[rudo-agent] auth failed:", authError);
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body: ChatRequestBody = await req.json();
    if (!body.session_id) {
      return jsonResponse({ error: "session_id is required" }, 400);
    }

    console.log(
      "[rudo-agent] incoming request — userId:",
      user.id,
      "sessionId:",
      body.session_id,
      "hasAudio:",
      Boolean(body.audio_base64),
      "hasMessage:",
      Boolean(body.message),
      "language:",
      body.language,
    );

    if (body.audio_base64) {
      const result = await handleVoiceTurn(supabase, user.id, body);
      return jsonResponse(result);
    }

    if (body.message) {
      const result = await handleTextTurn(supabase, user.id, body);
      return jsonResponse(result);
    }

    return jsonResponse({ error: "Provide either message or audio_base64" }, 400);
  } catch (err) {
    console.error("rudo-chat error:", err);
    return jsonResponse({ error: "Internal error", detail: String(err) }, 500);
  }
});

// ---------------------------------------------------------------------------
// Session state helpers
// ---------------------------------------------------------------------------

async function getSessionState(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<SessionState> {
  const { data, error } = await supabase
    .from("chat_sessions")
    .select("session_state")
    .eq("id", sessionId)
    .maybeSingle();
  if (error) {
    console.error("getSessionState query failed:", error, "sessionId:", sessionId);
  }
  const state = (data?.session_state as SessionState) ?? {};
  console.log(
    "[rudo-agent] loaded session state for",
    sessionId,
    "— pending_action:",
    state.pending_action ? state.pending_action.type : null,
    "doctor_candidates:",
    state.doctor_candidates ? state.doctor_candidates.length : 0,
    "recent_turns:",
    state.recent_turns ? state.recent_turns.length : 0,
  );
  return state;
}

async function saveSessionState(
  supabase: SupabaseClient,
  sessionId: string,
  state: SessionState,
) {
  const { error } = await supabase
    .from("chat_sessions")
    .update({ session_state: state, updated_at: new Date().toISOString() })
    .eq("id", sessionId);
  if (error) {
    console.error("saveSessionState update failed:", error, "sessionId:", sessionId);
  }
}

async function logMessages(
  supabase: SupabaseClient,
  sessionId: string,
  userText: string,
  reply: string,
) {
  const { error } = await supabase.from("chat_messages").insert([
    { session_id: sessionId, role: "user", content: userText },
    { session_id: sessionId, role: "assistant", content: reply },
  ]);
  if (error) {
    console.error("logMessages insert failed:", error, "sessionId:", sessionId);
  }
}

// Appends the current transcript to a capped rolling window of recent user
// turns. Kept small (last 4) so it stays cheap to send to Gemini every turn.
function pushRecentTurn(state: SessionState, transcript: string): string[] {
  const history = [...(state.recent_turns ?? []), transcript];
  return history.slice(-4);
}

// ---------------------------------------------------------------------------
// Voice turn: Sahara relay + appointment agent
// ---------------------------------------------------------------------------

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// api/voice.py (Flask) expects multipart/form-data with:
//   - form field 'user_id' (falls back to 'session_id' server-side, but we
//     always send the real Supabase user id since that's what the mother
//     lookup downstream actually keys on)
//   - file field 'audio' (or 'audio_file') containing the raw audio bytes
//
// It is NOT a JSON endpoint — sending JSON here returns 400 "user_id is
// required" because request.form/request.files are empty for a JSON body.
async function callRudoVoiceBackend(body: ChatRequestBody, userId: string) {
  if (!body.audio_base64) {
    throw new Error("audio_base64 is required for voice turns");
  }

  const audioBytes = base64ToBytes(body.audio_base64);
  const filename = body.filename || "voice_note.m4a";
  const mimeType = body.mime_type || "audio/mp4";

  const form = new FormData();
  form.append("user_id", userId);
  form.append("audio", new Blob([audioBytes], { type: mimeType }), filename);

  const resp = await fetch(DAWAMOM_VOICE_BACKEND_URL, {
    method: "POST",
    body: form,
    // Do NOT set Content-Type manually — fetch derives the correct
    // multipart boundary from the FormData instance automatically.
  });

  if (!resp.ok) {
    const errText = await resp.text().catch(() => "");
    throw new Error(
      `Voice backend returned ${resp.status}${errText ? `: ${errText}` : ""}`,
    );
  }
  return (await resp.json()) as { transcript?: string; reply?: string };
}

async function handleVoiceTurn(
  supabase: SupabaseClient,
  userId: string,
  body: ChatRequestBody,
) {
  const lang = resolveLang(body);
  const backendReply = await callRudoVoiceBackend(body, userId);
  const transcript = backendReply.transcript ?? "";

  console.log(
    "[rudo-agent] voice turn transcript:",
    JSON.stringify(transcript),
    "backend reply:",
    JSON.stringify(backendReply.reply ?? ""),
  );

  const sessionState = await getSessionState(supabase, body.session_id);

  let finalReply = backendReply.reply ?? "";
  let actionTaken: string | undefined;
  let newSessionState = sessionState;

  if (transcript.trim().length > 0) {
    const agentResult = await runAppointmentAgent(supabase, {
      userId,
      sessionId: body.session_id,
      transcript,
      sessionState,
      lang,
    });

    console.log(
      "[rudo-agent] voice turn agent result — engaged:",
      agentResult.engaged,
      "actionTaken:",
      agentResult.actionTaken,
    );

    // The appointment agent only speaks up when it actually engaged with
    // a booking-related turn (proposed/confirmed/refused/answered a
    // read query). Otherwise it returns the backend's own reply untouched.
    if (agentResult.engaged) {
      finalReply = agentResult.reply;
      actionTaken = agentResult.actionTaken;
    } else {
      console.log(
        "[rudo-agent] voice turn NOT engaged — falling back to backend reply verbatim",
      );
    }
    newSessionState = agentResult.newSessionState;
  }

  newSessionState.last_backend_response = backendReply;
  await saveSessionState(supabase, body.session_id, newSessionState);
  await logMessages(supabase, body.session_id, transcript, finalReply);

  return {
    session_id: body.session_id,
    transcript,
    reply: finalReply,
    action_taken: actionTaken,
  };
}

async function handleTextTurn(
  supabase: SupabaseClient,
  userId: string,
  body: ChatRequestBody,
) {
  const lang = resolveLang(body);
  const transcript = body.message ?? "";
  const sessionState = await getSessionState(supabase, body.session_id);

  console.log("[rudo-agent] text turn transcript:", JSON.stringify(transcript));

  const agentResult = await runAppointmentAgent(supabase, {
    userId,
    sessionId: body.session_id,
    transcript,
    sessionState,
    lang,
  });

  console.log(
    "[rudo-agent] text turn agent result — engaged:",
    agentResult.engaged,
    "actionTaken:",
    agentResult.actionTaken,
  );

  let reply = agentResult.reply;
  if (!agentResult.engaged) {
    console.log(
      "[rudo-agent] text turn NOT engaged — falling back to generalGeminiReply (plain Q&A)",
    );
    // Fall back to the general Gemini text pipeline for anything that
    // isn't appointment-related.
    reply = await generalGeminiReply(transcript, lang);
  }

  await saveSessionState(supabase, body.session_id, agentResult.newSessionState);
  await logMessages(supabase, body.session_id, transcript, reply);

  return { session_id: body.session_id, reply, action_taken: agentResult.actionTaken };
}

// ---------------------------------------------------------------------------
// Appointment agent
// ---------------------------------------------------------------------------

async function runAppointmentAgent(
  supabase: SupabaseClient,
  input: {
    userId: string;
    sessionId: string;
    transcript: string;
    sessionState: SessionState;
    lang: Lang;
  },
): Promise<AgentTurnResult & { engaged: boolean }> {
  // 1. Resolve mother_id from profile_id — every tool call needs this.
  const { data: mother, error: motherError } = await supabase
    .from("mothers")
    .select("id, first_encounter_id")
    .eq("profile_id", input.userId)
    .maybeSingle();
  if (motherError) {
    console.error("runAppointmentAgent mother lookup failed:", motherError, "userId:", input.userId);
  }

  console.log(
    "[rudo-agent] mother lookup — profile_id:",
    input.userId,
    "found:",
    Boolean(mother),
    "mother_id:",
    mother?.id ?? null,
    "first_encounter_id:",
    mother?.first_encounter_id ?? null,
  );

  if (!mother) {
    console.log(
      "[rudo-agent] BYPASS: no mother row found for profile_id",
      input.userId,
      "— agent will not engage this turn",
    );
    return { engaged: false, reply: "", newSessionState: input.sessionState };
  }

  // 2. Check for a pending confirmation / slot-fill from the previous
  //    turn first — this takes priority over any new intent
  //    classification.
  const pending = input.sessionState.pending_action ?? null;
  console.log(
    "[rudo-agent] pending_action for mother",
    mother.id,
    ":",
    pending ? JSON.stringify(pending) : null,
  );

  if (pending) {
    const pendingLang = pending.lang ?? input.lang;

    // 2a. Awaiting a date/time for a doctor already picked. This is NOT
    //     a yes/no turn — extract a date/time from the user's reply
    //     instead of classifying it as a confirmation.
    if (pending.type === "awaiting_datetime") {
      const extracted = await extractDateTime(input.transcript);
      console.log(
        "[rudo-agent] awaiting_datetime extraction for transcript:",
        JSON.stringify(input.transcript),
        "=>",
        JSON.stringify(extracted),
      );

      if (!extracted.date || !extracted.time) {
        // Still missing one or both — re-ask, keep the pending state so
        // the doctor choice isn't lost.
        return {
          engaged: true,
          reply: t("ask_datetime_retry", pendingLang, pending.doctorName ?? ""),
          newSessionState: input.sessionState,
        };
      }

      const doctor: Doctor = {
        id: pending.doctor_id!,
        name: pending.doctorName ?? "",
        clinic_name_legacy: pending.clinicName ?? null,
      };
      const result = await proposeBookingFlow(
        supabase,
        mother.id,
        doctor,
        extracted.date,
        extracted.time,
        pendingLang,
      );
      return {
        engaged: true,
        ...result,
        newSessionState: { ...input.sessionState, ...result.newSessionState },
      };
    }

    // 2b. Ordinary yes/no confirmation for book/cancel/reschedule.
    const yesNo = await classifyYesNo(input.transcript);
    console.log(
      "[rudo-agent] pending_action yes/no classification for transcript:",
      JSON.stringify(input.transcript),
      "=>",
      yesNo,
    );

    if (yesNo === "yes") {
      const result = await executePendingAction(supabase, mother.id, input.userId, pending, pendingLang);
      return {
        engaged: true,
        ...result,
        newSessionState: { ...input.sessionState, ...result.newSessionState },
      };
    }
    if (yesNo === "no") {
      return {
        engaged: true,
        reply: t("cancelled_nothing_changed", pendingLang),
        newSessionState: { ...input.sessionState, pending_action: null },
      };
    }
    // Neither a clear yes nor no. Previously this just re-asked the same
    // yes/no question forever — but "unclear" doesn't only happen on
    // genuinely garbled STT output; it also fires when the user is
    // legitimately trying to CORRECT or RESTATE their request instead of
    // answering yes/no (e.g. "no wait, tomorrow morning instead", or a
    // partially-garbled restatement like "boke reapment ... mangwanani").
    // Re-asking the same question in that case traps the user in an
    // infinite loop with no way out.
    //
    // So: clear pending_action here and fall through to the normal
    // fresh-turn classification path below (section 3), giving Gemini a
    // chance to pick up a new/corrected intent from this same transcript.
    // If that ALSO comes back with nothing actionable, the fallback at
    // the bottom of section 3 restores this exact pending_action and
    // re-asks the original yes/no question — so a truly ambiguous
    // utterance ("hmm", noise) still degrades to the old safe behavior
    // instead of silently dropping the pending booking/cancel/reschedule.
    console.log(
      "[rudo-agent] pending_action yes/no UNCLEAR — clearing pending_action and re-attempting fresh-turn classification for transcript:",
      JSON.stringify(input.transcript),
      "(will restore pending_action and re-ask if nothing actionable is found)",
    );
  }

  // 3. No pending action (or a pending yes/no confirmation that came back
  //    "unclear" and was cleared above so this transcript gets a second
  //    chance as a fresh request): classify + let Gemini call tools.
  //    Carry forward conversational memory (recent transcripts + any
  //    doctor candidates just offered) so a follow-up like "Dr.
  //    Chikwanda" can be resolved against what was just asked, instead of
  //    being classified in a vacuum.
  const sessionStateForFreshTurn: SessionState = pending
    ? { ...input.sessionState, pending_action: null }
    : input.sessionState;

  const primaryDoctor = await resolvePrimaryDoctor(supabase, mother.id);
  console.log(
    "[rudo-agent] primaryDoctor resolved:",
    primaryDoctor ? `${primaryDoctor.name} (${primaryDoctor.id})` : null,
  );

  const recentTurns = pushRecentTurn(sessionStateForFreshTurn, input.transcript);
  const doctorCandidates = sessionStateForFreshTurn.doctor_candidates ?? null;

  const toolResult = await runGeminiWithTools(
    input.transcript,
    primaryDoctor,
    recentTurns,
    doctorCandidates,
  );
  console.log(
    "[rudo-agent] runGeminiWithTools result:",
    toolResult ? JSON.stringify(toolResult) : null,
  );

  if (!toolResult) {
    if (pending) {
      // We cleared a stale pending_action hoping this transcript was a
      // correction/new request, but Gemini found no appointment-related
      // intent in it either — most likely genuinely garbled/ambiguous
      // input. Restore the original pending_action and re-ask, rather
      // than silently dropping the user's in-progress booking/cancel/
      // reschedule.
      const pendingLang = pending.lang ?? input.lang;
      console.log(
        "[rudo-agent] fresh-turn classification also found nothing actionable — restoring pending_action and re-asking for transcript:",
        JSON.stringify(input.transcript),
      );
      return {
        engaged: true,
        reply: t("unclear_yes_no", pendingLang),
        newSessionState: { ...sessionStateForFreshTurn, pending_action: pending, recent_turns: recentTurns },
      };
    }
    console.log(
      "[rudo-agent] BYPASS: Gemini returned no functionCall for transcript:",
      JSON.stringify(input.transcript),
      "— agent will not engage this turn (falls through to general Q&A)",
    );
    return {
      engaged: false,
      reply: "",
      newSessionState: { ...sessionStateForFreshTurn, recent_turns: recentTurns },
    };
  }

  const result = await executeAgentTool(supabase, mother.id, toolResult, primaryDoctor, input.lang);
  return {
    ...result,
    newSessionState: {
      ...sessionStateForFreshTurn,
      ...result.newSessionState,
      recent_turns: recentTurns,
    },
  };
}

// ---------------------------------------------------------------------------
// Primary doctor resolution
// ---------------------------------------------------------------------------

async function resolvePrimaryDoctor(
  supabase: SupabaseClient,
  motherId: string,
): Promise<Doctor | null> {
  const { data: mother, error: motherError } = await supabase
    .from("mothers")
    .select("first_encounter_id")
    .eq("id", motherId)
    .maybeSingle();
  if (motherError) {
    console.error("resolvePrimaryDoctor mother lookup failed:", motherError, "motherId:", motherId);
  }

  if (!mother?.first_encounter_id) {
    console.log("[rudo-agent] resolvePrimaryDoctor: no first_encounter_id for mother", motherId);
    return null;
  }

  const { data: firstEncounter, error: encounterError } = await supabase
    .from("first_encounters")
    .select("doctor_id")
    .eq("id", mother.first_encounter_id)
    .maybeSingle();
  if (encounterError) {
    console.error(
      "resolvePrimaryDoctor first_encounter lookup failed:",
      encounterError,
      "first_encounter_id:",
      mother.first_encounter_id,
    );
  }

  if (!firstEncounter?.doctor_id) {
    console.log(
      "[rudo-agent] resolvePrimaryDoctor: no doctor_id on first_encounter",
      mother.first_encounter_id,
    );
    return null;
  }

  // clinic_id is a NOT NULL FK on appointments — a doctor missing it (or
  // inactive/not bookable, or a junk/incomplete directory row) can't be
  // booked through here even if they're technically this mother's
  // first_encounter doctor. Filtering happens in the query itself so a
  // disqualified doctor comes back as "no primary doctor" rather than
  // being silently offered and then failing at insert time.
  const { data: doctor, error: doctorError } = await supabase
    .from("doctors")
    .select("id, name, clinic_name_legacy, clinic_id")
    .eq("id", firstEncounter.doctor_id)
    .eq("is_active", true)
    .eq("is_bookable", true)
    .not("clinic_id", "is", null)
    .not("name", "is", null)
    .maybeSingle();
  if (doctorError) {
    console.error(
      "resolvePrimaryDoctor doctor lookup failed:",
      doctorError,
      "doctor_id:",
      firstEncounter.doctor_id,
    );
  }

  return (doctor as Doctor) ?? null;
}

async function listDoctors(
  supabase: SupabaseClient,
  filter?: string,
): Promise<Doctor[]> {
  // Same bookability filtering as resolvePrimaryDoctor — never offer a
  // doctor the user could pick and then have booking fail on, whether
  // from missing clinic_id, being inactive/non-bookable, or a junk
  // directory row with no name.
  let query = supabase
    .from("doctors")
    .select("id, name, clinic_name_legacy, clinic_id")
    .eq("is_active", true)
    .eq("is_bookable", true)
    .not("clinic_id", "is", null)
    .not("name", "is", null);
  if (filter) {
    query = query.or(
      `name.ilike.%${filter}%,clinic_name_legacy.ilike.%${filter}%`,
    );
  }
  const { data, error } = await query.limit(10);
  if (error) {
    console.error("listDoctors query failed:", error, "filter:", filter);
  }
  console.log(
    "[rudo-agent] listDoctors — filter:",
    filter ?? null,
    "rowCount:",
    data?.length ?? 0,
  );
  return (data as Doctor[]) ?? [];
}

// Fetches a single doctor by id directly, instead of pulling an unfiltered
// page of doctors and hoping the target is in the first 10 (that bug let
// propose_booking silently fall back to the wrong doctor for anyone
// outside the first page — see propose_booking below).
async function getDoctorById(
  supabase: SupabaseClient,
  doctorId: string,
): Promise<Doctor | null> {
  // Same bookability filtering as listDoctors/resolvePrimaryDoctor — if
  // Gemini names a doctor_id (e.g. from a candidate list offered earlier
  // in the same session), it must still pass these checks here, in case
  // the doctor's bookability changed between being listed and being
  // picked.
  const { data, error } = await supabase
    .from("doctors")
    .select("id, name, clinic_name_legacy, clinic_id")
    .eq("id", doctorId)
    .eq("is_active", true)
    .eq("is_bookable", true)
    .not("clinic_id", "is", null)
    .not("name", "is", null)
    .maybeSingle();
  if (error) {
    console.error("getDoctorById query failed:", error, "doctorId:", doctorId);
  }
  return (data as Doctor) ?? null;
}

// ---------------------------------------------------------------------------
// Read-only + slot-check helpers
// ---------------------------------------------------------------------------

async function getUpcomingAppointment(supabase: SupabaseClient, motherId: string) {
  // status.in(ACTIVE_APPOINTMENT_STATUSES) — 'pending' (not yet confirmed
  // by the clinic) still counts as "your upcoming appointment" from the
  // patient's point of view; 'declined'/'completed'/'cancelled'/'missed'
  // don't.
  const { data, error } = await supabase
    .from("appointments")
    .select("id, clinician_id, appointment_date, start_time, end_time, status, doctors(name, clinic_name_legacy)")
    .eq("mother_id", motherId)
    .in("status", ACTIVE_APPOINTMENT_STATUSES)
    .order("appointment_date", { ascending: true })
    .order("start_time", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) {
    console.error("getUpcomingAppointment query failed:", error, "motherId:", motherId);
  }
  return data;
}

async function hasScheduledAppointment(supabase: SupabaseClient, motherId: string) {
  const { data, error } = await supabase
    .from("appointments")
    .select("id")
    .eq("mother_id", motherId)
    .in("status", ACTIVE_APPOINTMENT_STATUSES)
    .maybeSingle();
  if (error) {
    console.error("hasScheduledAppointment query failed:", error, "motherId:", motherId);
  }
  return Boolean(data);
}

// appointments has no DB-level exclusion/overlap constraint, so this is
// enforced entirely in application logic — same race-condition caveat as
// the original design notes already called out (re-checked again at
// execution time in executePendingAction, not just here at proposal
// time). `time` is the requested START time; this checks for a genuine
// time-range overlap against any other ACTIVE appointment for the same
// doctor on the same date, using the fixed APPOINTMENT_DURATION_MINUTES
// to derive an end time (existing.start < new.end AND existing.end >
// new.start).
async function isSlotTaken(
  supabase: SupabaseClient,
  doctorId: string,
  date: string,
  time: string,
) {
  const endTime = addMinutesToTime(time, APPOINTMENT_DURATION_MINUTES);
  const { data, error } = await supabase
    .from("appointments")
    .select("id")
    .eq("clinician_id", doctorId)
    .eq("appointment_date", date)
    .in("status", ACTIVE_APPOINTMENT_STATUSES)
    .lt("start_time", endTime)
    .gt("end_time", time)
    .maybeSingle();
  if (error) {
    console.error(
      "isSlotTaken query failed:",
      error,
      "doctorId:",
      doctorId,
      "date:",
      date,
      "time:",
      time,
    );
  }
  return Boolean(data);
}

// ---------------------------------------------------------------------------
// Shared booking-proposal flow — used both by propose_booking (when the
// tool call already includes date/time) and by the awaiting_datetime
// resolution path (once a date/time is extracted from a follow-up turn).
// Re-checks the two booking invariants and, if clear, sets a "book"
// pending_action asking for final confirmation. Never writes to
// `encounters` itself — see executePendingAction for that.
// ---------------------------------------------------------------------------

async function proposeBookingFlow(
  supabase: SupabaseClient,
  motherId: string,
  doctor: Doctor,
  date: string,
  time: string,
  lang: Lang,
): Promise<AgentTurnResult> {
  // Defensive check — every caller today resolves Doctor through
  // listDoctors/resolvePrimaryDoctor/getDoctorById, which already filter
  // out doctors missing clinic_id, but this function shouldn't silently
  // build an insert payload that's guaranteed to fail the NOT NULL FK if
  // that ever changes.
  if (!doctor.clinic_id) {
    console.error(
      "[rudo-agent] proposeBookingFlow: doctor missing clinic_id, refusing to propose",
      "doctor_id:",
      doctor.id,
    );
    return {
      reply: t("which_doctor_book", lang),
      newSessionState: { pending_action: null, doctor_candidates: null },
    };
  }

  const alreadyScheduled = await hasScheduledAppointment(supabase, motherId);
  if (alreadyScheduled) {
    return {
      reply: t("already_scheduled", lang),
      newSessionState: { pending_action: null, doctor_candidates: null },
    };
  }

  const taken = await isSlotTaken(supabase, doctor.id, date, time);
  if (taken) {
    return {
      reply: t("doctor_not_free", lang, doctor.name, date, time),
      newSessionState: { pending_action: null, doctor_candidates: null },
    };
  }

  // doctor.clinic_id is guaranteed non-null here — listDoctors/
  // resolvePrimaryDoctor/getDoctorById all filter out doctors missing it
  // before a Doctor object ever reaches this function.
  const pending: PendingAction = {
    type: "book",
    doctor_id: doctor.id,
    doctorName: doctor.name,
    clinicName: doctor.clinic_name_legacy ?? undefined,
    clinicId: doctor.clinic_id!,
    date,
    time,
    idempotencyKey: crypto.randomUUID(),
    lang,
  };
  return {
    reply: t("confirm_booking", lang, doctor.name, date, time),
    newSessionState: { pending_action: pending, doctor_candidates: null },
  };
}

// ---------------------------------------------------------------------------
// Gemini: tool-calling classification for a fresh (non-pending) turn
// ---------------------------------------------------------------------------

type AgentToolCall =
  | { name: "get_upcoming_appointment"; args: Record<string, never> }
  | { name: "list_doctors"; args: { specialty_or_clinic?: string } }
  | { name: "check_doctor_slot"; args: { doctor_id?: string; date: string; time: string } }
  | { name: "propose_booking"; args: { doctor_id?: string; date?: string; time?: string } }
  | { name: "propose_cancel"; args: { appointment_id?: string } }
  | { name: "propose_reschedule"; args: { appointment_id?: string; new_date: string; new_time: string } };

const TOOL_DECLARATIONS = [
  {
    name: "get_upcoming_appointment",
    description: "Look up the user's next scheduled appointment.",
    parameters: { type: "OBJECT", properties: {} },
  },
  {
    name: "list_doctors",
    description:
      "Browse available doctors, optionally filtered by name or clinic. Only use this if the user wants someone other than their primary doctor, or has no primary doctor.",
    parameters: {
      type: "OBJECT",
      properties: { specialty_or_clinic: { type: "STRING" } },
    },
  },
  {
    name: "check_doctor_slot",
    description: "Check whether a given doctor is free at a given date and time.",
    parameters: {
      type: "OBJECT",
      properties: {
        doctor_id: { type: "STRING" },
        date: { type: "STRING", description: "YYYY-MM-DD" },
        time: { type: "STRING", description: "HH:MM 24-hour" },
      },
      required: ["date", "time"],
    },
  },
  {
    name: "propose_booking",
    description:
      "Propose booking an appointment. Does NOT book anything yet — only asks the user to confirm. Call this as soon as a doctor is identified, even if date and time are not yet known — omit date/time in that case and the app will ask the user for them separately. If the user's message already gives a date and/or time (including relative phrasing like 'tomorrow' or '2pm'), resolve it into YYYY-MM-DD / HH:MM yourself and pass both in immediately.",
    parameters: {
      type: "OBJECT",
      properties: {
        doctor_id: { type: "STRING" },
        date: { type: "STRING", description: "YYYY-MM-DD, omit if not yet known" },
        time: { type: "STRING", description: "HH:MM 24-hour, omit if not yet known" },
      },
      // Deliberately no `required` here (previously required ["date",
      // "time"]). A doctor can now be resolved via this same tool before
      // a date/time is known — see the awaiting_datetime pending_action
      // flow in runAppointmentAgent, which picks up from here.
    },
  },
  {
    name: "propose_cancel",
    description: "Propose cancelling the user's upcoming appointment. Does not cancel yet.",
    parameters: {
      type: "OBJECT",
      properties: { appointment_id: { type: "STRING" } },
    },
  },
  {
    name: "propose_reschedule",
    description:
      "Propose moving the user's upcoming appointment to a new date/time. Does not change anything yet — and note that under the hood this will cancel the existing appointment and create a new pending request, since there's no way to move an appointment's time in place.",
    parameters: {
      type: "OBJECT",
      properties: {
        appointment_id: { type: "STRING" },
        new_date: { type: "STRING", description: "YYYY-MM-DD" },
        new_time: { type: "STRING", description: "HH:MM 24-hour" },
      },
      required: ["new_date", "new_time"],
    },
  },
];

// NOTE: deliberately no language-output instruction here. This call's own
// text output (if the model doesn't call a tool) is never shown to the
// user — only whether it emits a functionCall matters. Adding "respond
// only in Shona" here previously caused the model to satisfy that
// instruction with plain-text Shona prose instead of calling a tool,
// which broke intent detection for Shona voice/text turns. The model
// already understands Shona input without being told to; it just
// shouldn't be told to constrain its output language for this call.
//
// It IS given today's date (see `today` below) so it can resolve relative
// date/time phrasing ("tomorrow", "2pm") on a fresh booking turn without
// needing a second round-trip through the awaiting_datetime flow — see the
// ONE-SHOT DATE/TIME RESOLUTION NOTE at the top of this file.
async function runGeminiWithTools(
  transcript: string,
  primaryDoctor: Doctor | null,
  recentTurns: string[] = [],
  doctorCandidates: DoctorCandidate[] | null = null,
): Promise<AgentToolCall | null> {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD, server clock

  let systemPrompt = `Today's date is ${today} (server clock, use this to resolve any relative date/time the user gives).\n\n`;

  systemPrompt += primaryDoctor
    ? `This mother's primary doctor is ${primaryDoctor.name} at ${primaryDoctor.clinic_name_legacy ?? "their clinic"} (doctor_id: ${primaryDoctor.id}). Default to this doctor for booking/rescheduling unless the user explicitly asks for someone else.`
    : `This mother has no primary doctor on file. If they want to book, use list_doctors first so they can choose.`;

  systemPrompt += `\n\nIf the user's message already includes a date and/or time — including relative phrasing like "tomorrow", "next Tuesday", "2pm", "2 in the afternoon" — resolve it yourself into an absolute date (YYYY-MM-DD) and 24-hour time (HH:MM) using today's date above, and pass BOTH into propose_booking right away instead of leaving them blank. Only omit date/time from propose_booking if the user genuinely hasn't mentioned them yet. Example: if today is ${today} and the user says "tomorrow at 2pm", call propose_booking with the next calendar day as date and "14:00" as time.`;

  if (doctorCandidates && doctorCandidates.length > 0) {
    const candidateList = doctorCandidates
      .map(
        (d) =>
          `- ${d.name} (doctor_id: ${d.id})${d.clinic_name_legacy ? `, at ${d.clinic_name_legacy}` : ""}`,
      )
      .join("\n");
    systemPrompt += `\n\nYou just asked the user which of these doctors they'd like to book with:\n${candidateList}\nIf the user's latest message names or clearly refers to one of them (even just a first name, nickname, or partial match), call propose_booking with that exact doctor_id right away — you do NOT need a date/time yet to call this, omit those fields if they aren't known and the app will ask the user for them next.`;
  }

  if (recentTurns.length > 1) {
    // recentTurns already includes the current transcript as its last
    // element (the caller appends before calling this), so treat
    // everything before it as prior context and the last one as what to
    // act on.
    const prior = recentTurns.slice(0, -1);
    systemPrompt += `\n\nEarlier in this same conversation, the user also said (oldest first):\n${prior
      .map((tprev) => `- "${tprev}"`)
      .join("\n")}\nUse this only as context for interpreting their latest message below — decide what to do based on the latest message, informed by this history (e.g. a date/time mentioned earlier still applies if the user hasn't changed it).`;
  }

  systemPrompt += `\n\nIf the message is not about appointments (booking, cancelling, rescheduling, or asking about an upcoming visit), call no tool. The user's message may be written in Shona or English — understand it in either language and call the appropriate tool regardless of which language it's in.`;

  console.log("[rudo-agent] runGeminiWithTools systemPrompt:", systemPrompt);

  let resp: Response;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt }] },
          contents: [{ role: "user", parts: [{ text: transcript }] }],
          tools: [{ function_declarations: TOOL_DECLARATIONS }],
        }),
      },
    );
  } catch (err) {
    console.error("[rudo-agent] runGeminiWithTools fetch threw:", err);
    return null;
  }

  if (!resp.ok) {
    console.error("[rudo-agent] Gemini tool-call request failed, status:", resp.status, "body:", await resp.text());
    return null;
  }

  const data = await resp.json();

  const candidate = data?.candidates?.[0];
  console.log(
    "[rudo-agent] Gemini tools raw response — finishReason:",
    candidate?.finishReason,
    "parts:",
    JSON.stringify(candidate?.content?.parts ?? null),
  );
  if (data?.promptFeedback?.blockReason) {
    console.log(
      "[rudo-agent] Gemini tools call BLOCKED — blockReason:",
      data.promptFeedback.blockReason,
    );
  }

  const call = candidate?.content?.parts?.find(
    (p: { functionCall?: unknown }) => p.functionCall,
  )?.functionCall;

  if (!call) {
    console.log(
      "[rudo-agent] Gemini did not emit a functionCall for transcript:",
      JSON.stringify(transcript),
      "— it likely answered in plain text instead (see parts above), or genuinely had nothing to act on yet",
    );
    return null;
  }
  console.log("[rudo-agent] Gemini functionCall:", call.name, JSON.stringify(call.args));
  return { name: call.name, args: call.args ?? {} } as AgentToolCall;
}

// ---------------------------------------------------------------------------
// Small Gemini calls for forgiving yes/no classification (voice STT noise)
// ---------------------------------------------------------------------------

// No language-output instruction needed here either — the model is told to
// always reply with the literal English word "yes"/"no"/"unclear" regardless
// of what language the input was in, and that output is never shown to the
// user (only parsed).
async function classifyYesNo(transcript: string): Promise<"yes" | "no" | "unclear"> {
  let resp: Response;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: {
            parts: [
              {
                text:
                  'Classify the user message as confirming ("yes"), declining ("no"), or neither ("unclear"). Reply with exactly one of those three words and nothing else (always in English, regardless of the input language). Voice transcripts may be noisy and may be in Shona or English — "yeah", "go ahead", "sure", "that works", "ehe", "hongu", "zvakanaka" all count as yes; "no", "cancel that", "not now", "don\'t", "kwete", "aiwa" all count as no.',
              },
            ],
          },
          contents: [{ role: "user", parts: [{ text: transcript }] }],
        }),
      },
    );
  } catch (err) {
    console.error("[rudo-agent] classifyYesNo fetch threw:", err);
    return "unclear";
  }

  if (!resp.ok) {
    console.error("[rudo-agent] classifyYesNo request failed, status:", resp.status);
    return "unclear";
  }
  const data = await resp.json();
  const text = (data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "")
    .trim()
    .toLowerCase();
  console.log("[rudo-agent] classifyYesNo raw text:", JSON.stringify(text));
  if (text.startsWith("yes")) return "yes";
  if (text.startsWith("no")) return "no";
  return "unclear";
}

// ---------------------------------------------------------------------------
// Small Gemini call to extract a date/time from a follow-up turn while a
// "awaiting_datetime" pending_action is active. Handles relative phrasing
// ("tomorrow", "next Tuesday") using the server's current date as a
// reference point. Output is parsed JSON, never shown to the user
// directly — same "no language constraint needed" reasoning as the other
// classification helpers above.
// ---------------------------------------------------------------------------

async function extractDateTime(
  transcript: string,
): Promise<{ date: string | null; time: string | null }> {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD, server clock

  let resp: Response;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: {
            parts: [
              {
                text: `Today's date is ${today}. Extract an appointment date and time from the user's message below, which may be in Shona or English and may use relative phrasing ("tomorrow", "next Tuesday", "3 in the afternoon", "mangwana", "manheru"). Respond with ONLY a JSON object, no markdown fencing, no commentary, in exactly this shape: {"date": "YYYY-MM-DD" or null, "time": "HH:MM" or null (24-hour)}. If either the date or the time isn't present or can't be confidently resolved, use null for that field rather than guessing.`,
              },
            ],
          },
          contents: [{ role: "user", parts: [{ text: transcript }] }],
        }),
      },
    );
  } catch (err) {
    console.error("[rudo-agent] extractDateTime fetch threw:", err);
    return { date: null, time: null };
  }

  if (!resp.ok) {
    console.error("[rudo-agent] extractDateTime request failed, status:", resp.status);
    return { date: null, time: null };
  }

  const data = await resp.json();
  const raw = (data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "").trim();
  console.log("[rudo-agent] extractDateTime raw text:", JSON.stringify(raw));

  try {
    const cleaned = raw.replace(/^```json\s*|```\s*$/g, "").trim();
    const parsed = JSON.parse(cleaned);
    return {
      date: typeof parsed?.date === "string" ? parsed.date : null,
      time: typeof parsed?.time === "string" ? parsed.time : null,
    };
  } catch (err) {
    console.error("[rudo-agent] extractDateTime JSON parse failed:", err, "raw:", raw);
    return { date: null, time: null };
  }
}

// ---------------------------------------------------------------------------
// Executing a tool call for a fresh turn (produces a spoken reply, and for
// propose_* tools, a pending_action — never a DB write to `encounters`)
// ---------------------------------------------------------------------------

async function executeAgentTool(
  supabase: SupabaseClient,
  motherId: string,
  call: AgentToolCall,
  primaryDoctor: Doctor | null,
  lang: Lang,
): Promise<AgentTurnResult & { engaged: boolean }> {
  console.log("[rudo-agent] executeAgentTool:", call.name, JSON.stringify(call.args));

  switch (call.name) {
    case "get_upcoming_appointment": {
      const appt = await getUpcomingAppointment(supabase, motherId);
      if (!appt) {
        return {
          engaged: true,
          reply: t("no_upcoming", lang),
          newSessionState: {},
        };
      }
      const doctorName = (appt as { doctors?: { name?: string } }).doctors?.name ?? "your doctor";
      return {
        engaged: true,
        reply: t("next_appointment", lang, doctorName, appt.appointment_date, appt.start_time),
        newSessionState: {},
      };
    }

    case "list_doctors": {
      const doctors = await listDoctors(supabase, call.args.specialty_or_clinic);
      if (doctors.length === 0) {
        return {
          engaged: true,
          reply: t("no_doctors_found", lang),
          newSessionState: { doctor_candidates: null },
        };
      }
      const names = doctors
        .map((d) => `${d.name}${d.clinic_name_legacy ? ` at ${d.clinic_name_legacy}` : ""}`)
        .join(", ");
      return {
        engaged: true,
        reply: t("which_doctor", lang, names),
        newSessionState: {
          doctor_candidates: doctors.map((d) => ({
            id: d.id,
            name: d.name,
            clinic_name_legacy: d.clinic_name_legacy,
          })),
        },
      };
    }

    case "check_doctor_slot": {
      const doctorId = call.args.doctor_id ?? primaryDoctor?.id;
      if (!doctorId) {
        return {
          engaged: true,
          reply: t("which_doctor_check", lang),
          newSessionState: {},
        };
      }
      const taken = await isSlotTaken(supabase, doctorId, call.args.date, call.args.time);
      return {
        engaged: true,
        reply: taken
          ? t("slot_taken", lang, call.args.date, call.args.time)
          : t("slot_free", lang, call.args.date, call.args.time),
        newSessionState: {},
      };
    }

    case "propose_booking": {
      // Fetch the specific requested doctor directly by id — previously
      // this pulled an unfiltered page of doctors (limit 10) and did a
      // .find() over it, which silently fell back to primaryDoctor for
      // anyone not in that first page. getDoctorById fixes that.
      const doctor = call.args.doctor_id
        ? (await getDoctorById(supabase, call.args.doctor_id)) ?? primaryDoctor
        : primaryDoctor;

      if (!doctor) {
        return {
          engaged: true,
          reply: t("which_doctor_book", lang),
          newSessionState: {},
        };
      }

      // Doctor is resolved but no date/time yet: park a deterministic
      // "awaiting_datetime" pending action and ask for it explicitly,
      // instead of hoping the next turn resolves cleanly on its own.
      if (!call.args.date || !call.args.time) {
        const pending: PendingAction = {
          type: "awaiting_datetime",
          doctor_id: doctor.id,
          doctorName: doctor.name,
          clinicName: doctor.clinic_name_legacy ?? undefined,
          lang,
        };
        return {
          engaged: true,
          reply: t("ask_datetime", lang, doctor.name),
          newSessionState: { pending_action: pending, doctor_candidates: null },
        };
      }

      const result = await proposeBookingFlow(
        supabase,
        motherId,
        doctor,
        call.args.date,
        call.args.time,
        lang,
      );
      return { engaged: true, ...result };
    }

    case "propose_cancel": {
      const appt = call.args.appointment_id
        ? { id: call.args.appointment_id }
        : await getUpcomingAppointment(supabase, motherId);
      if (!appt) {
        return {
          engaged: true,
          reply: t("no_appointment_cancel", lang),
          newSessionState: { doctor_candidates: null },
        };
      }
      const pending: PendingAction = { type: "cancel", appointment_id: appt.id, lang };
      return {
        engaged: true,
        reply: t("confirm_cancel", lang),
        newSessionState: { pending_action: pending, doctor_candidates: null },
      };
    }

    case "propose_reschedule": {
      const appt = call.args.appointment_id
        ? { id: call.args.appointment_id }
        : await getUpcomingAppointment(supabase, motherId);
      if (!appt) {
        return {
          engaged: true,
          reply: t("no_appointment_reschedule", lang),
          newSessionState: { doctor_candidates: null },
        };
      }
      const pending: PendingAction = {
        type: "reschedule",
        appointment_id: appt.id,
        new_date: call.args.new_date,
        new_time: call.args.new_time,
        lang,
      };
      return {
        engaged: true,
        reply: t("confirm_reschedule", lang, call.args.new_date, call.args.new_time),
        newSessionState: { pending_action: pending, doctor_candidates: null },
      };
    }

    default:
      console.log("[rudo-agent] executeAgentTool: unrecognized tool name", (call as { name?: string }).name);
      return { engaged: false, reply: "", newSessionState: {} };
  }
}

// ---------------------------------------------------------------------------
// Executing a CONFIRMED pending action — the only place `encounters` is
// ever written. Re-checks both invariants immediately before writing.
// ---------------------------------------------------------------------------

async function executePendingAction(
  supabase: SupabaseClient,
  motherId: string,
  userId: string,
  pending: PendingAction,
  lang: Lang,
): Promise<AgentTurnResult> {
  console.log("[rudo-agent] executePendingAction:", JSON.stringify(pending), "motherId:", motherId, "userId:", userId);

  if (pending.type === "book") {
    const alreadyScheduled = await hasScheduledAppointment(supabase, motherId);
    if (alreadyScheduled) {
      console.log("[rudo-agent] executePendingAction(book): rejected — already has an active appointment");
      return {
        reply: t("already_scheduled_execute", lang),
        newSessionState: { pending_action: null },
      };
    }

    const taken = await isSlotTaken(supabase, pending.doctor_id!, pending.date!, pending.time!);
    if (taken) {
      console.log("[rudo-agent] executePendingAction(book): rejected — slot taken between propose and confirm");
      return {
        reply: t("slot_taken_execute", lang),
        newSessionState: { pending_action: null },
      };
    }

    const endTime = addMinutesToTime(pending.time!, APPOINTMENT_DURATION_MINUTES);

    // status/source/integration_status are forced to these exact values
    // by appointments_insert_owner's RLS with_check anyway — set
    // explicitly here rather than relying on column defaults, so this
    // insert is self-documenting and doesn't silently depend on defaults
    // matching the policy.
    const { error } = await supabase.from("appointments").insert({
      mother_id: motherId,
      patient_id: userId,
      clinician_id: pending.doctor_id,
      clinic_id: pending.clinicId,
      appointment_date: pending.date,
      start_time: pending.time,
      end_time: endTime,
      appointment_type: "maternal_health",
      status: "pending",
      source: "dawa_mom",
      created_by: userId,
      integration_status: "pending",
      client_idempotency_key: pending.idempotencyKey ?? crypto.randomUUID(),
    });
    if (error) {
      console.error("Booking insert failed:", error);
      return {
        reply: t("booking_failed", lang),
        newSessionState: { pending_action: null },
      };
    }

    console.log("[rudo-agent] executePendingAction(book): SUCCESS (status=pending, awaiting clinic confirmation)");
    return {
      reply: t("booking_success", lang, pending.doctorName ?? "", pending.date ?? "", pending.time ?? ""),
      actionTaken: "appointment_requested",
      newSessionState: { pending_action: null },
    };
  }

  if (pending.type === "cancel") {
    const { data: appt, error: fetchError } = await supabase
      .from("appointments")
      .select("id, status")
      .eq("id", pending.appointment_id)
      .maybeSingle();
    if (fetchError) {
      console.error("Cancel lookup failed:", fetchError, "appointment_id:", pending.appointment_id);
    }

    if (!appt || !ACTIVE_APPOINTMENT_STATUSES.includes(appt.status)) {
      console.log("[rudo-agent] executePendingAction(cancel): nothing to cancel");
      return {
        reply: t("nothing_to_cancel", lang),
        newSessionState: { pending_action: null },
      };
    }

    const { error } = await supabase
      .from("appointments")
      .update({ status: "cancelled" })
      .eq("id", pending.appointment_id);
    if (error) {
      console.error("Cancel update failed:", error);
      return {
        reply: t("cancel_failed", lang),
        newSessionState: { pending_action: null },
      };
    }

    console.log("[rudo-agent] executePendingAction(cancel): SUCCESS");
    return {
      reply: t("cancel_success", lang),
      actionTaken: "appointment_cancelled",
      newSessionState: { pending_action: null },
    };
  }

  if (pending.type === "reschedule") {
    // There is no RLS UPDATE policy letting a patient change date/time on
    // an existing appointment while keeping it non-cancelled — the only
    // patient UPDATE policy allows a transition to status='cancelled'
    // and nothing else. So this is genuinely cancel-old + insert-new, not
    // an UPDATE — two separate statements, not atomic. See the
    // APPOINTMENTS-TABLE REWRITE note at the top of this file.
    const { data: appt, error: fetchError } = await supabase
      .from("appointments")
      .select("id, status, clinician_id, clinic_id, mother_id")
      .eq("id", pending.appointment_id)
      .maybeSingle();
    if (fetchError) {
      console.error("Reschedule lookup failed:", fetchError, "appointment_id:", pending.appointment_id);
    }

    if (!appt || !ACTIVE_APPOINTMENT_STATUSES.includes(appt.status)) {
      console.log("[rudo-agent] executePendingAction(reschedule): appointment not found / not active");
      return {
        reply: t("not_found_reschedule", lang),
        newSessionState: { pending_action: null },
      };
    }

    const taken = await isSlotTaken(
      supabase,
      appt.clinician_id,
      pending.new_date!,
      pending.new_time!,
    );
    if (taken) {
      console.log("[rudo-agent] executePendingAction(reschedule): new slot taken");
      return {
        reply: t("new_time_taken", lang),
        newSessionState: { pending_action: null },
      };
    }

    const { error: cancelError } = await supabase
      .from("appointments")
      .update({ status: "cancelled" })
      .eq("id", appt.id);
    if (cancelError) {
      console.error("Reschedule (cancel step) failed:", cancelError);
      return {
        reply: t("reschedule_failed", lang),
        newSessionState: { pending_action: null },
      };
    }

    const newEndTime = addMinutesToTime(pending.new_time!, APPOINTMENT_DURATION_MINUTES);
    const { error: insertError } = await supabase.from("appointments").insert({
      mother_id: appt.mother_id,
      patient_id: userId,
      clinician_id: appt.clinician_id,
      clinic_id: appt.clinic_id,
      appointment_date: pending.new_date,
      start_time: pending.new_time,
      end_time: newEndTime,
      appointment_type: "maternal_health",
      status: "pending",
      source: "dawa_mom",
      created_by: userId,
      integration_status: "pending",
      client_idempotency_key: pending.idempotencyKey ?? crypto.randomUUID(),
    });
    if (insertError) {
      // The old appointment IS cancelled at this point — this is a real
      // partial-failure state (neither old nor new appointment exists as
      // active), not an ordinary "nothing changed" failure. Logged loudly
      // and reported with distinct copy rather than the generic
      // reschedule_failed message, since telling the user "nothing was
      // changed" here would be actively wrong.
      console.error(
        "[rudo-agent] executePendingAction(reschedule): PARTIAL FAILURE — old appointment",
        appt.id,
        "was cancelled but the new request insert failed:",
        insertError,
      );
      return {
        reply: t("reschedule_partial_failure", lang),
        newSessionState: { pending_action: null },
      };
    }

    console.log("[rudo-agent] executePendingAction(reschedule): SUCCESS (old cancelled, new request pending)");
    return {
      reply: t("reschedule_success", lang, pending.new_date ?? "", pending.new_time ?? ""),
      actionTaken: "appointment_rescheduled",
      newSessionState: { pending_action: null },
    };
  }

  console.log("[rudo-agent] executePendingAction: unrecognized pending.type", (pending as { type?: string }).type);
  return { reply: t("nothing_pending", lang), newSessionState: { pending_action: null } };
}

// ---------------------------------------------------------------------------
// General (non-appointment) text fallback
// ---------------------------------------------------------------------------

// This call's output IS shown to the user, so it's the right place (along
// with the hardcoded STRINGS table) to enforce reply language.
function languageInstruction(lang: Lang): string {
  return lang === "sn"
    ? "Respond only in Shona (chiShona)."
    : "Respond only in English.";
}

async function generalGeminiReply(transcript: string, lang: Lang): Promise<string> {
  console.log(
    "[rudo-agent] generalGeminiReply invoked (plain Q&A path) for transcript:",
    JSON.stringify(transcript),
  );

  let resp: Response;
  try {
    resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: {
            parts: [
              {
                text: `You are Rudo, a warm, concise maternal-health assistant for DawaMom. ${languageInstruction(lang)}`,
              },
            ],
          },
          contents: [{ role: "user", parts: [{ text: transcript }] }],
        }),
      },
    );
  } catch (err) {
    console.error("[rudo-agent] generalGeminiReply fetch threw:", err);
    return lang === "sn"
      ? "Ndine hurombo, handina kunzwa zvawataura — unganditaurira zvakare?"
      : "Sorry, I didn't catch that — could you say it again?";
  }

  if (!resp.ok) {
    console.error("[rudo-agent] generalGeminiReply request failed, status:", resp.status);
    return lang === "sn"
      ? "Ndine hurombo, handina kunzwa zvawataura — unganditaurira zvakare?"
      : "Sorry, I didn't catch that — could you say it again?";
  }
  const data = await resp.json();
  return (
    data?.candidates?.[0]?.content?.parts?.[0]?.text ??
    (lang === "sn" ? "Ndine hurombo, handina kunzwa." : "Sorry, I didn't catch that.")
  );
}