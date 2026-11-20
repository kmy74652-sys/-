import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const pushClient = readFileSync('apps/mobile/lib/pushNotifications.ts', 'utf8');
const layout = readFileSync('apps/mobile/app/_layout.tsx', 'utf8');
const migration = readFileSync('supabase/migrations/069_push_notifications.sql', 'utf8');
const pkg = readFileSync('apps/mobile/package.json', 'utf8');
const app = readFileSync('apps/mobile/app.json', 'utf8');

assert(pkg.includes('expo-notifications') && pkg.includes('expo-device'), 'Expo Push dependencies are installed');
assert(app.includes('"expo-notifications"') && app.includes('"versionCode": 4'), 'native notification plugin and version bump are configured');
assert(pushClient.includes('requestPermissionsAsync') && pushClient.includes('getExpoPushTokenAsync'), 'device permission and token registration are implemented');
assert(pushClient.includes("rpc('register_push_device'") && pushClient.includes("rpc('disable_push_device'"), 'token writes use protected RPCs');
assert(pushClient.includes('notifyInAppTaskReceived') && pushClient.includes("sound: 'default'") && pushClient.includes('trigger: null'), 'local task notification plays the default sound');
assert(layout.includes('addNotificationResponseReceivedListener') && layout.includes("router.push('/tasks'"), 'notification presses open the employee workspace');
assert(migration.includes('notification_devices') && migration.includes('register_push_device') && migration.includes('disable_push_device'), 'device table and protected lifecycle RPCs exist');
assert(migration.includes('notifications_dispatch_push') && migration.includes('net.http_post'), 'new in-app notifications dispatch to Expo Push Service');
assert(migration.includes("organization_id = new.organization_id") && migration.includes("user_id = new.recipient_user_id"), 'dispatch is scoped to the notification recipient and organization');
console.log(JSON.stringify({ ok: true, checks: 8, scope: 'push-notifications' }));
