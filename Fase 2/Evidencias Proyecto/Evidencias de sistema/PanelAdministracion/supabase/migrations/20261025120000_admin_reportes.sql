begin;
create or replace function public.admin_reporte_uso(p_desde date,p_hasta date,p_agrupacion text default 'MES')
returns table(periodo date,altas int,usuarios_activos int,retencion_pct numeric,productos_registrados int,alertas_emitidas int)
language plpgsql stable security definer set search_path = '' as $$
declare v_unit text;
begin
 if not public.es_admin('REPORTES_VER') then raise exception 'No autorizado.' using errcode='42501'; end if;
 if p_desde is null or p_hasta is null or p_desde>p_hasta then raise exception 'El rango de fechas no es válido.'; end if;
 if p_hasta-p_desde+1>366 then raise exception 'El rango no puede superar 366 días.'; end if;
 if p_agrupacion is null or p_agrupacion not in ('MES','SEMANA') then raise exception 'La agrupación no es válida.'; end if;
 v_unit:=case when p_agrupacion='MES' then 'month' else 'week' end;
 return query with periodos as (
 select s::date as periodo,greatest(s::date,p_desde)::timestamp at time zone 'America/Santiago' as inicio,
 least((s+case when p_agrupacion='MES' then interval '1 month' else interval '1 week' end)::date,p_hasta+1)::timestamp at time zone 'America/Santiago' as fin,
 s::timestamp at time zone 'America/Santiago' as inicio_periodo
 from generate_series(date_trunc(v_unit,p_desde::timestamp),date_trunc(v_unit,p_hasta::timestamp),case when p_agrupacion='MES' then interval '1 month' else interval '1 week' end) s
 )
 select p.periodo,
 (select count(*)::int from public.perfil f join auth.users u on u.id=f.id where u.created_at>=p.inicio and u.created_at<p.fin),
 (select count(distinct m.registrado_por)::int from public.movimiento m where m.fecha>=p.inicio and m.fecha<p.fin),
 (select round(100.0*count(*) filter(where exists(select 1 from public.movimiento m where m.registrado_por=f.id and m.fecha>=p.inicio and m.fecha<p.fin))/nullif(count(*),0),1) from public.perfil f join auth.users u on u.id=f.id where u.created_at<p.inicio_periodo),
 (select count(*)::int from public.despensa_item d where d.created_at>=p.inicio and d.created_at<p.fin),
 (select count(*)::int from public.notificacion n where n.estado in ('ENVIADA','LEIDA') and n.programada_para>=p.inicio and n.programada_para<p.fin)
 from periodos p order by p.periodo;
end;
$$;
revoke execute on function public.admin_reporte_uso(date,date,text) from public,anon;
grant execute on function public.admin_reporte_uso(date,date,text) to authenticated;
create or replace function public.admin_reporte_desperdicio(p_desde date,p_hasta date,p_agrupacion text default 'MES')
returns table(periodo date,categoria text,descartes int,hogares int)
language plpgsql stable security definer set search_path = '' as $$
declare v_unit text;
begin
 if not public.es_admin('REPORTES_VER') then raise exception 'No autorizado.' using errcode='42501'; end if;
 if p_desde is null or p_hasta is null or p_desde>p_hasta then raise exception 'El rango de fechas no es válido.'; end if;
 if p_hasta-p_desde+1>366 then raise exception 'El rango no puede superar 366 días.'; end if;
 if p_agrupacion is null or p_agrupacion not in ('MES','SEMANA') then raise exception 'La agrupación no es válida.'; end if;
 v_unit:=case when p_agrupacion='MES' then 'month' else 'week' end;
 return query select date_trunc(v_unit,m.fecha at time zone 'America/Santiago')::date,raiz.nombre,count(*)::int,count(distinct d.hogar_id)::int
 from public.movimiento m join public.despensa_item d on d.id=m.despensa_item_id
 join public.alimento a on a.id=d.alimento_id join public.categoria c on c.id=a.categoria_id
 join public.categoria raiz on raiz.id=coalesce(c.parent_id,c.id)
 where m.tipo='DESCARTE' and m.fecha>=p_desde::timestamp at time zone 'America/Santiago'
 and m.fecha<(p_hasta+1)::timestamp at time zone 'America/Santiago'
 group by 1,raiz.id,raiz.nombre having count(distinct d.hogar_id)>=3 order by 1,3 desc;
end;
$$;
revoke execute on function public.admin_reporte_desperdicio(date,date,text) from public,anon;
grant execute on function public.admin_reporte_desperdicio(date,date,text) to authenticated;
commit;
