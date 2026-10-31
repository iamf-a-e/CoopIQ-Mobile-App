# gemini-proxy

Edge Function that holds the Gemini key. The app sends questions and photos here;
the function checks the user is signed in, enforces an hourly limit, calls Gemini and
returns the answer.

Limits per user per hour: 60 chat messages, 20 diagnoses. Change `LIMITS` in index.ts.

## Deploy

```bash
supabase login
supabase link --project-ref bpimmhuezwuiobctzygd
supabase secrets set GEMINI_API_KEY=your_new_key
supabase functions deploy gemini-proxy --no-verify-jwt
```

`--no-verify-jwt` is intentional: the function verifies the user itself with
Supabase Auth, which also works with newer project signing keys.

Run `supabase/migrations/20261003120000_ai_usage.sql` in the SQL editor first.
