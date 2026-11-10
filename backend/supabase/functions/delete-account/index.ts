// Supprime définitivement le compte de l'utilisateur et, par cascade, ses compteurs d'usage et droits.
import { createClient } from "npm:@supabase/supabase-js@2.119.0";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data } = await admin.auth.getUser(token);
  if (!data?.user) return new Response(JSON.stringify({ error: "Session expirée." }), { status: 401 });
  const { error } = await admin.auth.admin.deleteUser(data.user.id);
  if (error) return new Response(JSON.stringify({ error: "Suppression impossible pour le moment." }), { status: 500 });
  return new Response(JSON.stringify({ deleted: true }), { headers: { "Content-Type": "application/json" } });
});
