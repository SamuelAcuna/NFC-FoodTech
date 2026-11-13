begin;
create or replace function public.admin_listar_soporte(p_estado text default null,p_limite int default 50,p_offset int default 0)
returns table(id uuid,tipo text,asunto text,mensaje text,estado text,prioridad smallint,
 solicitante_email text,hogar_ref text,solicitado_en timestamptz,asignado_a uuid,asignado_email text,
 respuesta text,respondido_email text,respondido_en timestamptz,cerrado_en timestamptz,total bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.es_admin('SOPORTE_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 return query select s.id,s.tipo,s.asunto,s.mensaje,s.estado,s.prioridad,u.email::text,
 case when s.hogar_id is null then null else 'hogar_'||left(replace(s.hogar_id::text,'-',''),6) end,
 s.solicitado_en,s.asignado_a,a.email::text,s.respuesta,r.email::text,s.respondido_en,s.cerrado_en,count(*) over()
 from public.solicitud_soporte s join auth.users u on u.id=s.solicitado_por
 left join auth.users a on a.id=s.asignado_a left join auth.users r on r.id=s.respondido_por
 where p_estado is null or s.estado=p_estado or (p_estado='ABIERTAS' and s.estado in('PENDIENTE','ASIGNADA'))
 order by case s.estado when 'PENDIENTE' then 1 when 'ASIGNADA' then 2 when 'RESPONDIDA' then 3 else 4 end,
 s.prioridad asc,s.solicitado_en asc,s.id
 limit greatest(1,least(coalesce(p_limite,50),200)) offset greatest(0,coalesce(p_offset,0));
end;
$$;
revoke execute on function public.admin_listar_soporte(text,int,int) from public,anon;
grant execute on function public.admin_listar_soporte(text,int,int) to authenticated;
create or replace function public.admin_listar_agentes_soporte()
returns table(id uuid,email text) language plpgsql stable security definer set search_path='' as $$
begin
 if not public.es_admin('SOPORTE_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 return query select p.id,u.email::text from public.perfil p join auth.users u on u.id=p.id
 where p.estado_cuenta='ACTIVA' and exists(select 1 from public.perfil_rol pr join public.rol_permiso rp on rp.rol_id=pr.rol_id
 join public.permiso pe on pe.id=rp.permiso_id where pr.perfil_id=p.id and pe.codigo='SOPORTE_GESTIONAR') order by u.email,p.id;
end;
$$;
revoke execute on function public.admin_listar_agentes_soporte() from public,anon;
grant execute on function public.admin_listar_agentes_soporte() to authenticated;
create or replace function public.admin_soporte_asignar(p_id uuid,p_agente uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_antes public.solicitud_soporte%rowtype; v_despues public.solicitud_soporte%rowtype;
begin
 if not public.es_admin('SOPORTE_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 select * into v_antes from public.solicitud_soporte where id=p_id for update;
 if not found then raise exception 'La solicitud no existe.'; end if;
 if v_antes.estado not in('PENDIENTE','ASIGNADA') then raise exception 'La solicitud no se puede asignar en su estado actual.'; end if;
 if not exists(select 1 from public.admin_listar_agentes_soporte() a where a.id=p_agente) then raise exception 'El agente no tiene permisos de soporte.'; end if;
 update public.solicitud_soporte set estado='ASIGNADA',asignado_a=p_agente where id=p_id returning * into v_despues;
 insert into public.auditoria(entidad,entidad_id,accion,perfil_id,antes,despues)
 values('solicitud_soporte',p_id::text,'UPDATE',auth.uid(),
 jsonb_build_object('estado',v_antes.estado,'asignado_a',v_antes.asignado_a),
 jsonb_build_object('operacion','ASIGNAR','estado',v_despues.estado,'asignado_a',v_despues.asignado_a,'asunto',v_despues.asunto));
end;
$$;
revoke execute on function public.admin_soporte_asignar(uuid,uuid) from public,anon;
grant execute on function public.admin_soporte_asignar(uuid,uuid) to authenticated;
create or replace function public.admin_soporte_responder(p_id uuid,p_respuesta text)
returns void language plpgsql security definer set search_path='' as $$
declare v_antes public.solicitud_soporte%rowtype; v_despues public.solicitud_soporte%rowtype;
begin
 if not public.es_admin('SOPORTE_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 select * into v_antes from public.solicitud_soporte where id=p_id for update;
 if not found then raise exception 'La solicitud no existe.'; end if;
 if p_respuesta is null or char_length(btrim(p_respuesta)) not between 5 and 2000 then raise exception 'La respuesta debe tener entre 5 y 2000 caracteres.'; end if;
 if v_antes.estado='CERRADA' then raise exception 'La solicitud está cerrada.'; end if;
 update public.solicitud_soporte set respuesta=btrim(p_respuesta),respondido_por=auth.uid(),respondido_en=now(),
 asignado_a=coalesce(asignado_a,auth.uid()),estado='RESPONDIDA' where id=p_id returning * into v_despues;
 insert into public.auditoria(entidad,entidad_id,accion,perfil_id,antes,despues)
 values('solicitud_soporte',p_id::text,'UPDATE',auth.uid(),
 jsonb_build_object('estado',v_antes.estado,'asignado_a',v_antes.asignado_a),
 jsonb_build_object('operacion','RESPONDER','estado',v_despues.estado,'asignado_a',v_despues.asignado_a,'asunto',v_despues.asunto));
end;
$$;
revoke execute on function public.admin_soporte_responder(uuid,text) from public,anon;
grant execute on function public.admin_soporte_responder(uuid,text) to authenticated;
create or replace function public.admin_soporte_cerrar(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_antes public.solicitud_soporte%rowtype; v_despues public.solicitud_soporte%rowtype;
begin
 if not public.es_admin('SOPORTE_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 select * into v_antes from public.solicitud_soporte where id=p_id for update;
 if not found then raise exception 'La solicitud no existe.'; end if;
 if v_antes.estado='CERRADA' then raise exception 'La solicitud ya está cerrada.'; end if;
 update public.solicitud_soporte set asignado_a=coalesce(asignado_a,auth.uid()),estado='CERRADA',cerrado_en=now() where id=p_id returning * into v_despues;
 insert into public.auditoria(entidad,entidad_id,accion,perfil_id,antes,despues)
 values('solicitud_soporte',p_id::text,'UPDATE',auth.uid(),
 jsonb_build_object('estado',v_antes.estado,'asignado_a',v_antes.asignado_a),
 jsonb_build_object('operacion','CERRAR','estado',v_despues.estado,'asignado_a',v_despues.asignado_a,'asunto',v_despues.asunto));
end;
$$;
revoke execute on function public.admin_soporte_cerrar(uuid) from public,anon;
grant execute on function public.admin_soporte_cerrar(uuid) to authenticated;
commit;
