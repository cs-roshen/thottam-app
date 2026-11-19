// The project's public address and publishable (anon) key, from the Supabase dashboard
// (Project settings → API). Both are public by design; the service-role key must never
// be put here. Every console action goes through the admin functions in
// supabase/migrations/0006_admin_console.sql, which check that the signed-in person is
// an admin.
window.THOTTAM_ADMIN = {
  url: 'https://YOUR-PROJECT-REF.supabase.co',
  publishableKey: 'YOUR-PUBLISHABLE-KEY',
};
