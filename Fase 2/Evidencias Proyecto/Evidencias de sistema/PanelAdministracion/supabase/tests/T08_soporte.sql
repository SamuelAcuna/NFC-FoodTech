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

insert into public.solicitud_soporte(id,tipo,asunto,mensaje,solicitado_por,prioridad) values
 ('b1080000-0000-0000-0000-000000000001','CONSULTA','B1 flujo','Mensaje privado','b1000000-0000-0000-0000-000000000004',1),
 ('b1080000-0000-0000-0000-000000000002','ERROR','B1 responder','Mensaje privado','b1000000-0000-0000-0000-000000000004',2),
 ('b1080000-0000-0000-0000-000000000003','SUGERENCIA','B1 cerrar','Mensaje privado','b1000000-0000-0000-0000-000000000004',3);
select set_config('request.jwt.claims','{"sub":"b1000000-0000-0000-0000-000000000003","aal":"aal2","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 assert exists(select 1 from public.admin_listar_agentes_soporte() where id=auth.uid());
 assert (select count(*)=1 from public.admin_listar_soporte('ABIERTAS',1,0));
 begin perform public.admin_soporte_asignar('b1080000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000004'); raise exception 'Agente sin permiso permitido'; exception when raise_exception then assert sqlerrm='El agente no tiene permisos de soporte.'; end;
 perform public.admin_soporte_asignar('b1080000-0000-0000-0000-000000000001',auth.uid());
 perform public.admin_soporte_responder('b1080000-0000-0000-0000-000000000001','Respuesta privada');
 begin perform public.admin_soporte_asignar('b1080000-0000-0000-0000-000000000001',auth.uid()); raise exception 'Respondida asignable'; exception when raise_exception then assert sqlerrm='La solicitud no se puede asignar en su estado actual.'; end;
 perform public.admin_soporte_cerrar('b1080000-0000-0000-0000-000000000001');
 perform public.admin_soporte_responder('b1080000-0000-0000-0000-000000000002','Respuesta privada');
 perform public.admin_soporte_cerrar('b1080000-0000-0000-0000-000000000003');
 begin perform public.admin_soporte_asignar('b1080000-0000-0000-0000-000000000001',auth.uid()); raise exception 'Cerrada asignable'; exception when raise_exception then assert sqlerrm='La solicitud no se puede asignar en su estado actual.'; end;
 begin perform public.admin_soporte_responder('b1080000-0000-0000-0000-000000000001','Respuesta privada'); raise exception 'Cerrada respondible'; exception when raise_exception then assert sqlerrm='La solicitud está cerrada.'; end;
 begin perform public.admin_soporte_cerrar('b1080000-0000-0000-0000-000000000001'); raise exception 'Doble cierre'; exception when raise_exception then assert sqlerrm='La solicitud ya está cerrada.'; end;
 begin perform public.admin_soporte_responder('b1080000-0000-0000-0000-000000000002','x'); raise exception 'Corto permitido'; exception when raise_exception then assert sqlerrm='La respuesta debe tener entre 5 y 2000 caracteres.'; end;
 begin perform public.admin_soporte_cerrar('b1080000-0000-0000-0000-000000000099'); raise exception 'Inexistente permitido'; exception when raise_exception then assert sqlerrm='La solicitud no existe.'; end;
end $$;
reset role;
do $$ begin
 assert (select count(*)=3 from public.auditoria where entidad='solicitud_soporte' and entidad_id='b1080000-0000-0000-0000-000000000001');
 assert not exists(select 1 from public.auditoria where entidad='solicitud_soporte' and (antes ?| array['mensaje','respuesta'] or despues ?| array['mensaje','respuesta']));
 assert (select estado='CERRADA' and asignado_a='b1000000-0000-0000-0000-000000000003' and respondido_en is not null and cerrado_en is not null from public.solicitud_soporte where id='b1080000-0000-0000-0000-000000000001');
 assert (select asignado_a='b1000000-0000-0000-0000-000000000003' from public.solicitud_soporte where id='b1080000-0000-0000-0000-000000000002');
 assert (select asignado_a='b1000000-0000-0000-0000-000000000003' from public.solicitud_soporte where id='b1080000-0000-0000-0000-000000000003');
 assert not has_function_privilege('anon','public.admin_soporte_asignar(uuid,uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.admin_soporte_responder(uuid,text)','EXECUTE');
 assert not has_function_privilege('anon','public.admin_soporte_cerrar(uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.admin_listar_soporte(text,integer,integer)','EXECUTE');
 assert not has_function_privilege('anon','public.admin_listar_agentes_soporte()','EXECUTE');
end $$;
-- Denegación de las cinco RPC: editor aal2 y administrador aal1.
do $$ declare claims text; begin
 foreach claims in array array['{"sub":"b1000000-0000-0000-0000-000000000002","aal":"aal2"}','{"sub":"b1000000-0000-0000-0000-000000000001","aal":"aal1"}'] loop
 perform set_config('request.jwt.claims',claims,true);
 begin perform public.admin_listar_soporte(); raise exception 'Listado permitido'; exception when insufficient_privilege then null; end;
 begin perform public.admin_listar_agentes_soporte(); raise exception 'Agentes permitido'; exception when insufficient_privilege then null; end;
 begin perform public.admin_soporte_asignar('b1080000-0000-0000-0000-000000000001',auth.uid()); raise exception 'Asignar permitido'; exception when insufficient_privilege then null; end;
 begin perform public.admin_soporte_responder('b1080000-0000-0000-0000-000000000001','Respuesta'); raise exception 'Responder permitido'; exception when insufficient_privilege then null; end;
 begin perform public.admin_soporte_cerrar('b1080000-0000-0000-0000-000000000001'); raise exception 'Cerrar permitido'; exception when insufficient_privilege then null; end;
 end loop;
end $$;
rollback;
