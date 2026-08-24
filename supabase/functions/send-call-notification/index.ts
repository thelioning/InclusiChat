import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

type CallNotificationRequest = {
  call_id: string;
  conversation_id: string;
  receiver_id: string;
  call_type: "audio" | "video";
};

const isValidCallId = (value: string) =>
  /^call_[0-9]+$/.test(value) ||
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const firebaseB64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !firebaseB64) {
    return json({ error: "Server configuration incomplete" }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const callerId = userData.user?.id;
  if (userError || !callerId) return json({ error: "Invalid session" }, 401);

  let body: CallNotificationRequest;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (
    !isValidCallId(body.call_id ?? "") ||
    !/^[0-9a-f-]{36}$/i.test(body.conversation_id ?? "") ||
    !/^[0-9a-f-]{36}$/i.test(body.receiver_id ?? "") ||
    !["audio", "video"].includes(body.call_type) ||
    callerId === body.receiver_id
  ) {
    return json({ error: "Invalid call request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data: participants, error: participantError } = await admin
    .from("conversation_participants")
    .select("user_id")
    .eq("conversation_id", body.conversation_id)
    .in("user_id", [callerId, body.receiver_id])
    .is("left_at", null);
  if (participantError || participants?.length !== 2) {
    return json({ error: "Conversation membership denied" }, 403);
  }

  const { data: caller } = await admin
    .from("profiles")
    .select("display_name,avatar_url")
    .eq("id", callerId)
    .maybeSingle();
  const { data: tokenRows, error: tokenError } = await admin
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", body.receiver_id);
  if (tokenError) return json({ error: "Token lookup failed" }, 500);
  if (!tokenRows?.length) return json({ delivered: 0, reason: "no_devices" });

  const serviceAccount = JSON.parse(
    new TextDecoder().decode(
      Uint8Array.from(atob(firebaseB64), (character) => character.charCodeAt(0)),
    ),
  );
  const auth = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const accessToken = await auth.getAccessToken();
  if (!accessToken.token) return json({ error: "FCM authorization failed" }, 502);

  const callerName = caller?.display_name ?? "Contacto";
  const data = {
    event: "incoming_call",
    call_id: body.call_id,
    conversation_id: body.conversation_id,
    caller_id: callerId,
    caller_name: callerName,
    caller_avatar: caller?.avatar_url ?? "",
    receiver_id: body.receiver_id,
    call_type: body.call_type,
  };
  let delivered = 0;
  const invalidTokens: string[] = [];
  for (const row of tokenRows) {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken.token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: row.token,
            data,
            android: {
              priority: "high",
              ttl: "35s",
              collapse_key: body.call_id,
            },
          },
        }),
      },
    );
    if (response.ok) {
      delivered++;
    } else {
      const failure = await response.text();
      if (failure.includes("UNREGISTERED")) invalidTokens.push(row.token);
      console.error("FCM send failed", response.status, failure);
    }
  }
  if (invalidTokens.length) {
    await admin.from("device_push_tokens").delete().in("token", invalidTokens);
  }
  return json({ delivered });
});
