-- Gymnee サーバ関数・トリガ (§6.1 認証時の Profile 整合 / §7 アカウント削除)

-- 新規 auth ユーザー作成時に profiles 行を自動生成する。
-- 表示名は SiwA の fullName 等を raw_user_meta_data.display_name から拾う（無ければ 'ゲスト'）。
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), 'ゲスト')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- アカウント完全削除 (§7 / App Store 5.1.1(v))。
-- クライアントから RPC で呼ぶ: supabase.rpc('delete_account')。
-- auth.users を消すと user_id 参照は全て ON DELETE CASCADE で連鎖削除される。
create or replace function public.delete_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
