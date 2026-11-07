-- PICHE UET Peshawar: database setup. Run once in Supabase > SQL Editor.

create table staff (email text primary key, role text not null check (role in ('admin','cabinet')));
create table designations (name text primary key, sort int not null default 0);
create table settings (key text primary key, value text not null default '');
create sequence member_seq;

create table members (
  id uuid primary key default gen_random_uuid(),
  name text not null, father text not null,
  reg_no text not null, email text not null,
  department text not null, semester int not null check (semester between 1 and 8),
  address text not null, blood text,
  blood_verified boolean not null default false,
  status text not null default 'Pending' check (status in ('Pending','Active','Inactive','Former','Verified','Rejected','Correction')),
  membership_id text unique, valid_until date,
  public_listing boolean not null default true,
  photo_url text, note text,
  created_at timestamptz not null default now()
);
create unique index members_reg_uq on members (lower(reg_no));
create index members_email_ix on members (lower(email));

create table member_roles (
  member_id uuid references members(id) on delete cascade,
  term text not null, designation text not null,
  primary key (member_id, term)
);
create table events (id uuid primary key default gen_random_uuid(), title text not null, event_date date not null, venue text, description text, photo_url text);
create table news (id uuid primary key default gen_random_uuid(), title text not null, news_date date not null, body text);
create table activity_log (id bigserial primary key, at timestamptz not null default now(), actor text, action text not null);

-- Helper functions
create function is_staff() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from staff where lower(email)=lower(coalesce(auth.jwt()->>'email',''))) $$;
create function is_admin() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from staff where role='admin' and lower(email)=lower(coalesce(auth.jwt()->>'email',''))) $$;
create function my_role() returns text language sql stable security definer set search_path=public as
$$ select role from staff where lower(email)=lower(coalesce(auth.jwt()->>'email','')) $$;
create function can_sign_in(p_email text, p_reg text) returns boolean language sql stable security definer set search_path=public as
$$ select case when p_reg is null then exists(select 1 from staff where lower(email)=lower(p_email))
   else exists(select 1 from members where lower(email)=lower(p_email) and lower(reg_no)=lower(p_reg)) end $$;
create function verify_member(p_id text)
returns table(name text, membership_id text, department text, status text, valid_until date, designation text)
language sql stable security definer set search_path=public as
$$ select m.name,m.membership_id,m.department,m.status,m.valid_until,
   (select r.designation from member_roles r where r.member_id=m.id and r.term=(select value from settings where key='term') limit 1)
   from members m where m.membership_id is not null and lower(m.membership_id)=lower(p_id) $$;

-- Safe public view: no phone, address, father's name, registration number or email
create view public_members as
select m.id,m.name,m.department,m.semester,m.membership_id,m.status,m.photo_url,m.public_listing,
 coalesce((select jsonb_agg(jsonb_build_object('y',r.term,'d',r.designation)) from member_roles r where r.member_id=m.id),'[]'::jsonb) as roles
from members m
where m.status in ('Active','Inactive','Former','Verified')
  and (m.public_listing or exists(select 1 from member_roles r where r.member_id=m.id));
grant select on public_members to anon, authenticated;
grant execute on function can_sign_in(text,text), verify_member(text) to anon, authenticated;

-- Guard rules enforced in the database, not only in the web page
create function members_guard() returns trigger language plpgsql security definer set search_path=public as $$
declare adm boolean := is_admin(); stf boolean := is_staff();
begin
  if tg_op='INSERT' then
    if not stf then new.status:='Pending'; new.membership_id:=null; new.valid_until:=null; new.blood_verified:=false; new.note:=null; end if;
  else
    if not stf then
      new.name:=old.name; new.father:=old.father; new.reg_no:=old.reg_no; new.email:=old.email;
      new.department:=old.department; new.semester:=old.semester; new.membership_id:=old.membership_id; new.valid_until:=old.valid_until;
      if new.blood is distinct from old.blood then new.blood_verified:=false; else new.blood_verified:=old.blood_verified; end if;
      if old.status='Correction' and new.status='Pending' then new.note:=null; else new.status:=old.status; new.note:=old.note; end if;
    elsif not adm then
      if new.status not in ('Active','Pending','Rejected','Correction') then new.status:=old.status; end if;
      new.blood_verified:=old.blood_verified;
    end if;
  end if;
  if new.status in ('Active','Verified') and new.membership_id is null then
    new.membership_id:='PICHE-'||to_char(now(),'YY')||'-'||lpad(nextval('member_seq')::text,4,'0');
    new.valid_until:=coalesce(new.valid_until,(now()+interval '1 year')::date);
  end if;
  return new;
end $$;
create trigger members_guard_t before insert or update on members for each row execute function members_guard();

-- Row level security
alter table staff enable row level security;
alter table designations enable row level security;
alter table settings enable row level security;
alter table members enable row level security;
alter table member_roles enable row level security;
alter table events enable row level security;
alter table news enable row level security;
alter table activity_log enable row level security;

create policy m_ins on members for insert to anon, authenticated with check (true);
create policy m_sel_staff on members for select to authenticated using (is_staff());
create policy m_sel_own on members for select to authenticated using (lower(email)=lower(auth.jwt()->>'email'));
create policy m_upd_staff on members for update to authenticated using (is_staff()) with check (is_staff());
create policy m_upd_own on members for update to authenticated using (lower(email)=lower(auth.jwt()->>'email')) with check (lower(email)=lower(auth.jwt()->>'email'));

create policy r_sel on member_roles for select to authenticated using (is_staff() or member_id in (select id from members where lower(email)=lower(auth.jwt()->>'email')));
create policy r_all on member_roles for all to authenticated using (is_admin()) with check (is_admin());

create policy d_sel on designations for select to anon, authenticated using (true);
create policy d_all on designations for all to authenticated using (is_admin()) with check (is_admin());
create policy s_sel on settings for select to anon, authenticated using (true);
create policy s_all on settings for all to authenticated using (is_admin()) with check (is_admin());
create policy e_sel on events for select to anon, authenticated using (true);
create policy e_all on events for all to authenticated using (is_staff()) with check (is_staff());
create policy n_sel on news for select to anon, authenticated using (true);
create policy n_all on news for all to authenticated using (is_staff()) with check (is_staff());
create policy l_ins on activity_log for insert to authenticated with check (is_staff());
create policy l_sel on activity_log for select to authenticated using (is_admin());

-- Photo storage: public read, JPEG only, max 1 MB
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('photos','photos',true,1048576,array['image/jpeg']) on conflict (id) do nothing;
create policy ph_reg on storage.objects for insert to anon, authenticated with check (bucket_id='photos' and name like 'reg/%');
create policy ph_mem on storage.objects for insert to authenticated with check (bucket_id='photos' and (name like 'm/%' or (name like 'ev/%' and is_staff())));

-- Starting data
insert into designations (name,sort) values ('President',0),('Vice President',1),('General Secretary',2),('Joint Secretary',3),('Treasurer',4),('Media Secretary',5),('Event Coordinator',6),('Technical Coordinator',7),('Executive Member',8),('General Member',9);
insert into settings (key,value) values ('term','2026-27'),('email',''),('phone',''),('fb',''),('ig',''),('li','');

-- IMPORTANT: add yourself as administrator (replace with your real email), then run this line:
-- insert into staff (email, role) values ('you@example.com', 'admin');
-- Cabinet members: insert into staff (email, role) values ('name@example.com', 'cabinet');
