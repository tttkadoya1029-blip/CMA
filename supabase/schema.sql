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
  topic       text not null,             -- 論点（分析の単位）
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
create or replace function public.get_questions()
returns table(id text, topic text, level text, stem text, sort int)
language sql stable security definer set search_path = public as $$
  select q.id, q.topic, q.level, q.stem, q.sort from public.questions q
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

-- ---------- 行レベルセキュリティ（RLS） ----------
alter table public.profiles  enable row level security;
alter table public.questions enable row level security;
alter table public.sessions  enable row level security;
alter table public.attempts  enable row level security;

drop policy if exists "profiles: 本人か講師が読める" on public.profiles;
create policy "profiles: 本人か講師が読める" on public.profiles for select
  using (id = auth.uid() or public.is_teacher());
drop policy if exists "profiles: 本人が名前を変更" on public.profiles;
create policy "profiles: 本人が名前を変更" on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
-- 役割(role)は本人が変えられないよう、更新できる列を名前だけに限定
revoke update on public.profiles from anon, authenticated;
grant update (display_name) on public.profiles to authenticated;

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
grant execute on function public.submit_answer(uuid, text, boolean, int) to authenticated;
revoke execute on function public.submit_answer(uuid, text, boolean, int) from anon, public;
revoke execute on function public.get_questions() from anon, public;
