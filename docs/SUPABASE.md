# Synchronizacja w chmurze (Supabase)

Moja Kuchnia synchronizuje wszystkie przepisy (+ kategorie) jako **jeden
dokument JSON na użytkownika**, przez zwykłe HTTP do Supabase (bez wtyczek
Fluttera uruchamianych przy starcie — brak ryzyka białej strony). Reużywamy
tego samego projektu Supabase co Lexicon i Miejscownik (te same konta) —
wystarczy **raz** utworzyć osobną tabelę `recipes`.

## 1. Utwórz tabelę (jednorazowo)

W panelu Supabase → **SQL Editor** → wklej i uruchom:

```sql
-- Jeden wiersz na użytkownika; wszystkie przepisy w kolumnie data (JSON jako tekst).
create table if not exists public.recipes (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       text not null,
  updated_at timestamptz not null default now()
);

alter table public.recipes enable row level security;

-- Każdy widzi i modyfikuje wyłącznie swój wiersz.
create policy "own row - select" on public.recipes
  for select using (auth.uid() = user_id);
create policy "own row - insert" on public.recipes
  for insert with check (auth.uid() = user_id);
create policy "own row - update" on public.recipes
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

To wszystko. Klucze połączenia są w `lib/services/supabase_config.dart`
(publiczne z założenia — chroni je Row Level Security).

## 2. Jak to działa

- **Logowanie/rejestracja**: e-mail + hasło (Supabase Auth). Możesz użyć tego
  samego konta co w Lexiconie / Miejscowniku.
- **Wypychanie**: po każdej zmianie (debounce ~2 s) wysyłany jest cały zbiór
  (`upsert` z `Prefer: resolution=merge-duplicates`).
- **Pobieranie**: polling co ~15 s oraz przycisk „Synchronizuj teraz".
  Rozstrzyganie „ostatni wygrywa" po `updated_at`.
- **Pierwsze logowanie z danymi po obu stronach**: aplikacja pyta, którą wersję
  zostawić (urządzenie vs chmura).
- **Sesja** trzymana lokalnie w Hive (box `meta`), nie w sieci — brak ryzyka
  białej strony przy starcie.

## 3. Kopia zapasowa bez chmury

Ekran „Synchronizacja" ma też **Eksportuj / Importuj** — pobiera wszystkie
przepisy do pliku `.json` i wczytuje je z powrotem (ręczny backup /
przeniesienie bez konta).
