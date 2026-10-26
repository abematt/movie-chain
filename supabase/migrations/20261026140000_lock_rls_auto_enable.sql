-- The security advisor flagged `public.rls_auto_enable()`: the function behind the
-- dashboard's "Enable automatic RLS" event trigger is SECURITY DEFINER and could be
-- called through /rest/v1/rpc by anyone holding the publishable key. It's only
-- meant to fire from its event trigger, which doesn't need these grants.

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
