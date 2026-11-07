# 補助作業で作った財務分析の追加問題（out_II-N.json）を検証し、supabase/seed_finance_extra.sql を作る
# 使い方: python3 dev/build_finance_extra.py <out_*.json と ctx_*.json と本文 *.txt があるフォルダ>
import json, os, re, sys
from collections import Counter

W = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNITS = ["II-1", "II-2", "II-3", "II-4", "II-5"]
problems, rows, all_stems = [], [], set()

def norm(t): return re.sub(r"\s+", "", t)
def lit(s): return "'" + str(s).replace("'", "''") + "'"

for u in UNITS:
    ctx = json.load(open(f"{W}/ctx_{u}.json", encoding="utf-8"))
    path = f"{W}/out_{u}.json"
    if not os.path.exists(path):
        problems.append(f"{u}: 出力ファイルがありません"); continue
    qs = json.load(open(path, encoding="utf-8"))
    codes = {p["code"] for p in ctx["points"]}
    existing = {norm(e["stem"]) for e in ctx["existing"]}
    text = norm(open(ctx["text_file"], encoding="utf-8").read().replace("=====PAGE=====", ""))
    long_grams = {text[i:i+28] for i in range(len(text)-27)}
    ans = Counter(q.get("answer") for q in qs); lv = Counter(q.get("level") for q in qs)
    per = Counter(q.get("point_code") for q in qs)
    if len(qs) != 180: problems.append(f"{u}: 問題数が {len(qs)} 問")
    if abs(ans[True]-ans[False]) > 4: problems.append(f"{u}: ○{ans[True]}・×{ans[False]} で偏っている")
    missing = codes - set(per)
    if missing: problems.append(f"{u}: 使われていない学習ポイント {sorted(missing)}")
    n_no, n_copy = 0, 0
    for i, q in enumerate(qs, 1):
        tag = f"{u} #{i}"
        if set(q) < {"point_code","level","stem","answer","explanation"}: problems.append(f"{tag}: キー不足"); continue
        if q["point_code"] not in codes: problems.append(f"{tag}: 学習ポイント {q['point_code']} はこの回にない")
        if q["level"] not in ("基礎","標準","応用"): problems.append(f"{tag}: 難易度 {q['level']}")
        if not isinstance(q["answer"], bool): problems.append(f"{tag}: answer が真偽値でない")
        if not q["explanation"].startswith("正しい。" if q["answer"] else "誤り。"): n_no += 1
        s = norm(q["stem"])
        if s in all_stems or s in existing: problems.append(f"{tag}: 問題文が重複")
        all_stems.add(s)
        # 28字以上続けて本文と同じ＝文の書き写しとみなす（それより短い一致は専門用語・基準名・定型句として許容）
        if any(s[j:j+28] in long_grams for j in range(len(s)-27)): n_copy += 1
        rows.append((u, i, q))
    if n_no: problems.append(f"{u}: 解説の書き出し（正しい。／誤り。）が答えと合わない {n_no} 問")
    if n_copy: problems.append(f"{u}: 本文と28字以上一致する問題文 {n_copy} 問")
    print(f"{u}: {len(qs)}問 ○{ans[True]}×{ans[False]} 難易度{dict(lv)} ポイント数{len(per)} 最少{min(per.values()) if per else 0}問")

if problems:
    print("問題あり:"); [print(" -", p) for p in problems]
else:
    print("OK: 検証をすべて通過")

vals = []
for u, i, q in rows:
    n = int(u.split("-")[1])
    qid = f"f{n}-{i+20:03d}"       # 既存の f1-01〜f1-20 の後ろに続ける
    sort = 2100 + n*1000 + i + 20
    vals.append(f"({lit(qid)},{lit(q['point_code'])},{lit(q['level'])},{lit(q['stem'])},{'true' if q['answer'] else 'false'},\n {lit(q['explanation'])},{sort})")
sql = ("-- 科目Ⅱ 財務分析 追加問題（第1〜5回・各180問）。既存の seed_finance.sql の後に実行する\n"
       "-- dev/build_finance_extra.py で自動生成\n"
       "insert into public.questions (id, point_code, level, stem, answer, explanation, sort) values\n"
       + ",\n".join(vals) +
       "\non conflict (id) do update set point_code=excluded.point_code, level=excluded.level, stem=excluded.stem, answer=excluded.answer,\n"
       "  explanation=excluded.explanation, sort=excluded.sort, active=true;\n")
open(os.path.join(ROOT, "supabase", "seed_finance_extra.sql"), "w", encoding="utf-8").write(sql)
print(f"supabase/seed_finance_extra.sql に {len(vals)} 問を書き出しました")
sys.exit(1 if problems else 0)
