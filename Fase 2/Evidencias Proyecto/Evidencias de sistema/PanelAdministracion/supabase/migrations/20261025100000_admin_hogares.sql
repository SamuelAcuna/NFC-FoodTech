begin;
create or replace function public.admin_listar_hogares(p_busqueda text default null,p_actividad text default null,p_limite int default 50,p_offset int default 0)
returns table(hogar_ref text,nombre text,comuna text,region text,integrantes int,invitados int,adultos smallint,menores smallint,creado_en timestamptz,movimientos_30d int,ultimo_movimiento timestamptz,productos_disponibles int,nivel_actividad text,total bigint)
language plpgsql stable security definer set search_path = '' as $$
declare v_busqueda text;
begin
 if not public.es_admin('HOGARES_VER') then raise exception 'No autorizado.' using errcode='42501'; end if;
 v_busqueda := '%' || replace(replace(replace(p_busqueda,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_') || '%';
 return query with agregados as (
 select 'hogar_'||left(h.id::text,6) as ref,h.nombre,c.nombre as comuna,r.nombre as region,
 (select count(*)::int from public.hogar_miembro hm where hm.hogar_id=h.id and hm.estado='ACTIVO') as integrantes,
 (select count(*)::int from public.hogar_miembro hm where hm.hogar_id=h.id and hm.estado='INVITADO') as invitados,
 h.adultos,h.menores,h.created_at,
 (select count(*)::int from public.movimiento m join public.despensa_item d on d.id=m.despensa_item_id where d.hogar_id=h.id and m.fecha>=now()-interval '30 days') as movimientos,
 (select max(m.fecha) from public.movimiento m join public.despensa_item d on d.id=m.despensa_item_id where d.hogar_id=h.id) as ultimo,
 (select count(*)::int from public.despensa_item d where d.hogar_id=h.id and d.estado='DISPONIBLE') as productos
 from public.hogar h left join public.comuna c on c.id=h.comuna_id left join public.region r on r.id=c.region_id
 where p_busqueda is null or h.nombre ilike v_busqueda
 ), niveles as (select a.*,case when movimientos=0 then 'SIN_ACTIVIDAD' when movimientos<5 then 'BAJA' when movimientos<20 then 'MEDIA' else 'ALTA' end as nivel from agregados a)
 select n.ref,n.nombre,n.comuna,n.region,n.integrantes,n.invitados,n.adultos,n.menores,n.created_at,n.movimientos,n.ultimo,n.productos,n.nivel,count(*) over()
 from niveles n where p_actividad is null or n.nivel=p_actividad order by n.created_at desc,n.ref
 limit greatest(1,least(coalesce(p_limite,50),200)) offset greatest(0,coalesce(p_offset,0));
end;
$$;
revoke execute on function public.admin_listar_hogares(text,text,int,int) from public,anon;
grant execute on function public.admin_listar_hogares(text,text,int,int) to authenticated;
commit;
