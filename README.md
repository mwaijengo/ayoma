# AyomaMax

Livestream app for live TV, football and movies, with an admin app and API. The user app, admin app, and API follow the same screens and behavior as UhuruMax.

| Folder | What it is |
| --- | --- |
| `/` (root) | **AyomaMax** user app (Flutter). Swahili UI, SonicPesa checkout, native Android player (HLS/DASH, ClearKey, Widevine, Referer/Origin headers). |
| `ayoma_admin/` | **AyomaMax Admin** app (Flutter). Password-only login (24-hour sessions): channels, carousel, packages, users, payments, notifications, maintenance, must-update, refresh apps, danger zone. |
| `backend/` | API (Node.js, Express, Postgres). Deploys to Railway. SonicPesa payments and Firebase push. |

## Run locally

```bash
# API with an embedded Postgres (admin password: ayoma-admin)
cd backend && npm install && npm run dev:local

# Apps against the local API (Android emulator); without API_URL they use the live API
flutter run --dart-define=API_URL=http://10.0.2.2:8080
cd ayoma_admin && flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

## Production

- **API:** set the variables from `backend/.env.example` on Railway (`DATABASE_URL`, `JWT_SECRET`, `ADMIN_PASSWORD`, SonicPesa keys, `FCM_SERVICE_ACCOUNT_JSON`).
- **Apps:** both connect to `https://uhurumax-production.up.railway.app` by default; `--dart-define=API_URL=...` overrides it.
- **Push (user app):** also pass `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID` and `FIREBASE_PROJECT_ID` as `--dart-define`s.
