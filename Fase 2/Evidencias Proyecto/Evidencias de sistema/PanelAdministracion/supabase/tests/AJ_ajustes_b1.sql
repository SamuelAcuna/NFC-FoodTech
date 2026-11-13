-- Fixture como superusuario; auditoría verificada después de RESET ROLE.
begin;
insert into auth.users(id,email,role,aud) values
 ('b2a10000-0000-0000-0000-000000000001','admin-aj@local','authenticated','authenticated'),
 ('b2a10000-0000-0000-0000-000000000002','otro-aj@local','authenticated','authenticated');
insert into public.perfil(id,estado_cuenta) select id,'ACTIVA' from auth.users where email like '%-aj@local' on conflict(id) do update set estado_cuenta='ACTIVA';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2a10000-0000-0000-0000-000000000001',id from public.rol where codigo in ('ADMIN','EDITOR_CATALOGO');
insert into public.perfil_rol(perfil_id,rol_id) select 'b2a10000-0000-0000-0000-000000000002',id from public.rol where codigo='EDITOR_CATALOGO';
select set_config('request.jwt.claims','{"sub":"b2a10000-0000-0000-0000-000000000001","aal":"aal2"}',true);
set local role authenticated;
do $$ declare code text; msg text; begin
 foreach code in array array['ADMIN','EDITOR_CATALOGO'] loop
 msg:=null;
 begin perform public.admin_quitar_rol(auth.uid(),code); exception when raise_exception then msg:=sqlerrm;end;
 assert msg='No puedes quitarte tus propios roles.','AJ-CA2: bloqueo de cualquier rol propio '||code;
 end loop;
 perform public.admin_quitar_rol('b2a10000-0000-0000-0000-000000000002','EDITOR_CATALOGO');
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b2a10000-0000-0000-0000-000000000002","aal":"aal2"}',true);
set local role authenticated;
do $$ declare denied boolean := false; begin
 begin perform public.admin_quitar_rol('b2a10000-0000-0000-0000-000000000001','ADMIN'); exception when insufficient_privilege then denied:=true; end;
 assert denied,'AJ-CA1: editor catalogo recibe 42501';
end $$;
reset role;
do $$ begin
 assert (select count(*) from public.perfil_rol pr join public.rol r on r.id=pr.rol_id where pr.perfil_id='b2a10000-0000-0000-0000-000000000001' and r.codigo in ('ADMIN','EDITOR_CATALOGO'))=2,'AJ-CA2: roles propios intactos';
 assert not exists(select 1 from public.perfil_rol where perfil_id='b2a10000-0000-0000-0000-000000000002'),'AJ-CA3: rol ajeno eliminado';
 assert exists(select 1 from public.auditoria where entidad='perfil_rol' and accion='DELETE' and perfil_id='b2a10000-0000-0000-0000-000000000001' and antes->>'perfil_id'='b2a10000-0000-0000-0000-000000000002'),'AJ-CA3: eliminación ajena auditada';
 assert not has_function_privilege('anon','public.admin_quitar_rol(uuid,text)','EXECUTE'),'AJ-CA1: anon sin execute';
 assert not has_function_privilege('public','public.admin_quitar_rol(uuid,text)','EXECUTE'),'AJ-CA1: public sin execute';
end $$;
rollback;
