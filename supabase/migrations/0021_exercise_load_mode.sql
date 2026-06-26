-- 自重種目の荷重スタイル（自重のみ/荷重/補助）。懸垂等で「荷重(自重＋kg)」と「補助(自重−kg)」を
-- 明示的に区別する。bodyweight のときだけ意味を持つ。記録される weight は常に正の大きさ。
alter table public.exercises add column if not exists load_mode text not null default 'none';
