import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type NotificationRow = {
  id: string;
  title: string | null;
  body: string | null;
  task_id: string | null;
  recipient_user_id: string;
};

type DeviceRow = {
  id: string;
  native_push_token: string;
  platform: "android" | "ios";
};

type ServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: jsonHeaders,
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_secret:${name}`);
  return value;
}

function base64UrlEncode(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToBytes(pem: string): Uint8Array {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function createGoogleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64UrlEncode(
    JSON.stringify({
      iss: account.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(account.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`google_oauth_failed:${response.status}:${await response.text()}`);
  }
  const result = await response.json() as { access_token?: string };
  if (!result.access_token) throw new Error("google_oauth_missing_access_token");
  return result.access_token;
}

function serviceAccountFromEnv(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")?.trim();
  if (raw) {
    const parsed = JSON.parse(raw) as {
      project_id?: string;
      client_email?: string;
      private_key?: string;
    };
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      throw new Error("invalid_firebase_service_account_json");
    }
    return {
      projectId: parsed.project_id,
      clientEmail: parsed.client_email,
      privateKey: parsed.private_key,
    };
  }
  return {
    projectId: requiredEnv("FIREBASE_PROJECT_ID"),
    clientEmail: requiredEnv("FIREBASE_CLIENT_EMAIL"),
    privateKey: requiredEnv("FIREBASE_PRIVATE_KEY"),
  };
}

async function sendToFcm(
  accessToken: string,
  projectId: string,
  device: DeviceRow,
  notification: NotificationRow,
): Promise<{ ok: boolean; invalidToken: boolean; detail?: string }> {
  const data: Record<string, string> = {
    notificationId: notification.id,
    taskId: notification.task_id ?? "",
    route: "/tasks",
  };
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: device.native_push_token,
          notification: {
            title: notification.title ?? "تنبيه جديد",
            body: notification.body ?? "لديك إشعار جديد في NEXORA",
          },
          data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "alshaeri_notifications",
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
    },
  );
  if (response.ok) return { ok: true, invalidToken: false };
  const detail = await response.text();
  const invalidToken =
    response.status === 404 ||
    detail.includes("UNREGISTERED") ||
    detail.includes("INVALID_ARGUMENT");
  return { ok: false, invalidToken, detail };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const webhookSecret = requiredEnv("FCM_WEBHOOK_SECRET");
    if (request.headers.get("x-webhook-secret") !== webhookSecret) {
      return json({ error: "unauthorized" }, 401);
    }

    const payload = await request.json() as { notification_id?: string };
    const notificationId = payload.notification_id?.trim();
    if (!notificationId) return json({ error: "notification_id_required" }, 400);

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: notification, error: notificationError } = await admin
      .from("notifications")
      .select("id,title,body,task_id,recipient_user_id")
      .eq("id", notificationId)
      .maybeSingle<NotificationRow>();
    if (notificationError) throw notificationError;
    if (!notification) return json({ error: "notification_not_found" }, 404);

    const { data: devices, error: devicesError } = await admin
      .from("notification_devices")
      .select("id,native_push_token,platform")
      .eq("user_id", notification.recipient_user_id)
      .eq("is_enabled", true)
      .limit(100);
    if (devicesError) throw devicesError;

    const account = serviceAccountFromEnv();
    const accessToken = await createGoogleAccessToken(account);
    const results = [];
    for (const device of (devices ?? []) as DeviceRow[]) {
      const result = await sendToFcm(accessToken, account.projectId, device, notification);
      results.push({ id: device.id, platform: device.platform, ...result });
      if (result.invalidToken) {
        await admin
          .from("notification_devices")
          .update({ is_enabled: false, updated_at: new Date().toISOString() })
          .eq("id", device.id);
      }
    }

    return json({ notification_id: notificationId, attempted: results.length, results });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "internal_error" }, 500);
  }
});
