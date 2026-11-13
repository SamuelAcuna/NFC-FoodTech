-- Fixtures y referencias privadas antes de SET ROLE; no ejecutar sobre la base real.
begin;
do $$ begin
 assert not exists(select 1 from auth.users where created_at<'1800-04-01'),'T13-CA3: período histórico aislado para conteos exactos';
end $$;
insert into auth.users(id,email,role,aud,created_at) values
 ('b2130000-0000-0000-0000-000000000001','admin-t13@local','authenticated','authenticated','1800-01-02 12:00 America/Santiago'),
 ('b2130000-0000-0000-0000-000000000002','editor-t13@local','authenticated','authenticated','1800-01-02 12:00 America/Santiago'),
 ('b2130000-0000-0000-0000-000000000003','soporte-t13@local','authenticated','authenticated','1800-01-02 12:00 America/Santiago');
insert into public.perfil(id,estado_cuenta) select id,'ACTIVA' from auth.users where email like '%-t13@local' on conflict(id) do update set estado_cuenta='ACTIVA';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2130000-0000-0000-0000-000000000001',id from public.rol where codigo='ADMIN';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2130000-0000-0000-0000-000000000002',id from public.rol where codigo='EDITOR_CATALOGO';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2130000-0000-0000-0000-000000000003',id from public.rol where codigo='SOPORTE';
do $$ declare root_id bigint; child_id bigint; hidden_id bigint; a bigint; h uuid; d uuid; td bigint; tpl bigint; i int; begin
 insert into public.categoria(nombre) values('T13 raíz visible') returning id into root_id;
 insert into public.categoria(nombre,parent_id) values('T13 hija',root_id) returning id into child_id;
 insert into public.categoria(nombre) values('T13 oculta') returning id into hidden_id;
 insert into public.tipo_desperdicio(codigo,nombre,es_evitable) values('T13_PRUEBA','T13 prueba',true) returning id into td;
 for i in 1..5 loop
 insert into public.hogar(nombre,creado_por) values('T13 hogar '||i,'b2130000-0000-0000-0000-000000000001') returning id into h;
 insert into public.alimento(nombre,categoria_id,unidad_base) values('T13 alimento '||i,case when i<=3 then child_id else hidden_id end,'un') returning id into a;
 insert into public.despensa_item(hogar_id,alimento_id,cantidad_inicial,cantidad_restante,created_at) values(h,a,10,9,'1800-02-02 12:00 America/Santiago') returning id into d;
 assert d is not null,'T13-CA4: fixture privada creada como superusuario';
 perform set_config('t13.item_'||i,d::text,true);
 insert into public.movimiento(despensa_item_id,tipo,cantidad,tipo_desperdicio_id,registrado_por,fecha) values(d,'DESCARTE',1,td,'b2130000-0000-0000-0000-000000000001','1800-02-02 12:00 America/Santiago');
 end loop;
 insert into public.plantilla_notificacion(codigo,categoria,titulo_tpl,cuerpo_tpl) values('T13_PRUEBA','SISTEMA','T13','T13') returning id into tpl;
 insert into public.notificacion(perfil_id,plantilla_id,estado,programada_para,clave_dedup)
 select 'b2130000-0000-0000-0000-000000000001',tpl,s,'1800-02-02 12:00 America/Santiago','T13_'||s from unnest(array['ENVIADA','LEIDA','PENDIENTE']) s;
end $$;
select set_config('request.jwt.claims','{"sub":"b2130000-0000-0000-0000-000000000001","aal":"aal2"}',true);
set local role authenticated;
do $$ declare r record; msg text; fn text; c record; begin
 assert (select count(*) from public.admin_reporte_uso('1800-01-01','1800-03-31'))=3,'T13-CA3: todos los meses incluidos los vacíos';
 select * into strict r from public.admin_reporte_uso('1800-01-01','1800-03-31') where periodo='1800-01-01';
 assert r.altas=3 and r.usuarios_activos=0 and r.retencion_pct is null and r.productos_registrados=0 and r.alertas_emitidas=0,'T13-CA3: altas y denominador cero';
 select * into strict r from public.admin_reporte_uso('1800-01-01','1800-03-31') where periodo='1800-02-01';
 assert r.altas=0 and r.usuarios_activos=1 and r.retencion_pct=33.3 and r.productos_registrados=5 and r.alertas_emitidas=2,'T13-CA3: activos retención productos y alertas sin PENDIENTE';
 select * into strict r from public.admin_reporte_uso('1800-01-01','1800-03-31') where periodo='1800-03-01';
 assert r.altas=0 and r.usuarios_activos=0 and r.retencion_pct=0 and r.productos_registrados=0 and r.alertas_emitidas=0,'T13-CA3: período vacío';
 assert not exists(select 1 from public.admin_reporte_uso('1800-01-01','1800-03-31','SEMANA') where extract(isodow from periodo)<>1),'T13-CA3: semanas ISO desde lunes';
 select * into strict r from public.admin_reporte_desperdicio('1800-01-01','1800-03-31');
 assert r.categoria='T13 raíz visible' and r.descartes=3 and r.hogares=3,'T13-CA4: hija agrupada en raíz y categoría de dos hogares omitida';
 assert not exists(select 1 from public.admin_reporte_desperdicio('1800-01-01','1800-03-31') where categoria='T13 oculta'),'T13-CA4: categoría con 2 hogares no aparece en resultado';
 assert (select count(*) from public.admin_reporte_desperdicio('1800-02-02','1800-02-02','SEMANA'))=1,'T13-CA4: rango diario inclusivo y agrupación semanal';
 foreach fn in array array['admin_reporte_uso','admin_reporte_desperdicio'] loop
 for c in select * from (values(null::date,'1800-01-01'::date,'MES','El rango de fechas no es válido.'),('1800-02-01'::date,'1800-01-01'::date,'MES','El rango de fechas no es válido.'),('1800-01-01'::date,'1801-01-02'::date,'MES','El rango no puede superar 366 días.'),('1800-01-01'::date,'1800-01-02'::date,'DIA','La agrupación no es válida.')) v(d,h,g,m) loop
 msg:=null;
 begin execute format('select * from public.%I($1,$2,$3)',fn) using c.d,c.h,c.g;exception when raise_exception then msg:=sqlerrm;end;
 assert msg=c.m,'T13-CA5: mensaje exacto '||fn||' '||c.m;
 end loop;
 end loop;
end $$;
reset role;
do $$ begin
 assert not has_function_privilege('anon','public.admin_reporte_uso(date,date,text)','EXECUTE'),'T13-CA2: anon sin uso';
 assert not has_function_privilege('public','public.admin_reporte_uso(date,date,text)','EXECUTE'),'T13-CA2: public sin uso';
 assert not has_function_privilege('anon','public.admin_reporte_desperdicio(date,date,text)','EXECUTE'),'T13-CA2: anon sin desperdicio';
 assert not has_function_privilege('public','public.admin_reporte_desperdicio(date,date,text)','EXECUTE'),'T13-CA2: public sin desperdicio';
end $$;
set local role authenticated;
do $$ declare claims text; fn text; denied boolean; begin
 foreach claims in array array['{"sub":"b2130000-0000-0000-0000-000000000002","aal":"aal2"}','{"sub":"b2130000-0000-0000-0000-000000000003","aal":"aal2"}','{"sub":"b2130000-0000-0000-0000-000000000001","aal":"aal1"}'] loop
 perform set_config('request.jwt.claims',claims,true);
 foreach fn in array array['admin_reporte_uso','admin_reporte_desperdicio'] loop
 denied:=false;
 begin execute format('select * from public.%I($1,$2)',fn) using '1800-01-01'::date,'1800-03-31'::date;exception when insufficient_privilege then denied:=true;end;
 assert denied,'T13-CA2: editor soporte y aal1 reciben 42501 en '||fn;
 end loop;end loop;
end $$;
reset role;
rollback;
