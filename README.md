# CMA正誤トレーナー（Supabase + Vercel 版）

証券アナリストの正誤問題を解き、1問ごとの **解答時間** と **正誤** を記録するWebアプリです。
受講者は **Googleアカウント** か **メールアドレス＋パスワード** でログインします。
講師は受講者別の偏差値・論点別の弱点・問題別の正答率を分析できます。

## 主な機能
- **本番モード**：範囲（すべて／科目ごと）と問題数（10・20・30・50問・すべて・自由入力）を選び、ランダムに出題。正誤と解説は最後にまとめて表示。途中で終了して採点も可。
- **3択で解答**：「○」「×」「わからない」。わからないは不正解として採点し、割合も記録（知識不足か思い違いかを見分けられる）。
- **ランキング**：10問以上を最後まで解いた試験の自己ベスト（正答率→1問あたりの時間の中央値）／直近30日の解答数。名前を出したくない人は非表示にできる。
- **学習ポイント**：テキスト「この章で学ぶこと」の番号（1001〜1026）で問題を整理。
- **解説動画**：講師画面で学習ポイントごとにYouTubeのURLを登録すると、間違えた問題・弱い論点から直接飛べる。
- **講師用分析**：偏差値、学習ポイント×受講者の弱点マップ、問題別正答率、個別の指導優先順位。
- 解答時間は**中央値**で集計（極端に遅い1回に引っ張られない）。

## 問題数
科目Ⅱ 財務分析は第1〜5回で各200問・計1,000問（`seed_finance.sql` の100問＋`seed_finance_extra.sql` の900問）。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `index.html` | アプリ本体（画面・計測・分析） |
| `config.js` | Supabase の接続情報（ここだけ書き換える） |
| `supabase/schema.sql` | テーブル・権限ルール（最初に1回実行） |
| `supabase/seed_questions.sql` | 学習ポイントと問題データ（問題を増やすときもこれを編集して実行） |
| `dev/` | スマホ表示の確認用（公開されません） |
| `CLAUDE.md` | Claudeに作業してもらうときのルール |

ビルド作業は不要です。HTMLをそのまま公開するだけで動きます。

---

## セットアップ手順（30分ほど）

### 1. Supabase（データベースとログイン）
1. https://supabase.com で無料アカウントを作り、「New project」でプロジェクトを作成（リージョンは Tokyo を推奨）。
2. 左メニュー **SQL Editor** → 「New query」に `supabase/schema.sql` の中身を貼って **Run**。
3. 同じく `supabase/seed_questions.sql` を貼って **Run**（問題10問が入ります）。
4. **Project Settings → API** を開き、`Project URL` と `anon public` キーを `config.js` に貼り付け。

### 2. メールログインの設定
**Authentication → Sign In / Providers → Email** を開く。
- 最初は **「Confirm email」をオフ** にするのがおすすめです。Supabase標準のメール送信は1時間に数通までしか送れないため、確認メールが届かない人が出ます。
- 本格運用で確認メールを使いたくなったら、**Authentication → SMTP Settings** で Resend などのメール送信サービスを設定してからオンにします。

### 3. Googleログインの設定（使わないなら `config.js` の `ENABLE_GOOGLE` を `false` にして飛ばしてOK）
1. https://console.cloud.google.com でプロジェクトを作成。
2. 「APIとサービス → OAuth同意画面」を設定（ユーザーの種類：外部、アプリ名・メールを入力、公開ステータスを「本番」に）。
3. 「認証情報 → 認証情報を作成 → OAuthクライアントID」→ 種類「ウェブアプリケーション」。
   - **承認済みのリダイレクトURI** に `https://＜あなたのプロジェクトID＞.supabase.co/auth/v1/callback` を追加。
4. 表示された **クライアントID** と **シークレット** を、Supabase の **Authentication → Sign In / Providers → Google** に貼って有効化。

### 4. GitHub にアップロード
1. https://github.com で「New repository」（Private で可）。
2. 「uploading an existing file」から、このフォルダの中身をすべてドラッグ＆ドロップして Commit。

### 5. Vercel で公開
1. https://vercel.com に GitHub アカウントでログイン → 「Add New → Project」→ さきほどのリポジトリを Import。
2. Framework Preset は「Other」のまま **Deploy**。数十秒で `https://xxxx.vercel.app` のURLができます。
3. Supabase の **Authentication → URL Configuration** で
   - **Site URL** に Vercel のURLを入力
   - **Redirect URLs** にも同じURLを追加（ローカルで試すなら `http://localhost:3000` なども）

以後は GitHub のファイルを更新するたびに、Vercel が自動で再公開します。

### 6. 自分を「講師」にする
公開したURLで一度ログインしたあと、Supabase の SQL Editor で次を実行します（メールアドレスは自分のものに）。

```sql
update public.profiles set role = 'teacher' where email = 'あなたのメールアドレス';
```

ページを再読み込みすると「講師用 分析」タブが表示されます。受講者にはURLを送るだけです。

---

## データの守り方
- 受講者は **自分の記録しか読めません**。全員分を読めるのは role が `teacher` の人だけです。
- 受講者の画面には **正答が送られません**。○×を押すとサーバー側で採点し、その問題の正答と解説だけを返します。
- 解答の記録はサーバー側の関数（`submit_answer`）経由でしか書き込めず、正誤を書き換えることはできません。
- 同じ問題を二重に送信しても、最初の1回だけが記録されます。

## 計測ルール
- 解答時間 ＝ 問題が表示されてから ○/× を押すまで。別のタブを見ている間は止まります。
- 5分を超えた解答は「離席」とみなし、時間の分析から除外します（正誤の集計には含めます）。
- 偏差値 ＝ 50 ＋ 10 ×（本人の正答率 − 全員の平均正答率）÷ 標準偏差。

## アップデートしたとき（データベースの更新）
`supabase/schema.sql` → `supabase/seed_questions.sql` の順に、SQL Editor でもう一度実行してください。
既存の記録は消えません（何度実行しても大丈夫なように書いてあります）。

## スマホ表示の確認（開発者向け）
`node dev/check-mobile.js` で、iPhone SE・iPhone 15・小さめのAndroid・PCの幅で全画面を自動操作し、
横はみ出しやエラーがないか確認して `dev/screens/` にスクリーンショットを保存します（Playwright が必要）。

## 問題を追加・修正するには
`supabase/seed_questions.sql` に行を追加して（`point_code` に学習ポイント番号を入れる） SQL Editor で実行するか、Supabase の **Table Editor → questions** で直接編集します。
`active` を false にすると出題から外れます（過去の記録は残ります）。

## 生データを見たいとき
Supabase の **Table Editor → attempts** に1解答1行で記録されています。右上からCSVで書き出せます。
