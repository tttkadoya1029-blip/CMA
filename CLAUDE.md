# CMA正誤トレーナー — 作業ルール

証券アナリスト第1次の正誤問題アプリ。静的HTML（index.html）＋ Supabase（DB・ログイン）、GitHub → Vercel で自動公開。

## 構成
- `index.html` … 画面とロジックすべて（ビルドなし）。`config.js` … Supabase接続情報（anon keyのみ。公開してよい）
- `supabase/schema.sql` … テーブル・RLS・関数。何度実行しても壊れないように書く（create if not exists / add column if not exists / drop policy if exists）
- `supabase/seed_questions.sql` … 学習ポイント（1001〜1026）と問題。問題は必ず `point_code` で学習ポイントに紐づける
- `dev/` … 表示確認用（にせSupabaseとスクリーンショットスクリプト）。Vercelには上げない

## 変更したら必ずやること
1. **スマホ表示の確認**：`node dev/check-mobile.js` を実行し、「OK: 横はみ出し・JSエラーなし」を確認。
   `dev/screens/` の iphone-se（375px）と android-small（360px）のスクリーンショットを実際に見て、折り返し・ボタンの押しやすさ・文字の重なりを確認する。新しい画面を作ったらスクリプトにも追加する。
2. **SQLを変えたら**：ローカルのPostgreSQLで schema.sql を2回連続実行して通ること、受講者・講師・未ログインそれぞれで読める範囲が正しいことを確認する。
3. 画面にUIを足すときは `dev/stub-supabase.js` に必要なrpc・テーブルを足す。

## 設計上の決まり
- 解答時間の代表値は**中央値**（平均は使わない）。5分超は離席とみなし時間の集計から除外。
- 受講者に正答を事前に送らない（`get_questions` は正答なし、採点は `submit_answer`）。
- 受講者は自分の記録だけ読める。他人のデータは集計値（`get_question_stats` 等）とランキングのみ。
- 練習モードはランキング対象外。試験モードは全問・最後に採点・正答率→合計時間でランキング。
- 問題文はテキストや過去問の文章をそのまま使わない（著作権）。論点だけ参考にしてオリジナルで作る。
- スマホ優先：表ではなく縦積みリスト（`.list`/`.li`）を基本に。表は講師用の横スクロールだけ。入力欄は16px以上（iOSのズーム防止）。
