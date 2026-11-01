// Supabase の「Project Settings → API」に表示される2つの値を貼り付けてください。
// anon key は公開しても安全な鍵です（データの守りはデータベース側のルールで行っています）。
window.APP_CONFIG = {
  SUPABASE_URL: "https://xxxxxxxxxxxx.supabase.co",
  SUPABASE_ANON_KEY: "ここに anon public key を貼り付け",
  // Googleログインを使わない場合は false に
  ENABLE_GOOGLE: true
};
