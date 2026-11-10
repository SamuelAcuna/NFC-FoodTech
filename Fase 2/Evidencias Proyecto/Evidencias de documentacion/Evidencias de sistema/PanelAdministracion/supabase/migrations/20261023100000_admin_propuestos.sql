-- T05: aplicación manual por el orquestador, solo con OK de Samuel.
begin;

create or replace function public.admin_listar_propuestos()
returns table (
  id bigint, nombre text, categoria_id bigint, unidad_base text,
  es_perecible boolean, vida_util_dias_ref int, hogar_ref text,
  propuesto_en timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.es_admin('PROPUESTOS_REVISAR') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return query
    select a.id, a.nombre, a.categoria_id, a.unidad_base,
      a.es_perecible, a.vida_util_dias_ref,
      'hogar_' || pg_catalog.left(pg_catalog.replace(a.hogar_id::text, '-', ''), 6),
      a.created_at
    from public.alimento as a
    where a.estado = 'PROPUESTO'
    order by a.created_at;
end;
$$;
revoke execute on function public.admin_listar_propuestos() from public, anon;
grant execute on function public.admin_listar_propuestos() to authenticated;

create or replace function public.admin_contar_propuestos()
returns int
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.es_admin('PROPUESTOS_REVISAR') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  return (select pg_catalog.count(*)::int from public.alimento as a where a.estado = 'PROPUESTO');
end;
$$;
revoke execute on function public.admin_contar_propuestos() from public, anon;
grant execute on function public.admin_contar_propuestos() to authenticated;

create or replace function public.admin_aprobar_propuesto(
  p_id bigint, p_nombre text, p_categoria_id bigint, p_unidad_base text,
  p_es_perecible boolean, p_vida_util_dias_ref int
)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare
  v_estado text;
begin
  if not public.es_admin('PROPUESTOS_REVISAR') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  select a.estado into v_estado from public.alimento as a where a.id = p_id for update;
  if not found or v_estado <> 'PROPUESTO' then
    raise exception 'El producto ya no está pendiente de revisión.';
  end if;
  if p_nombre is null or pg_catalog.char_length(pg_catalog.btrim(p_nombre)) not between 2 and 80 then
    raise exception 'El nombre debe tener entre 2 y 80 caracteres.';
  end if;
  if not exists (select 1 from public.categoria as c where c.id = p_categoria_id and c.activa) then
    raise exception 'La categoría no existe o está inactiva.';
  end if;
  if p_vida_util_dias_ref is not null and p_vida_util_dias_ref not between 1 and 3650 then
    raise exception 'La duración debe estar entre 1 y 3650 días.';
  end if;
  update public.alimento as a set
    nombre = pg_catalog.btrim(p_nombre), categoria_id = p_categoria_id,
    unidad_base = p_unidad_base, es_perecible = p_es_perecible,
    vida_util_dias_ref = p_vida_util_dias_ref,
    estado = 'APROBADO', hogar_id = null, activo = true
  where a.id = p_id;
  return p_id;
end;
$$;
revoke execute on function public.admin_aprobar_propuesto(bigint, text, bigint, text, boolean, int) from public, anon;
grant execute on function public.admin_aprobar_propuesto(bigint, text, bigint, text, boolean, int) to authenticated;

create or replace function public.admin_rechazar_propuesto(p_id bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_estado text;
begin
  if not public.es_admin('PROPUESTOS_REVISAR') then
    raise exception 'No autorizado.' using errcode = '42501';
  end if;
  select a.estado into v_estado from public.alimento as a where a.id = p_id for update;
  if not found or v_estado <> 'PROPUESTO' then
    raise exception 'El producto ya no está pendiente de revisión.';
  end if;
  update public.alimento as a set estado = 'RECHAZADO' where a.id = p_id;
end;
$$;
revoke execute on function public.admin_rechazar_propuesto(bigint) from public, anon;
grant execute on function public.admin_rechazar_propuesto(bigint) to authenticated;

commit;
