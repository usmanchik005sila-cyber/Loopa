begin;
alter table public.profiles drop constraint loopa_profile_avatar_own_path;
alter table public.profiles add constraint loopa_profile_avatar_own_path check (
  avatar_path is null
  or avatar_path ~ ('^' || id::text || '/avatar[.](jpg|png|webp)$')
  or avatar_path = id::text || '/telegram-avatar.jpg'
) not valid;
commit;

alter table public.profiles validate constraint loopa_profile_avatar_own_path;
