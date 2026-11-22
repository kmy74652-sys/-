# Flutter mobile app — Alshaeri

This is the in-progress Flutter client alongside the original Expo/React Native app. The migration is based on the supplied repository state and preserves the existing Supabase project, employee accounts, RPC/Edge Function contracts, and RLS boundaries. The Expo source under `../mobile` remains intact and is the behavior reference.

## Migration status

The Flutter application is **not yet a full-parity replacement and is not release-ready**. It currently contains Flutter implementations for Arabic RTL startup and routing; employee-code authentication and session/profile loading; the branded home shell and role/permission-aware navigation; task list search/status/priority filters and pagination; task details, dynamic report/task fields, evidence attachments, signatures, task execution and review; an initial per-user offline action queue; task reports plus read/review for employee role reports; report and organizational task designers; performance analytics; employee account create/edit/activate/suspend, set/change/revoke login codes, audit history and confirmed permanent deletion; organization name/tagline/logo settings; initial HR, agreements and administration screens; and in-app notification list/count UI.

Implementation depth varies by feature. Some administration/HR/agreement paths still need a full behavior-by-behavior comparison with Expo. Employee role reports and independent employee report submission now have Arabic Flutter screens using the existing contracts, including table editing, signature capture, choice fields, and small embedded attachments; the independent-report backend has no separate storage contract, so embedded attachments are intentionally limited to 2 MB per file until an approved contract is added. Display-name joins, direct CSV file export, and some reviewer controls remain incomplete. Offline queuing and retries are initial implementations and still need lifecycle, concurrency, file-upload and device testing. The current Flutter notification work does **not** port Expo push-device registration or foreground/local push notification behavior. The existing backend stores Expo push tokens; Flutter token registration must not be improvised or silently substituted without a compatible, explicitly supported backend contract.

A successful static analysis is not evidence of UI, backend, device, or release parity. No APK has been built or verified in this environment. `flutter doctor -v` reports no Android SDK; there is also no configured iOS toolchain. The machine is ARM64 and the available Flutter tool is invoked through its bundled ARM64 Dart runtime rather than a PATH-installed `flutter` binary.

## Configure and run

Install a Flutter stable SDK plus the Android SDK/platform/build tools (or Xcode for iOS), then from this directory:

```sh
flutter pub get
flutter analyze
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY
```

In the current sandbox the equivalent source-tool invocation is:

```sh
DART=/home/ubuntu/tools/flutter/bin/cache/dart-sdk/bin/dart
TOOL=/home/ubuntu/tools/flutter/packages/flutter_tools/bin/flutter_tools.dart
"$DART" "$TOOL" pub get
"$DART" "$TOOL" analyze
```

Only the Supabase URL and public anon/publishable key belong in a client build. Never put a `service_role` key in Flutter, source control, or build arguments. RLS and backend authorization remain authoritative. The Android scaffold uses application ID `com.alshaeri.mobile`, display name «مانجمنت», internet permission, and deep-link scheme `alshaeri`; signing compatibility with the currently installed Expo Android app has not been established. Do not assume the original private signing key is available.

## Backend and data safety

The Flutter client uses the existing Supabase project and its established tables, RPCs, Edge Functions, storage, and policies. Do not run migrations against production or change the database as part of this client migration without explicit authorization. In particular, preserve the existing employee-code authentication flow and use the supported credential Edge Function; do not write credentials or auth tables directly. Permanent employee deletion is a destructive owner action and is guarded by an explicit confirmation in the UI.

The app currently relies on existing contracts including `mobile_my_profile`, task update/report/step/timeline RPCs, `employee-code-auth`, `employee_role_reports` review, and the organization branding save path. Inspect the Expo implementation and matching migrations in `../../supabase` before modifying any contract. Never introduce service-role credentials into the mobile app.

## What remains before replacing Expo

Complete a screen/action/permission parity matrix against `../mobile`, especially branch administration, employee and HR edge cases, report export and review, all designer workflows, notification/push migration, deep links, offline conflict handling, accessibility and timezone behavior. Then add/execute unit and widget tests, validate authenticated Supabase flows against a non-production environment, install and exercise the Android/iOS apps on real devices, and perform a verified native build. An install-over-existing-app update additionally requires confirmation that the Android package ID and signing key match the published Expo app. Until those steps are complete, keep the Expo app as the production client and treat Flutter as an in-progress migration.
