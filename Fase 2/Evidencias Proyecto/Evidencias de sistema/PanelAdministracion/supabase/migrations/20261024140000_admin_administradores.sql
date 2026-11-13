begin;
create or replace function public.admin_listar_administradores()
returns table(perfil_id uuid,email text,nombre text,apellido text,estado_cuenta text,roles text[],mfa_activo boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.es_admin('ROLES_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 return query select p.id,u.email::text,p.nombre,p.apellido,p.estado_cuenta,
 array(select r.codigo from public.perfil_rol pr join public.rol r on r.id=pr.rol_id where pr.perfil_id=p.id order by r.codigo),
 exists(select 1 from auth.mfa_factors f where f.user_id=p.id and f.status='verified')
 from public.perfil p join auth.users u on u.id=p.id
 where exists(select 1 from public.perfil_rol pr where pr.perfil_id=p.id) order by u.email,p.id;
end;
$$;
revoke execute on function public.admin_listar_administradores() from public,anon;
grant execute on function public.admin_listar_administradores() to authenticated;
create or replace function public.admin_asignar_rol(p_email text,p_rol_codigo text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_rol bigint;v_estado text;
begin
 if not public.es_admin('ROLES_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 select u.id into v_id from auth.users u where lower(u.email)=lower(btrim(p_email));
 if not found then raise exception 'No existe un usuario registrado con ese correo.'; end if;
 select p.estado_cuenta into v_estado from public.perfil p where p.id=v_id for update;
 if not found or v_estado<>'ACTIVA' then raise exception 'La cuenta del usuario no está activa.'; end if;
 select r.id into v_rol from public.rol r where r.codigo=p_rol_codigo;
 if not found then raise exception 'El rol no existe.'; end if;
 if exists(select 1 from public.perfil_rol pr where pr.perfil_id=v_id and pr.rol_id=v_rol) then raise exception 'El usuario ya tiene ese rol.'; end if;
 insert into public.perfil_rol(perfil_id,rol_id,asignado_por) values(v_id,v_rol,auth.uid());
 return v_id;
end;
$$;
revoke execute on function public.admin_asignar_rol(text,text) from public,anon;
grant execute on function public.admin_asignar_rol(text,text) to authenticated;
create or replace function public.admin_quitar_rol(p_perfil_id uuid,p_rol_codigo text)
returns void language plpgsql security definer set search_path='' as $$
declare v_rol bigint;
begin
 if not public.es_admin('ROLES_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 if p_perfil_id=auth.uid() and p_rol_codigo='ADMIN' then raise exception 'No puedes quitarte tu propio rol de administrador.'; end if;
 select r.id into v_rol from public.rol r where r.codigo=p_rol_codigo;
 delete from public.perfil_rol pr where pr.perfil_id=p_perfil_id and pr.rol_id=v_rol;
 if not found then raise exception 'El usuario no tiene ese rol.'; end if;
end;
$$;
revoke execute on function public.admin_quitar_rol(uuid,text) from public,anon;
grant execute on function public.admin_quitar_rol(uuid,text) to authenticated;
drop policy if exists admin_rol_permiso_insert on public.rol_permiso;
create policy admin_rol_permiso_insert on public.rol_permiso for insert to authenticated
with check(public.es_admin('ROLES_GESTIONAR') and not exists(select 1 from public.rol r where r.id=rol_permiso.rol_id and r.es_sistema));
drop policy if exists admin_rol_permiso_delete on public.rol_permiso;
create policy admin_rol_permiso_delete on public.rol_permiso for delete to authenticated
using(public.es_admin('ROLES_GESTIONAR') and not exists(select 1 from public.rol r where r.id=rol_permiso.rol_id and r.es_sistema));
commit;
