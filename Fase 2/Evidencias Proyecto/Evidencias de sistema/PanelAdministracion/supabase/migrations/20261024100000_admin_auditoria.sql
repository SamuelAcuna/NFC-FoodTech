begin;
create or replace function public.admin_auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_antes jsonb; v_despues jsonb; v_fila jsonb; v_id text; v_accion text := TG_OP;
begin
  if not public.es_admin() then return null; end if;
  if TG_OP <> 'INSERT' then v_antes := to_jsonb(old); end if;
  if TG_OP <> 'DELETE' then v_despues := to_jsonb(new); end if;
  v_fila := coalesce(v_despues, v_antes);
  select string_agg(v_fila ->> k, ':' order by n) into v_id
    from unnest(TG_ARGV) with ordinality as claves(k,n);
  if TG_TABLE_NAME = 'alimento' then
    v_antes := v_antes - 'hogar_id' - 'creado_por';
    v_despues := v_despues - 'hogar_id' - 'creado_por';
  end if;
  if TG_OP = 'UPDATE' then
    if v_antes = v_despues then return null; end if;
    if TG_TABLE_NAME = 'alimento' and v_antes->>'estado' = 'PROPUESTO' then
      if v_despues->>'estado' = 'APROBADO' then v_accion := 'APROBAR';
      elsif v_despues->>'estado' = 'RECHAZADO' then v_accion := 'RECHAZAR'; end if;
    end if;
  end if;
  insert into public.auditoria(entidad,entidad_id,accion,perfil_id,antes,despues,motivo)
    values(TG_TABLE_NAME,v_id,v_accion,auth.uid(),v_antes,v_despues,
      nullif(current_setting('admin.motivo',true),''));
  return null;
end;
$$;
revoke execute on function public.admin_auditar() from public, anon, authenticated;
drop trigger if exists admin_auditoria_categoria on public.categoria;
create trigger admin_auditoria_categoria after insert or update or delete on public.categoria
  for each row execute function public.admin_auditar('id');
drop trigger if exists admin_auditoria_alimento on public.alimento;
create trigger admin_auditoria_alimento after insert or update or delete on public.alimento
  for each row execute function public.admin_auditar('id');
drop trigger if exists admin_auditoria_parametro on public.parametro;
create trigger admin_auditoria_parametro after insert or update or delete on public.parametro
  for each row execute function public.admin_auditar('clave');
drop trigger if exists admin_auditoria_rol on public.rol;
create trigger admin_auditoria_rol after insert or update or delete on public.rol
  for each row execute function public.admin_auditar('id');
drop trigger if exists admin_auditoria_rol_permiso on public.rol_permiso;
create trigger admin_auditoria_rol_permiso after insert or update or delete on public.rol_permiso
  for each row execute function public.admin_auditar('rol_id', 'permiso_id');
drop trigger if exists admin_auditoria_perfil_rol on public.perfil_rol;
create trigger admin_auditoria_perfil_rol after insert or update or delete on public.perfil_rol
  for each row execute function public.admin_auditar('perfil_id', 'rol_id');
create or replace function public.admin_listar_auditoria(
  p_desde date default null, p_hasta date default null, p_entidad text default null,
  p_accion text default null, p_limite int default 50, p_offset int default 0)
returns table(id uuid,fecha timestamptz,actor_email text,entidad text,entidad_id text,
  accion text,antes jsonb,despues jsonb,motivo text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin('AUDITORIA_VER') then raise exception 'No autorizado.' using errcode = '42501'; end if;
  return query select a.id,a.fecha,u.email::text,a.entidad,a.entidad_id,a.accion,a.antes,a.despues,a.motivo
    from public.auditoria a left join auth.users u on u.id = a.perfil_id
    where (p_desde is null or (a.fecha at time zone 'America/Santiago')::date >= p_desde)
      and (p_hasta is null or (a.fecha at time zone 'America/Santiago')::date <= p_hasta)
      and (p_entidad is null or a.entidad = p_entidad)
      and (p_accion is null or a.accion = p_accion)
    order by a.fecha desc,a.id
    limit greatest(1,least(coalesce(p_limite,50),200)) offset greatest(0,coalesce(p_offset,0));
end;
$$;
revoke execute on function public.admin_listar_auditoria(date,date,text,text,int,int) from public, anon;
grant execute on function public.admin_listar_auditoria(date,date,text,text,int,int) to authenticated;
commit;
