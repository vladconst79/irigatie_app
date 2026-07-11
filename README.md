# Irigatie App

Flutter client for the Irigatie HTTP gateway. The app gives a mobile/desktop/web
dashboard for monitoring the irrigation daemon, running watering commands, and
editing schedules, zones, and manual watering presets.

## Features

- Live dashboard for daemon state, runtime details, queue depth, database status,
  relay state, and 24-hour rainfall totals.
- Schedule management: create, edit, delete, and execute schedules.
- Manual watering presets: execute and edit existing manual programs.
- Zone management: edit zone name/type/enabled state and run relay tests.
- Watering history sheet with cursor-based pagination.
- Runtime API settings screen backed by local preferences.

## Requirements

- Flutter SDK compatible with Dart `^3.12.0`.
- A reachable Irigatie HTTP gateway.
- Gateway token, unless the gateway is running without authentication.

The gateway contract is maintained in the sibling backend repository at:

```text
../irigatie/api/irigatie-gateway.openapi.yaml
```

## API Configuration

The app loads API settings in this order:

1. Saved settings from the in-app Configuration screen.
2. `assets/config/irigatie_app.json`.
3. Dart compile-time environment values.
4. Empty defaults, which make requests relative to the current origin.

Create a local config file from the sample:

```sh
cp assets/config/irigatie_app.sample.json assets/config/irigatie_app.json
```

Example:

```json
{
  "apiUrl": "https://irigatie.example.com/api/",
  "apiToken": "replace-with-irigatie-http-gateway-token"
}
```

`apiUrl` may point either at the gateway root or at `/api`; the client normalizes
paths before making requests. Tokens are sent as:

```text
Authorization: Bearer <token>
```

You can also configure the app at build/run time:

```sh
flutter run \
  --dart-define=IRIGATIE_API_URL=https://irigatie.example.com/api \
  --dart-define=IRIGATIE_API_TOKEN=replace-with-token
```

## Gateway Endpoints Used

The current app uses these gateway routes:

- `GET /api/snapshot`
- `GET /api/watering-history`
- `POST /api/manual/execute`
- `PATCH /api/manual/{program_id}`
- `POST /api/zones/test`
- `PATCH /api/zones/{zone_id}`
- `POST /api/stop`
- `POST /api/schedules`
- `PATCH /api/schedules/{schedule_id}`
- `DELETE /api/schedules/{schedule_id}`
- `POST /api/schedules/{schedule_id}/execute`

## Development

Install dependencies:

```sh
flutter pub get
```

Run the app:

```sh
flutter run
```

Run on web:

```sh
flutter run -d chrome
```

Run tests:

```sh
flutter test
```

Run static analysis:

```sh
flutter analyze
```

## Build

Build web assets:

```sh
flutter build web --release
```

Build Android:

```sh
flutter build apk --release
```

Build iOS from macOS with Xcode installed:

```sh
flutter build ios --release
```

## Project Layout

```text
lib/main.dart                         Flutter app, models, API client, screens
assets/config/irigatie_app.sample.json Sample API configuration
docs/                                Backend/API implementation notes
test/widget_test.dart                Smoke test for the dashboard
web/                                 Web shell and PWA metadata
```

## Notes

- The app is intentionally tolerant of partially degraded snapshots. A database
  read failure can still render gateway/runtime status where the API provides it.
- Manual program create/delete UI is not currently wired because those endpoints
  are not part of the active gateway contract.
- Do not commit `assets/config/irigatie_app.json` if it contains a real token.
