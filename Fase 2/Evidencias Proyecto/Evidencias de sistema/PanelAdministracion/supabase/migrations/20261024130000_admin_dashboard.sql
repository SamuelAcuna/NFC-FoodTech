begin;
create or replace function public.admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_meses jsonb;
begin
 if not public.es_admin() then raise exception 'No autorizado.' using errcode='42501'; end if;
 select jsonb_agg(jsonb_build_object('mes',to_char(m.mes,'YYYY-MM'),'consumos',m.consumos,'descartes',m.descartes) order by m.mes)
 into v_meses from (
  select meses.mes,count(*) filter(where v.tipo='CONSUMO') consumos,count(*) filter(where v.tipo='DESCARTE') descartes
  from generate_series(date_trunc('month',now() at time zone 'America/Santiago')-interval '5 months',
    date_trunc('month',now() at time zone 'America/Santiago'),interval '1 month') meses(mes)
  left join public.movimiento v on v.fecha >= (meses.mes at time zone 'America/Santiago')
    and v.fecha < ((meses.mes+interval '1 month') at time zone 'America/Santiago')
    and v.tipo in('CONSUMO','DESCARTE')
  group by meses.mes
 ) m;
 return jsonb_build_object(
 'usuarios_registrados',(select count(*) from public.perfil),
 'usuarios_activos_30d',(select count(*) from auth.users where last_sign_in_at>=now()-interval '30 days'),
 'usuarios_suspendidos',(select count(*) from public.perfil where estado_cuenta='SUSPENDIDA'),
 'hogares_registrados',(select count(*) from public.hogar),
 'alimentos_catalogo',(select count(*) from public.alimento where hogar_id is null and activo),
 'propuestos_pendientes',(select count(*) from public.alimento where estado='PROPUESTO'),
 'solicitudes_abiertas',(select count(*) from public.solicitud_soporte where estado in('PENDIENTE','ASIGNADA')),
 'aprovechamiento',v_meses);
end;
$$;
revoke execute on function public.admin_dashboard() from public,anon;
grant execute on function public.admin_dashboard() to authenticated;
commit;
