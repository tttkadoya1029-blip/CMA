-- =========================================================
-- CMA正誤トレーナー  データベース定義（Supabase SQL Editor に貼って実行）
-- 何度実行しても壊れないように書いています
-- =========================================================

-- ---------- テーブル ----------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text,
  display_name text,
  role         text not null default 'student' check (role in ('student','teacher')),
  created_at   timestamptz not null default now()
);

create table if not exists public.questions (
  id          text primary key,
  topic       text,                      -- （旧）論点名。現在は point_code で整理
  level       text not null default '標準', -- 基礎 / 標準 / 応用
  stem        text not null,             -- 問題文
  answer      boolean not null,          -- true=○ false=×
  explanation text not null,
  source_note text,                      -- 出典メモ（どの章の論点か）
  sort        int not null default 0,
  active      boolean not null default true
);

create table if not exists public.sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  started_at  timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists public.attempts (
  id          bigint generated always as identity primary key,
  session_id  uuid not null references public.sessions(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  question_id text not null references public.questions(id),
  choice      boolean not null,
  is_correct  boolean not null,
  time_ms     int not null check (time_ms >= 0),
  answered_at timestamptz not null default now(),
  unique (session_id, question_id)
);
create index if not exists attempts_user_idx on public.attempts(user_id);
create index if not exists attempts_question_idx on public.attempts(question_id);


-- ---------- 学習ポイント（テキストの「この章で学ぶこと」の番号） ----------
create table if not exists public.points (
  code        text primary key,          -- 例: 1006
  chapter     int  not null,
  title       text not null,             -- 画面に出す短い名前
  description text,                      -- テキストの学習ポイントの文
  video_url   text,                      -- 解説動画（YouTubeなど）
  sort        int  not null default 0
);
alter table public.questions add column if not exists point_code text references public.points(code);
alter table public.questions alter column topic drop not null;
alter table public.sessions  add column if not exists mode text not null default 'practice';
alter table public.sessions  add column if not exists question_count int;
do $$ begin
  alter table public.sessions add constraint sessions_mode_chk check (mode in ('practice','exam'));
exception when duplicate_object then null; end $$;
alter table public.profiles  add column if not exists show_in_ranking boolean not null default true;

-- 試験モードは「その時点の全問」を解く。問題数はサーバー側で確定させる（ランキングの公平性のため）
create or replace function public.sessions_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  if new.mode = 'exam' then
    new.question_count := (select count(*) from public.questions where active);
  end if;
  return new;
end $$;
drop trigger if exists sessions_before_insert on public.sessions;
create trigger sessions_before_insert before insert on public.sessions
  for each row execute function public.sessions_before_insert();

-- ---------- 講師かどうか ----------
create or replace function public.is_teacher() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;

-- ---------- 新規ユーザー登録時にプロフィールを自動作成 ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 受講者向け：正答を含まない問題一覧 ----------
drop function if exists public.get_questions();
create or replace function public.get_questions()
returns table(id text, point_code text, level text, stem text, sort int)
language sql stable security definer set search_path = public as $$
  select q.id, q.point_code, q.level, q.stem, q.sort from public.questions q
  where q.active and auth.uid() is not null order by q.sort, q.id;
$$;

-- ---------- 解答の提出（正誤はサーバー側で判定。改ざん防止） ----------
create or replace function public.submit_answer(p_session uuid, p_question text, p_choice boolean, p_time_ms int)
returns table(is_correct boolean, answer boolean, explanation text)
language plpgsql security definer set search_path = public as $$
declare q public.questions%rowtype; ok boolean;
begin
  if auth.uid() is null then raise exception 'ログインが必要です'; end if;
  if not exists (select 1 from public.sessions s where s.id = p_session and s.user_id = auth.uid() and s.finished_at is null) then
    raise exception 'この受験記録には書き込めません';
  end if;
  select * into q from public.questions where questions.id = p_question and active;
  if not found then raise exception '問題が見つかりません'; end if;
  ok := (p_choice = q.answer);
  insert into public.attempts(session_id, user_id, question_id, choice, is_correct, time_ms)
  values (p_session, auth.uid(), p_question, p_choice, ok, greatest(0, least(p_time_ms, 3600000)))
  on conflict (session_id, question_id) do nothing;   -- 同じ問題の二重送信は最初の1回だけ有効
  return query select a.is_correct, q.answer, q.explanation from public.attempts a
    where a.session_id = p_session and a.question_id = p_question;
end $$;


-- ---------- 全体の成績（個人が特定されない集計値のみ） ----------
-- 時間は中央値。5分超（離席とみなす）は時間の集計から除外
drop function if exists public.get_question_stats();
create or replace function public.get_question_stats()
returns table(question_id text, n bigint, accuracy numeric, median_ms numeric)
language sql stable security definer set search_path = public as $$
  select a.question_id, count(*), round(avg(a.is_correct::int)::numeric, 4),
         round((percentile_cont(0.5) within group (order by a.time_ms) filter (where a.time_ms <= 300000))::numeric)
  from public.attempts a where auth.uid() is not null group by a.question_id;
$$;

drop function if exists public.get_point_stats();
create or replace function public.get_point_stats()
returns table(point_code text, n bigint, accuracy numeric, median_ms numeric)
language sql stable security definer set search_path = public as $$
  select q.point_code, count(*), round(avg(a.is_correct::int)::numeric, 4),
         round((percentile_cont(0.5) within group (order by a.time_ms) filter (where a.time_ms <= 300000))::numeric)
  from public.attempts a join public.questions q on q.id = a.question_id
  where auth.uid() is not null group by q.point_code;
$$;

-- ---------- 試験モードのランキング ----------
-- 各自のベスト記録（全問解答済みの試験）で、正答率が高い順 → 同率なら合計時間が短い順
drop function if exists public.get_exam_ranking();
create or replace function public.get_exam_ranking()
returns table(rank bigint, display_name text, correct int, total int, total_ms bigint, median_ms numeric, finished_at timestamptz, is_me boolean)
language sql stable security definer set search_path = public as $$
  with s as (
    select s.id, s.user_id, s.question_count, s.finished_at,
           count(a.id)::int as answered,
           count(a.id) filter (where a.is_correct)::int as correct,
           coalesce(sum(a.time_ms), 0)::bigint as total_ms,
           percentile_cont(0.5) within group (order by a.time_ms) as median_ms
    from public.sessions s join public.attempts a on a.session_id = s.id
    where s.mode = 'exam' and s.finished_at is not null and s.question_count > 0
    group by s.id
  ), best as (
    select distinct on (s.user_id) s.* from s
    where s.answered >= s.question_count
    order by s.user_id, s.correct::numeric / s.question_count desc, s.total_ms asc
  )
  select rank() over (order by b.correct::numeric / b.question_count desc, b.total_ms asc),
         coalesce(nullif(p.display_name, ''), '名前未登録'), b.correct, b.question_count, b.total_ms,
         round(b.median_ms::numeric), b.finished_at, b.user_id = auth.uid()
  from best b join public.profiles p on p.id = b.user_id
  where auth.uid() is not null and (p.show_in_ranking or b.user_id = auth.uid())
  order by 1, b.finished_at limit 100;
$$;

-- ---------- 利用回数ランキング（直近 p_days 日の解答数） ----------
drop function if exists public.get_activity_ranking(int);
create or replace function public.get_activity_ranking(p_days int default 30)
returns table(rank bigint, display_name text, answers bigint, sessions bigint, is_me boolean)
language sql stable security definer set search_path = public as $$
  select rank() over (order by count(*) desc), coalesce(nullif(p.display_name, ''), '名前未登録'),
         count(*), count(distinct a.session_id), a.user_id = auth.uid()
  from public.attempts a join public.profiles p on p.id = a.user_id
  where auth.uid() is not null and a.answered_at > now() - make_interval(days => greatest(1, least(p_days, 365)))
    and (p.show_in_ranking or a.user_id = auth.uid())
  group by a.user_id, p.display_name
  order by 1 limit 100;
$$;

-- ---------- 行レベルセキュリティ（RLS） ----------
alter table public.profiles  enable row level security;
alter table public.questions enable row level security;
alter table public.sessions  enable row level security;
alter table public.attempts  enable row level security;
alter table public.points    enable row level security;

drop policy if exists "points: ログインしていれば読める" on public.points;
create policy "points: ログインしていれば読める" on public.points for select
  using (auth.uid() is not null);
drop policy if exists "points: 講師が編集" on public.points;
create policy "points: 講師が編集" on public.points for all
  using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists "profiles: 本人か講師が読める" on public.profiles;
create policy "profiles: 本人か講師が読める" on public.profiles for select
  using (id = auth.uid() or public.is_teacher());
drop policy if exists "profiles: 本人が名前を変更" on public.profiles;
create policy "profiles: 本人が名前を変更" on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
-- 役割(role)は本人が変えられないよう、更新できる列を名前だけに限定
revoke update on public.profiles from anon, authenticated;
grant update (display_name, show_in_ranking) on public.profiles to authenticated;

drop policy if exists "questions: 講師が全操作" on public.questions;
create policy "questions: 講師が全操作" on public.questions for all
  using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists "sessions: 本人が開始" on public.sessions;
create policy "sessions: 本人が開始" on public.sessions for insert
  with check (user_id = auth.uid());
drop policy if exists "sessions: 本人か講師が読める" on public.sessions;
create policy "sessions: 本人か講師が読める" on public.sessions for select
  using (user_id = auth.uid() or public.is_teacher());
drop policy if exists "sessions: 本人が終了を記録" on public.sessions;
create policy "sessions: 本人が終了を記録" on public.sessions for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- attempts は submit_answer 経由でのみ書き込み（直接 insert のポリシーは作らない）
drop policy if exists "attempts: 本人か講師が読める" on public.attempts;
create policy "attempts: 本人か講師が読める" on public.attempts for select
  using (user_id = auth.uid() or public.is_teacher());

grant execute on function public.get_questions() to authenticated;
grant execute on function public.get_question_stats() to authenticated;
grant execute on function public.get_point_stats() to authenticated;
grant execute on function public.get_exam_ranking() to authenticated;
grant execute on function public.get_activity_ranking(int) to authenticated;
revoke execute on function public.get_question_stats() from anon, public;
revoke execute on function public.get_point_stats() from anon, public;
revoke execute on function public.get_exam_ranking() from anon, public;
revoke execute on function public.get_activity_ranking(int) from anon, public;
grant execute on function public.submit_answer(uuid, text, boolean, int) to authenticated;
revoke execute on function public.submit_answer(uuid, text, boolean, int) from anon, public;
revoke execute on function public.get_questions() from anon, public;
