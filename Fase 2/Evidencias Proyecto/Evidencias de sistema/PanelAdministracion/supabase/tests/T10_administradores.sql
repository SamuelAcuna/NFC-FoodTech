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
set local role authenticated;
do $$ declare target uuid; r bigint; p bigint; begin
 assert exists(select 1 from public.admin_listar_administradores() where perfil_id=auth.uid());
 target:=public.admin_asignar_rol(' USUARIO-B1@LOCAL ','EDITOR_CATALOGO'); assert target='b1000000-0000-0000-0000-000000000004';
 begin perform public.admin_asignar_rol('usuario-b1@local','EDITOR_CATALOGO'); raise exception 'Duplicado permitido'; exception when raise_exception then assert sqlerrm='El usuario ya tiene ese rol.'; end;
 perform public.admin_quitar_rol(target,'EDITOR_CATALOGO');
 begin perform public.admin_quitar_rol(target,'EDITOR_CATALOGO'); raise exception 'Ausente permitido'; exception when raise_exception then assert sqlerrm='El usuario no tiene ese rol.'; end;
 begin perform public.admin_quitar_rol(auth.uid(),'ADMIN'); raise exception 'Propio permitido'; exception when raise_exception then assert sqlerrm='No puedes quitarte tus propios roles.','AJ-CA2: T10 usa mensaje actualizado para rol propio'; end;
 begin perform public.admin_asignar_rol('noexiste-b1@local','ADMIN'); raise exception 'Inexistente permitido'; exception when raise_exception then assert sqlerrm='No existe un usuario registrado con ese correo.'; end;
 begin perform public.admin_asignar_rol('usuario-b1@local','NO_EXISTE'); raise exception 'Rol inexistente permitido'; exception when raise_exception then assert sqlerrm='El rol no existe.'; end;
 -- D9b: permiso nuevo que aún no está en el rol sistema, evita confundir unique_violation con RLS.
 insert into public.rol(codigo,nombre) values('B1_ROL_LIBRE','B1 rol libre') returning id into r;
 select id into p from public.permiso order by id limit 1;
 insert into public.rol_permiso(rol_id,permiso_id) values(r,p);
 delete from public.rol_permiso where rol_id=r and permiso_id=p;assert found;
 delete from public.rol_permiso where rol_id in(select id from public.rol where es_sistema);assert not found;
end $$;
reset role;
do $$ declare p bigint; r bigint; begin
 assert exists(select 1 from public.auditoria where entidad='perfil_rol' and entidad_id like 'b1000000-0000-0000-0000-000000000004:%' and accion='INSERT');
 assert exists(select 1 from public.auditoria where entidad='perfil_rol' and entidad_id like 'b1000000-0000-0000-0000-000000000004:%' and accion='DELETE');
 insert into public.permiso(codigo,modulo,descripcion) values('B1_TEST_NUEVO','B1','Prueba') returning id into p;
 select id into r from public.rol where codigo='ADMIN';
 perform set_config('t10.permiso',p::text,true);perform set_config('t10.rol',r::text,true);
end $$;
set local role authenticated;
do $$ begin
 begin insert into public.rol_permiso(rol_id,permiso_id) values(current_setting('t10.rol')::bigint,current_setting('t10.permiso')::bigint);raise exception 'Sistema insertable';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
update public.perfil set estado_cuenta='SUSPENDIDA' where id='b1000000-0000-0000-0000-000000000004';
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_asignar_rol('usuario-b1@local','ADMIN');raise exception 'Suspendido permitido';exception when raise_exception then assert sqlerrm='La cuenta del usuario no está activa.';end;
end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
-- Último ADMIN aislado; ejecutor activo con rol de prueba ROLES_GESTIONAR.
update public.perfil set estado_cuenta='SUSPENDIDA' where id in(select pr.perfil_id from public.perfil_rol pr join public.rol r on r.id=pr.rol_id where r.codigo='ADMIN') and id<>'b1000000-0000-0000-0000-000000000001';
update public.perfil set estado_cuenta='ACTIVA' where id='b1000000-0000-0000-0000-000000000004';
do $$ declare r bigint; begin
 insert into public.rol(codigo,nombre) values('B1_ROLES','B1 roles') returning id into r;
 insert into public.rol_permiso(rol_id,permiso_id) select r,id from public.permiso where codigo='ROLES_GESTIONAR';
 insert into public.perfil_rol(perfil_id,rol_id) values('b1000000-0000-0000-0000-000000000004',r);
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000004","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_quitar_rol('b1000000-0000-0000-0000-000000000001','ADMIN');raise exception 'Último ADMIN permitido';exception when raise_exception then assert sqlerrm='No se puede quitar el último administrador activo de la plataforma.';end;
end $$;
reset role;
do $$ declare claims text; begin
 foreach claims in array array['{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2"}','{"sub":"b1000000-0000-0000-0000-000000000003","aal":"aal2"}','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal1"}'] loop
 perform set_config('request.jwt.claims',claims,true);
 begin perform public.admin_listar_administradores(); raise exception 'Listado permitido'; exception when insufficient_privilege then null;end;
 begin perform public.admin_asignar_rol('usuario-b1@local','ADMIN'); raise exception 'Asignación permitida'; exception when insufficient_privilege then null;end;
 begin perform public.admin_quitar_rol('b1000000-0000-0000-0000-000000000001','ADMIN'); raise exception 'Retirada permitida'; exception when insufficient_privilege then null;end;
 end loop;
end $$;
rollback;
