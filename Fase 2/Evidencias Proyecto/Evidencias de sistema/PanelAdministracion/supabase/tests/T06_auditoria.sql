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
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ declare v_id bigint; begin
  perform set_config('admin.motivo','x',true);
  insert into public.categoria(nombre) values('B1 auditoría') returning id into v_id;
  perform set_config('t06.categoria',v_id::text,true);
  update public.categoria set nombre='B1 auditoría editada' where id=v_id;
  update public.categoria set nombre=nombre where id=v_id;
  delete from public.categoria where id=v_id;
  begin perform public.admin_listar_auditoria(); raise exception 'Se permitió auditoría a editor'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert (select count(*)=3 from public.auditoria where entidad='categoria' and entidad_id=current_setting('t06.categoria'));
  assert (select count(*)=3 from public.auditoria where entidad='categoria' and entidad_id=current_setting('t06.categoria') and perfil_id='b1000000-0000-0000-0000-000000000002' and motivo='x');
  assert (select antes is null and despues->>'nombre'='B1 auditoría' from public.auditoria where entidad='categoria' and entidad_id=current_setting('t06.categoria') and accion='INSERT');
  assert (select despues is null from public.auditoria where entidad='categoria' and entidad_id=current_setting('t06.categoria') and accion='DELETE');
  assert not has_function_privilege('anon','public.admin_listar_auditoria(date,date,text,text,integer,integer)','EXECUTE');
  assert not has_function_privilege('authenticated','public.admin_auditar()','EXECUTE');
  assert (select count(*)=6 from pg_trigger where tgname like 'admin_auditoria_%' and not tgisinternal);
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  assert (select count(*)=1 from public.admin_listar_auditoria(null,null,'categoria','INSERT',1,0) where actor_email is not null);
  begin insert into public.auditoria(entidad,entidad_id,accion) values('test','1','INSERT'); raise exception 'Escritura directa permitida'; exception when insufficient_privilege then null; end;
  assert (select count(*)=0 from public.auditoria);
end $$;
reset role;
-- Fixtures privados obtenidos antes de asumir authenticated (trampa de RLS).
select set_config('request.jwt.claims','{}',true);
insert into public.hogar(id,nombre,creado_por) values('b1000000-0000-0000-0000-000000000010','B1 hogar','b1000000-0000-0000-0000-000000000004');
do $$ declare c bigint; a bigint; b bigint; begin
  insert into public.categoria(nombre) values('B1 propuestas') returning id into c;
  perform set_config('t06.cat',c::text,true);
  insert into public.alimento(nombre,categoria_id,unidad_base,estado,hogar_id,creado_por)
    values('B1 aprobar',c,'un','PROPUESTO','b1000000-0000-0000-0000-000000000010','b1000000-0000-0000-0000-000000000004') returning id into a;
  insert into public.alimento(nombre,categoria_id,unidad_base,estado,hogar_id,creado_por)
    values('B1 rechazar',c,'un','PROPUESTO','b1000000-0000-0000-0000-000000000010','b1000000-0000-0000-0000-000000000004') returning id into b;
  assert a is not null and b is not null;
  perform set_config('t06.aprobar',a::text,true); perform set_config('t06.rechazar',b::text,true);
  assert not exists(select 1 from public.auditoria where entidad='alimento' and entidad_id in(a::text,b::text));
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
select public.admin_aprobar_propuesto(current_setting('t06.aprobar')::bigint,'B1 aprobado',current_setting('t06.cat')::bigint,'un',false,null);
select public.admin_rechazar_propuesto(current_setting('t06.rechazar')::bigint);
reset role;
do $$ begin
  assert exists(select 1 from public.auditoria where entidad_id=current_setting('t06.aprobar') and accion='APROBAR');
  assert exists(select 1 from public.auditoria where entidad_id=current_setting('t06.rechazar') and accion='RECHAZAR');
  assert not exists(select 1 from public.auditoria where entidad='alimento' and (antes ?| array['hogar_id','creado_por'] or despues ?| array['hogar_id','creado_por']));
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r bigint; p bigint; begin
  insert into public.rol(codigo,nombre) values('B1_AUDIT','B1 prueba') returning id into r;
  select id into p from public.permiso order by id limit 1;
  insert into public.rol_permiso(rol_id,permiso_id) values(r,p);
  insert into public.perfil_rol(perfil_id,rol_id) values('b1000000-0000-0000-0000-000000000004',r);
  perform set_config('t06.rp',r::text||':'||p::text,true);
  perform set_config('t06.pr','b1000000-0000-0000-0000-000000000004:'||r::text,true);
  update public.auditoria set motivo='NO'; assert not found;
  delete from public.auditoria; assert not found;
  assert (select count(*)=0 from public.admin_listar_auditoria('2000-01-01','2000-01-01'));
end $$;
reset role;
do $$ begin
 assert exists(select 1 from public.auditoria where entidad='rol_permiso' and entidad_id=current_setting('t06.rp'));
 assert exists(select 1 from public.auditoria where entidad='perfil_rol' and entidad_id=current_setting('t06.pr'));
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal1","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_listar_auditoria(); raise exception 'aal1 permitido'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
