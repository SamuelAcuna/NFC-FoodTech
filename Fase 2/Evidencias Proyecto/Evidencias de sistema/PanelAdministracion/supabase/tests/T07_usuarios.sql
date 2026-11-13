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

update auth.users set created_at=now(),last_sign_in_at=now() where email like '%-b1@local';
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 assert (select count(*)=4 from public.admin_listar_usuarios('-b1@local'));
 assert (select count(*)=1 from public.admin_listar_usuarios('-b1@local',null,null,null,'ACTIVOS_30',1,0));
 assert (select total=4 from public.admin_listar_usuarios('-b1@local',null,null,null,null,1,0));
 assert (select count(*)=0 from public.admin_listar_usuarios('%'));
 perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','SUSPENDIDA','Motivo prueba');
 begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','SUSPENDIDA','Motivo prueba'); raise exception 'Mismo estado permitido'; exception when raise_exception then assert sqlerrm='La cuenta ya está en ese estado.'; end;
 begin perform public.admin_cambiar_estado_cuenta(auth.uid(),'SUSPENDIDA','Motivo prueba'); raise exception 'Propia permitida'; exception when raise_exception then assert sqlerrm='No puedes cambiar el estado de tu propia cuenta.'; end;
 begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','BANEADA','Motivo prueba'); raise exception 'Baneada permitida'; exception when raise_exception then assert sqlerrm='Estado no válido.'; end;
 begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','ACTIVA','x'); raise exception 'Motivo corto permitido'; exception when raise_exception then assert sqlerrm='El motivo debe tener entre 5 y 500 caracteres.'; end;
 begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000099','ACTIVA','Motivo prueba'); raise exception 'Inexistente permitido'; exception when raise_exception then assert sqlerrm='El usuario no existe.'; end;
end $$;
reset role;
do $$ begin
 assert (select estado_cuenta='SUSPENDIDA' from public.perfil where id='b1000000-0000-0000-0000-000000000004');
 assert exists(select 1 from public.auditoria where entidad='perfil' and entidad_id='b1000000-0000-0000-0000-000000000004' and accion='SUSPENDER' and motivo='Motivo prueba');
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000004","aal":"aal1","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin update public.perfil set estado_cuenta='ACTIVA' where id=auth.uid(); raise exception 'Autoreactivación permitida'; exception when insufficient_privilege then null; end;
 update public.perfil set nombre='Prueba nombre' where id=auth.uid(); assert found;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
select public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','ACTIVA','Reactivación prueba');
reset role;
do $$ begin assert exists(select 1 from public.auditoria where entidad='perfil' and entidad_id='b1000000-0000-0000-0000-000000000004' and accion='REACTIVAR'); end $$;
-- D9a: aislar el único ADMIN activo como superusuario; ejecutor con rol personalizado.
select set_config('request.jwt.claims','{}',true);
update public.perfil set estado_cuenta='SUSPENDIDA' where id in(select pr.perfil_id from public.perfil_rol pr join public.rol r on r.id=pr.rol_id where r.codigo='ADMIN') and id<>'b1000000-0000-0000-0000-000000000001';
do $$ declare r bigint; begin
 insert into public.rol(codigo,nombre) values('B1_SUSPENDER','B1 prueba') returning id into r;
 insert into public.rol_permiso(rol_id,permiso_id) select r,id from public.permiso where codigo='USUARIOS_SUSPENDER';
 insert into public.perfil_rol(perfil_id,rol_id) values('b1000000-0000-0000-0000-000000000004',r);
end $$;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000004","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000001','SUSPENDIDA','Motivo prueba'); raise exception 'Último permitido'; exception when raise_exception then assert sqlerrm='No se puede suspender al último administrador activo.'; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin begin perform public.admin_listar_usuarios(); raise exception 'Editor permitido'; exception when insufficient_privilege then null; end; end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin begin perform public.admin_cambiar_estado_cuenta('b1000000-0000-0000-0000-000000000004','SUSPENDIDA','Motivo prueba'); raise exception 'Soporte permitido'; exception when insufficient_privilege then null; end; end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal1","role":"authenticated"}',true);
set local role authenticated;
do $$ begin begin perform public.admin_listar_usuarios(); raise exception 'aal1 permitido'; exception when insufficient_privilege then null; end; end $$;
reset role;
rollback;
