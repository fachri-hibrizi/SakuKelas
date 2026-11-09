-- ============================================================
-- SakuKelas - Skema Basis Data (semua nama dalam Bahasa Indonesia)
-- Jalankan di Supabase Dashboard > SQL Editor (aman dijalankan berulang).
--
-- PERHATIAN: skrip ini
--   * MENGHAPUS tabel lama 'kategori', 'anggota', 'bukti' versi sebelumnya
--     (struktur lama campur Inggris), jadi isi anggota/kategori uji coba ikut hilang.
--   * MEMINDAHKAN data tabel lama 'transactions' ke tabel baru 'transaksi',
--     lalu menghapus 'transactions'.
--   * Mengganti nama tabel 'profiles' menjadi 'profil' (data tetap).
-- ============================================================

-- ------------------------------------------------------------
-- 0. Bersihkan struktur lama (yang belum memakai kolom 'dibuat_pada')
-- ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['bukti', 'anggota', 'kategori'] loop
    if to_regclass('public.' || t) is not null
       and not exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = t and column_name = 'dibuat_pada'
       ) then
      execute format('drop table public.%I cascade', t);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 1. Tabel
-- ------------------------------------------------------------
create table if not exists public.kategori (
  id uuid primary key default gen_random_uuid(),
  pengguna_id uuid not null references auth.users(id) on delete cascade,
  nama_kategori text not null,
  jenis text not null check (jenis in ('masuk', 'keluar')),
  kategori_aktif boolean not null default true,
  adalah_uang_kas boolean not null default false,   -- true = kategori iuran bulanan
  dibuat_pada timestamptz not null default now(),
  unique (pengguna_id, jenis, nama_kategori)
);

create table if not exists public.anggota (
  id uuid primary key default gen_random_uuid(),
  pengguna_id uuid not null references auth.users(id) on delete cascade,
  nama text not null,
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.transaksi (
  id uuid primary key default gen_random_uuid(),
  pengguna_id uuid not null references auth.users(id) on delete cascade,
  kategori_id uuid references public.kategori(id) on delete set null,
  anggota_id uuid references public.anggota(id) on delete set null,
  judul text not null,
  nominal bigint not null check (nominal > 0),
  jenis text not null check (jenis in ('masuk', 'keluar')),
  catatan text,
  tanggal date not null default current_date,
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.bukti (
  id uuid primary key default gen_random_uuid(),
  transaksi_id uuid not null references public.transaksi(id) on delete cascade,
  url_foto text not null,
  dibuat_pada timestamptz not null default now()
);

-- Satu baris = satu anggota membayar uang kas untuk satu bulan.
-- Unik per (anggota, tahun, bulan) supaya satu bulan tidak bisa dibayar dua kali.
create table if not exists public.pembayaran_kas (
  id uuid primary key default gen_random_uuid(),
  pengguna_id uuid not null references auth.users(id) on delete cascade,
  transaksi_id uuid not null references public.transaksi(id) on delete cascade,
  anggota_id uuid not null references public.anggota(id) on delete cascade,
  bulan smallint not null check (bulan between 1 and 12),
  tahun smallint not null check (tahun between 2000 and 2100),
  dibuat_pada timestamptz not null default now(),
  unique (anggota_id, tahun, bulan)
);

create index if not exists idx_transaksi_pengguna_tanggal
  on public.transaksi (pengguna_id, tanggal desc);
create index if not exists idx_pembayaran_kas_pengguna
  on public.pembayaran_kas (pengguna_id);

-- ------------------------------------------------------------
-- 2. Pindahkan data dari tabel lama 'transactions' (jika masih ada)
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.transactions') is not null then
    insert into public.transaksi (id, pengguna_id, judul, nominal, jenis, catatan, tanggal)
    select id,
           user_id,
           coalesce(title, 'Tanpa judul'),
           amount::bigint,
           case when "type" = 'income' then 'masuk' else 'keluar' end,
           note,
           coalesce("date"::date, current_date)
    from public.transactions
    where amount > 0
    on conflict (id) do nothing;

    drop table public.transactions cascade;
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. Tabel profil (dulu 'profiles' dengan kolom 'full_name')
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.profiles') is not null and to_regclass('public.profil') is null then
    alter table public.profiles rename to profil;
  end if;
  if to_regclass('public.profil') is not null
     and exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'profil' and column_name = 'full_name'
     ) then
    alter table public.profil rename column full_name to nama_lengkap;
  end if;
end $$;

create table if not exists public.profil (
  id uuid primary key references auth.users(id) on delete cascade,
  nama_lengkap text,
  dibuat_pada timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4. Keamanan baris (Row Level Security)
-- ------------------------------------------------------------
alter table public.kategori        enable row level security;
alter table public.anggota         enable row level security;
alter table public.transaksi       enable row level security;
alter table public.bukti           enable row level security;
alter table public.pembayaran_kas  enable row level security;
alter table public.profil          enable row level security;

-- Hapus semua kebijakan lama (nama Inggris) di tabel-tabel ini
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('kategori', 'anggota', 'transaksi', 'bukti', 'pembayaran_kas', 'profil')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

create policy kategori_milik_pengguna on public.kategori
  for all using (pengguna_id = auth.uid()) with check (pengguna_id = auth.uid());

create policy anggota_milik_pengguna on public.anggota
  for all using (pengguna_id = auth.uid()) with check (pengguna_id = auth.uid());

create policy transaksi_milik_pengguna on public.transaksi
  for all using (pengguna_id = auth.uid()) with check (pengguna_id = auth.uid());

create policy pembayaran_kas_milik_pengguna on public.pembayaran_kas
  for all using (pengguna_id = auth.uid()) with check (pengguna_id = auth.uid());

create policy bukti_milik_pengguna on public.bukti
  for all
  using (exists (
    select 1 from public.transaksi t
    where t.id = bukti.transaksi_id and t.pengguna_id = auth.uid()))
  with check (exists (
    select 1 from public.transaksi t
    where t.id = bukti.transaksi_id and t.pengguna_id = auth.uid()));

create policy profil_milik_pengguna on public.profil
  for all using (id = auth.uid()) with check (id = auth.uid());

-- ------------------------------------------------------------
-- 5. Penyimpanan foto bukti
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('bukti-transaksi', 'bukti-transaksi', true)
on conflict (id) do nothing;

drop policy if exists "bukti storage owner" on storage.objects;
drop policy if exists "bukti_transaksi_milik_pengguna" on storage.objects;

create policy "bukti_transaksi_milik_pengguna" on storage.objects
  for all
  using (bucket_id = 'bukti-transaksi' and auth.uid()::text = (storage.foldername(name))[1])
  with check (bucket_id = 'bukti-transaksi' and auth.uid()::text = (storage.foldername(name))[1]);

-- ------------------------------------------------------------
-- Catatan:
-- * Kategori bawaan (Kebutuhan Kelas, Event, Kesenangan, Uang Kas, Donasi)
--   dibuat otomatis oleh aplikasi saat pertama kali dibutuhkan.
-- * Nilai kolom 'jenis' hanya 'masuk' atau 'keluar'.
-- ============================================================
