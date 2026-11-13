-- Solo archivo: ejecutar por Claude, nunca por el implementador. Verificar como superusuario tras RESET ROLE.
begin;
insert into auth.users(id,email,role,aud) values
 ('b1000000-0000-0000-0000-000000000001','admin-b1@local','authenticated','authenticated'),
 ('b1000000-0000-0000-0000-000000000002','editor-b1@local','authenticated','authenticated'),
 ('b1000000-0000-0000-0000-000000000003','soporte-b1@local','authenticated','authenticated'),
 ('b1000000-0000-0000-0000-000000000004','usuario-b1@local','authenticated','authenticated');
insert into public.perfil(id,estado_cuenta) select id,'ACTIVA' from auth.users where email like '%-b1@local' on conflict(id) do update set estado_cuenta='ACTIVA';
insert into public.perfil_rol(perfil_id,rol_id) select 'b1000000-0000-0000-0000-000000000001',id from public.rol where codigo='ADMIN';
insert into public.perfil_rol(perfil_id,rol_id) select 'b1000000-0000-0000-0000-000000000002',id from public.rol where codigo='EDITOR_CATALOGO';
insert into public.perfil_rol(perfil_id,rol_id) select 'b1000000-0000-0000-0000-000000000003',id from public.rol where codigo='SOPORTE';

select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
select set_config('t09.baseline',public.admin_dashboard()::text,true);
select set_config('request.jwt.claims','{}',true);
update auth.users set last_sign_in_at=now() where id='b1000000-0000-0000-0000-000000000004';
update public.perfil set estado_cuenta='SUSPENDIDA' where id='b1000000-0000-0000-0000-000000000004';
insert into public.hogar(id,nombre,creado_por) values('b1090000-0000-0000-0000-000000000010','B1 hogar','b1000000-0000-0000-0000-000000000004');
do $$ declare c bigint; a bigint; td bigint; begin
 insert into public.tipo_desperdicio(codigo,nombre,es_evitable) values('B1_TEST_DESP','B1 desperdicio',true) returning id into td; -- fix orquestador: ck_mov_desperdicio exige tipo en DESCARTE
 insert into public.categoria(nombre) values('B1 dashboard') returning id into c;
 insert into public.alimento(nombre,categoria_id,unidad_base,estado,hogar_id,creado_por) values('B1 dashboard',c,'un','PROPUESTO','b1090000-0000-0000-0000-000000000010','b1000000-0000-0000-0000-000000000004') returning id into a;
 insert into public.despensa_item(id,hogar_id,alimento_id,cantidad_inicial,cantidad_restante) values('b1090000-0000-0000-0000-000000000020','b1090000-0000-0000-0000-000000000010',a,100,100);
 insert into public.movimiento(despensa_item_id,tipo,cantidad,registrado_por,fecha,tipo_desperdicio_id) values
 ('b1090000-0000-0000-0000-000000000020','CONSUMO',1,'b1000000-0000-0000-0000-000000000004',now(),null),
 ('b1090000-0000-0000-0000-000000000020','DESCARTE',20,'b1000000-0000-0000-0000-000000000004',now()-interval '1 month',td);
 insert into public.solicitud_soporte(tipo,asunto,mensaje,solicitado_por) values('CONSULTA','B1 dashboard','Prueba','b1000000-0000-0000-0000-000000000004');
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ declare d jsonb; b jsonb:=current_setting('t09.baseline')::jsonb; begin
 d:=public.admin_dashboard();
 assert (d->>'hogares_registrados')::int=(b->>'hogares_registrados')::int+1;
 assert (d->>'usuarios_suspendidos')::int=(b->>'usuarios_suspendidos')::int+1;
 assert (d->>'usuarios_activos_30d')::int=(b->>'usuarios_activos_30d')::int+1;
 assert (d->>'propuestos_pendientes')::int=(b->>'propuestos_pendientes')::int+1;
 assert (d->>'solicitudes_abiertas')::int=(b->>'solicitudes_abiertas')::int+1;
 assert jsonb_array_length(d->'aprovechamiento')=6;
 assert (d->'aprovechamiento'->5->>'consumos')::int=(b->'aprovechamiento'->5->>'consumos')::int+1;
 assert (d->'aprovechamiento'->4->>'descartes')::int=(b->'aprovechamiento'->4->>'descartes')::int+1;
 assert not exists(select 1 from jsonb_each(d) e where e.key<>'aprovechamiento' and jsonb_typeof(e.value)<>'number');
 assert not exists(select 1 from jsonb_array_elements(d->'aprovechamiento') m,jsonb_object_keys(m) k where k not in('mes','consumos','descartes'));
end $$;
reset role;
do $$ declare claims text; begin
 assert not has_function_privilege('anon','public.admin_dashboard()','EXECUTE');
 foreach claims in array array['{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal1"}','{"sub":"b1000000-0000-0000-0000-000000000004","aal":"aal2"}'] loop
 perform set_config('request.jwt.claims',claims,true);
 begin perform public.admin_dashboard(); raise exception 'Acceso permitido'; exception when insufficient_privilege then null; end;
 end loop;
end $$;
rollback;
