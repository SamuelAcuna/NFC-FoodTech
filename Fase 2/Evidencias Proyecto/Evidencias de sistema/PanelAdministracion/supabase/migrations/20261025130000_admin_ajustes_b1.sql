begin;
create or replace function public.admin_quitar_rol(p_perfil_id uuid,p_rol_codigo text)
returns void language plpgsql security definer set search_path='' as $$
declare v_rol bigint;
begin
 if not public.es_admin('ROLES_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 if p_perfil_id=auth.uid() then raise exception 'No puedes quitarte tus propios roles.'; end if;
 select r.id into v_rol from public.rol r where r.codigo=p_rol_codigo;
 delete from public.perfil_rol pr where pr.perfil_id=p_perfil_id and pr.rol_id=v_rol;
 if not found then raise exception 'El usuario no tiene ese rol.'; end if;
end;
$$;
revoke execute on function public.admin_quitar_rol(uuid,text) from public,anon;
grant execute on function public.admin_quitar_rol(uuid,text) to authenticated;
commit;
