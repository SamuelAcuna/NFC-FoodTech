-- Ejecutar solo en entorno de verificación autorizado. IDs privados creados como superusuario.
begin;
insert into auth.users(id,email,role,aud) values
 ('b2110000-0000-0000-0000-000000000001','admin-t11@local','authenticated','authenticated'),
 ('b2110000-0000-0000-0000-000000000002','editor-t11@local','authenticated','authenticated'),
 ('b2110000-0000-0000-0000-000000000003','soporte-t11@local','authenticated','authenticated');
insert into public.perfil(id,estado_cuenta) select id,'ACTIVA' from auth.users where email like '%-t11@local' on conflict(id) do update set estado_cuenta='ACTIVA';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2110000-0000-0000-0000-000000000001',id from public.rol where codigo='ADMIN';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2110000-0000-0000-0000-000000000002',id from public.rol where codigo='EDITOR_CATALOGO';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2110000-0000-0000-0000-000000000003',id from public.rol where codigo='SOPORTE';
insert into public.hogar(id,nombre,creado_por,adultos,menores) values
 ('b211aa00-0000-0000-0000-000000000010','T11 % activo','b2110000-0000-0000-0000-000000000001',2,1),
 ('b211bb00-0000-0000-0000-000000000010','T11 vacío','b2110000-0000-0000-0000-000000000001',1,0);
insert into public.region(id,nombre,orden) values(99,'T11 Región',99) on conflict (id) do nothing;
insert into public.comuna(id,nombre,region_id) values(9999,'T11 Comuna',99) on conflict (id) do nothing;
update public.hogar set comuna_id=9999 where id='b211aa00-0000-0000-0000-000000000010';
insert into public.hogar_miembro(hogar_id,perfil_id,estado) values
 ('b211aa00-0000-0000-0000-000000000010','b2110000-0000-0000-0000-000000000001','ACTIVO'),
 ('b211aa00-0000-0000-0000-000000000010','b2110000-0000-0000-0000-000000000002','INVITADO');
do $$ declare c bigint; a bigint; d uuid; begin
 insert into public.categoria(nombre) values('T11 prueba') returning id into c;
 insert into public.alimento(nombre,categoria_id,unidad_base) values('T11 privado',c,'un') returning id into a;
 insert into public.despensa_item(hogar_id,alimento_id,cantidad_inicial,cantidad_restante) values('b211aa00-0000-0000-0000-000000000010',a,100,100) returning id into d;
 assert d is not null,'T11-CA3: fixture despensa creada antes de activar RLS';
 perform set_config('t11.item',d::text,true);
 insert into public.despensa_item(hogar_id,alimento_id,cantidad_inicial,cantidad_restante,estado) values('b211aa00-0000-0000-0000-000000000010',a,1,0,'AGOTADO');
 insert into public.movimiento(despensa_item_id,tipo,cantidad,registrado_por) select d,'CONSUMO',1,'b2110000-0000-0000-0000-000000000001' from generate_series(1,25);
end $$;
select set_config('request.jwt.claims','{"sub":"b2110000-0000-0000-0000-000000000001","aal":"aal2"}',true);
set local role authenticated;
do $$ declare r record; j jsonb; begin
 select * into strict r from public.admin_listar_hogares('T11 %');
 assert r.integrantes=1 and r.invitados=1 and r.adultos=2 and r.menores=1,'T11-CA3: miembros y composición exactos';
 assert r.movimientos_30d=25 and r.nivel_actividad='ALTA' and r.productos_disponibles=1 and r.ultimo_movimiento is not null,'T11-CA3: actividad y productos sin multiplicar joins';
 assert r.hogar_ref='hogar_b211aa' and r.comuna='T11 Comuna' and r.region='T11 Región','T11-CA3: referencia y ubicación resueltas';
 select to_jsonb(x) into strict j from public.admin_listar_hogares('T11 vacío','SIN_ACTIVIDAD') x;
 assert j->>'movimientos_30d'='0' and j->>'productos_disponibles'='0' and j->>'ultimo_movimiento' is null and j->>'comuna' is null and j->>'region' is null,'T11-CA3: hogar sin actividad ni comuna';
 assert (select count(*) from public.admin_listar_hogares('T11 ','ALTA'))=1,'T11-CA3: filtro de nivel';
 assert (select count(*) from public.admin_listar_hogares('T11 ',null,1,1))=1,'T11-CA3: paginación';
 assert (select array_agg(k order by k) from jsonb_object_keys(j) k)=array['adultos','comuna','creado_en','hogar_ref','integrantes','invitados','menores','movimientos_30d','nivel_actividad','nombre','productos_disponibles','region','total','ultimo_movimiento'],'T11-CA4: firma exacta sin datos privados';
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b2110000-0000-0000-0000-000000000003","aal":"aal2"}',true);
set local role authenticated;
do $$ begin assert (select count(*) from public.admin_listar_hogares('T11 '))=2,'T11-CA2: soporte autorizado'; end $$;
reset role;
do $$ begin
 assert not has_function_privilege('anon','public.admin_listar_hogares(text,text,integer,integer)','EXECUTE'),'T11-CA2: anon sin execute';
 assert not has_function_privilege('public','public.admin_listar_hogares(text,text,integer,integer)','EXECUTE'),'T11-CA2: public sin execute';
end $$;
set local role authenticated;
do $$ declare claims text; denied boolean; begin
 foreach claims in array array['{"sub":"b2110000-0000-0000-0000-000000000002","aal":"aal2"}','{"sub":"b2110000-0000-0000-0000-000000000001","aal":"aal1"}'] loop
 perform set_config('request.jwt.claims',claims,true); denied:=false;
 begin perform public.admin_listar_hogares(); exception when insufficient_privilege then denied:=true; end;
 assert denied,'T11-CA2: editor y aal1 reciben 42501';
 end loop;
end $$;
reset role;
rollback;
