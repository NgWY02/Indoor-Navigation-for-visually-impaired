-- Group sharing (party) with admin invite by per-user code
-- Run this entire script in Supabase SQL editor. It is idempotent.

-- 0) Extension for UUID generation
create extension if not exists pgcrypto;

-- 1) Minimal profiles (stores per-user code for admin invites)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  name text,
  user_code text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create profile on new auth user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, created_at, updated_at)
  values (new.id, new.email, now(), now())
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 2) Group sharing tables
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.path_groups (
  path_id uuid not null references public.navigation_paths(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  primary key (path_id, group_id)
);

-- 3) Add columns used by the app
alter table if exists public.navigation_paths
  add column if not exists is_published boolean not null default true;

alter table if exists public.navigation_paths
  add column if not exists map_id uuid references public.maps(id);

-- 4) Indexes
create index if not exists idx_group_members_user on public.group_members(user_id);
create index if not exists idx_group_members_group on public.group_members(group_id);
create index if not exists idx_path_groups_group on public.path_groups(group_id);
create index if not exists idx_path_groups_path on public.path_groups(path_id);
create index if not exists idx_navigation_paths_map_start on public.navigation_paths(map_id, start_location_id);
create index if not exists idx_profiles_user_code on public.profiles(user_code);

-- 5) Enable RLS
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.path_groups enable row level security;
alter table public.navigation_paths enable row level security;

-- 6) Policies (drop existing to avoid conflicts/recursion)

-- profiles: users see/update own; admins can read all
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles
  for select
  using (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select
  on public.profiles
  for select
  using (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

-- groups: INSERT by creator; SELECT by creator, members, or admin (no recursion)
drop policy if exists groups_insert_own on public.groups;
create policy groups_insert_own
  on public.groups
  for insert
  with check (created_by = auth.uid());

drop policy if exists groups_select_allowed on public.groups;
create policy groups_select_allowed
  on public.groups
  for select
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id
        and gm.user_id = auth.uid()
    )
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

-- group_members: INSERT/UPDATE self; admin can INSERT/UPDATE; SELECT self or admin
drop policy if exists group_members_insert_self on public.group_members;
create policy group_members_insert_self
  on public.group_members
  for insert
  with check (user_id = auth.uid());

drop policy if exists group_members_insert_admin on public.group_members;
create policy group_members_insert_admin
  on public.group_members
  for insert
  with check (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

drop policy if exists group_members_update_self on public.group_members;
create policy group_members_update_self
  on public.group_members
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists group_members_update_admin on public.group_members;
create policy group_members_update_admin
  on public.group_members
  for update
  using (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

drop policy if exists group_members_self_read on public.group_members;
create policy group_members_self_read
  on public.group_members
  for select
  using (user_id = auth.uid());

drop policy if exists group_members_admin_read on public.group_members;
create policy group_members_admin_read
  on public.group_members
  for select
  using (
    exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

-- path_groups: INSERT by group member or admin; SELECT by member or admin
drop policy if exists path_groups_insert_member on public.path_groups;
create policy path_groups_insert_member
  on public.path_groups
  for insert
  with check (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = path_groups.group_id
        and gm.user_id = auth.uid()
    )
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

drop policy if exists path_groups_member_read on public.path_groups;
create policy path_groups_member_read
  on public.path_groups
  for select
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = path_groups.group_id
        and gm.user_id = auth.uid()
    )
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role = 'admin'
    )
  );

-- navigation_paths: owner or published+shared via user's groups
drop policy if exists navigation_paths_owner_read on public.navigation_paths;
create policy navigation_paths_owner_read
  on public.navigation_paths
  for select
  using (user_id = auth.uid());

drop policy if exists navigation_paths_group_read on public.navigation_paths;
create policy navigation_paths_group_read
  on public.navigation_paths
  for select
  using (
    is_published = true and exists (
      select 1
      from public.path_groups pg
      join public.group_members gm on gm.group_id = pg.group_id
      where pg.path_id = navigation_paths.id
        and gm.user_id = auth.uid()
    )
  );