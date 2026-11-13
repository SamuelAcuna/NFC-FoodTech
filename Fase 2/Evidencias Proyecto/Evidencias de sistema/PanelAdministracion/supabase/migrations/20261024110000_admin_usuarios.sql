begin;
create or replace function public.admin_perfil_proteger_estado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado_cuenta is distinct from old.estado_cuenta and auth.uid() is not null
    and coalesce(current_setting('admin.cambio_estado',true),'') <> '1' then
    raise exception 'No autorizado.' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke execute on function public.admin_perfil_proteger_estado() from public,anon,authenticated;
drop trigger if exists admin_perfil_proteger_estado on public.perfil;
create trigger admin_perfil_proteger_estado before update of estado_cuenta on public.perfil
for each row execute function public.admin_perfil_proteger_estado();
create or replace function public.admin_listar_usuarios(
 p_busqueda text default null,p_estado text default null,p_registro_desde date default null,
 p_registro_hasta date default null,p_actividad text default null,p_limite int default 50,p_offset int default 0)
returns table(id uuid,email text,nombre text,apellido text,estado_cuenta text,registrado_en timestamptz,
 ultimo_acceso timestamptz,hogar_nombre text,rol_hogar text,es_administrador boolean,total bigint)
language plpgsql stable security definer set search_path = '' as $$
declare v_busqueda text;
begin
 if not public.es_admin('USUARIOS_VER') then raise exception 'No autorizado.' using errcode='42501'; end if;
 v_busqueda := '%' || replace(replace(replace(p_busqueda,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_') || '%';
 return query select p.id,u.email::text,p.nombre,p.apellido,p.estado_cuenta,u.created_at,u.last_sign_in_at,
   hm.nombre,hm.rol,exists(select 1 from public.perfil_rol pr where pr.perfil_id=p.id),count(*) over()
 from public.perfil p join auth.users u on u.id=p.id
 left join lateral (select h.nombre,m.rol from public.hogar_miembro m join public.hogar h on h.id=m.hogar_id
   where m.perfil_id=p.id and m.estado='ACTIVO' order by m.joined_at asc nulls last,m.hogar_id limit 1) hm on true
 where (p_busqueda is null or u.email ilike v_busqueda or p.nombre ilike v_busqueda or p.apellido ilike v_busqueda)
 and (p_estado is null or p.estado_cuenta=p_estado)
 and (p_registro_desde is null or (u.created_at at time zone 'America/Santiago')::date>=p_registro_desde)
 and (p_registro_hasta is null or (u.created_at at time zone 'America/Santiago')::date<=p_registro_hasta)
 and (p_actividad is null or (p_actividad='ACTIVOS_30' and u.last_sign_in_at>=now()-interval '30 days')
   or (p_actividad='INACTIVOS_30' and (u.last_sign_in_at is null or u.last_sign_in_at<now()-interval '30 days')))
 order by u.created_at desc,p.id
 limit greatest(1,least(coalesce(p_limite,50),200)) offset greatest(0,coalesce(p_offset,0));
end;
$$;
revoke execute on function public.admin_listar_usuarios(text,text,date,date,text,int,int) from public,anon;
grant execute on function public.admin_listar_usuarios(text,text,date,date,text,int,int) to authenticated;
create or replace function public.admin_cambiar_estado_cuenta(p_perfil_id uuid,p_estado text,p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_estado text; v_email text; v_flag text;
begin
 if not public.es_admin('USUARIOS_SUSPENDER') then raise exception 'No autorizado.' using errcode='42501'; end if;
 if p_estado is null or p_estado not in ('ACTIVA','SUSPENDIDA') then raise exception 'Estado no válido.'; end if;
 if p_motivo is null or char_length(btrim(p_motivo)) not between 5 and 500 then raise exception 'El motivo debe tener entre 5 y 500 caracteres.'; end if;
 if p_perfil_id=auth.uid() then raise exception 'No puedes cambiar el estado de tu propia cuenta.'; end if;
 -- La misma fila de rol que bloquea T01 coordina también la retirada de roles.
 perform pg_advisory_xact_lock(20261024,7);
 perform r.id from public.rol r where r.codigo='ADMIN' for update;
 select p.estado_cuenta,u.email into v_estado,v_email from public.perfil p join auth.users u on u.id=p.id
 where p.id=p_perfil_id for update of p;
 if not found then raise exception 'El usuario no existe.'; end if;
 if v_estado=p_estado then raise exception 'La cuenta ya está en ese estado.'; end if;
 if p_estado='SUSPENDIDA' and exists(select 1 from public.perfil_rol pr join public.rol r on r.id=pr.rol_id where pr.perfil_id=p_perfil_id and r.codigo='ADMIN')
 and not exists(select 1 from public.perfil_rol pr join public.rol r on r.id=pr.rol_id join public.perfil p on p.id=pr.perfil_id
   where r.codigo='ADMIN' and p.estado_cuenta='ACTIVA' and p.id<>p_perfil_id) then
   raise exception 'No se puede suspender al último administrador activo.';
 end if;
 v_flag := coalesce(current_setting('admin.cambio_estado',true),'');
 perform set_config('admin.cambio_estado','1',true);
 update public.perfil set estado_cuenta=p_estado where id=p_perfil_id;
 perform set_config('admin.cambio_estado',v_flag,true);
 insert into public.auditoria(entidad,entidad_id,accion,perfil_id,antes,despues,motivo)
 values('perfil',p_perfil_id::text,case when p_estado='SUSPENDIDA' then 'SUSPENDER' else 'REACTIVAR' end,auth.uid(),
 jsonb_build_object('estado_cuenta',v_estado,'email',v_email),jsonb_build_object('estado_cuenta',p_estado,'email',v_email),btrim(p_motivo));
end;
$$;
revoke execute on function public.admin_cambiar_estado_cuenta(uuid,text,text) from public,anon;
grant execute on function public.admin_cambiar_estado_cuenta(uuid,text,text) to authenticated;
commit;
