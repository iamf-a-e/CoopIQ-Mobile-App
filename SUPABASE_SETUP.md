# Connecting CoopIQ to Supabase

1. **Create the tables.** Supabase dashboard > SQL Editor > New query > paste
   `supabase/migrations/20261003000000_init.sql` > Run. Do this once per project.

2. **Auth settings.** Authentication > Providers > Email must be enabled.
   While developing, switch off "Confirm email" so sign-up logs in straight away.
   If you leave it on, the app tells the user to confirm by email first.

3. **Copy your keys.** Project Settings > API: the Project URL and the anon (public) key.
   Do not use the service_role key anywhere in the app.

4. **Create `env.json`** next to `pubspec.yaml` (copy `env.example.json`), fill it in,
   and make sure it is in `.gitignore`.

5. **Run.**
   ```bash
   flutter pub get
   flutter run -d <device> --dart-define-from-file=env.json
   ```

6. **Make an agrovet or admin** (run in the SQL editor after that person has signed up):
   ```sql
   update public.profiles set role = 'agrovet' where email = 'agrovet@example.com';
   ```

## Quick test

- Sign up, then check Table Editor > profiles for your row.
- Flock tab > Start a batch: a row appears in flocks and five rows in flock_vaccinations.
- Diagnose a photo: a row in diagnoses and the image in Storage > diagnosis-images/<your user id>/.
- Ask a question: two rows in chat_messages.
- Agrovet tab > send a request: a row in consultations or farm_visits.
