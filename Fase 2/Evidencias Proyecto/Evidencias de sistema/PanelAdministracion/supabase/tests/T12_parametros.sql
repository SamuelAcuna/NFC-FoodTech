-- Preparación como superusuario; verificación de auditoría tras RESET ROLE. No ejecutar en la base real.
begin;
insert into auth.users(id,email,role,aud) values
 ('b2120000-0000-0000-0000-000000000001','admin-t12@local','authenticated','authenticated'),
 ('b2120000-0000-0000-0000-000000000002','editor-t12@local','authenticated','authenticated'),
 ('b2120000-0000-0000-0000-000000000003','soporte-t12@local','authenticated','authenticated');
insert into public.perfil(id,estado_cuenta) select id,'ACTIVA' from auth.users where email like '%-t12@local' on conflict(id) do update set estado_cuenta='ACTIVA';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2120000-0000-0000-0000-000000000001',id from public.rol where codigo='ADMIN';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2120000-0000-0000-0000-000000000002',id from public.rol where codigo='EDITOR_CATALOGO';
insert into public.perfil_rol(perfil_id,rol_id) select 'b2120000-0000-0000-0000-000000000003',id from public.rol where codigo='SOPORTE';
-- La semilla se verifica aparte aplicándola dos veces: sus BEGIN/COMMIT no se incluyen aquí.
insert into public.parametro(clave,tipo_dato,valor) values
 ('t12.entero','ENTERO','1'),('t12.decimal','DECIMAL','1.2'),('t12.booleano','BOOLEANO','true'),('t12.json','JSON','{}'),('t12.texto','TEXTO','original'),
 ('notif.vencimiento.dias_anticipacion','ENTERO','3'),('hogar.max_miembros','ENTERO','8'),('hogar.invitacion_vigencia_horas','ENTERO','48'),('notif.hora_envio','TEXTO','09:00'),('notif.vencimiento.canales','JSON','["PUSH"]')
on conflict(clave) do nothing;
select set_config('request.jwt.claims','{"sub":"b2120000-0000-0000-0000-000000000002","aal":"aal2"}',true);
set local role authenticated;
select public.admin_actualizar_parametro('t12.entero',' 42 ');
do $$ declare t record; before_value text; actual_message text; begin
 for t in select * from (values
 ('t12.entero','1.2','El valor debe ser un número entero.'),
 ('t12.entero','abc','El valor debe ser un número entero.'),
 ('t12.decimal','1,2','El valor debe ser un número decimal.'),
 ('t12.booleano','TRUE','El valor debe ser verdadero o falso.'),
 ('t12.booleano','1','El valor debe ser verdadero o falso.'),
 ('t12.json','{','El valor debe ser JSON válido.'),
 ('t12.texto','','El texto debe tener entre 1 y 200 caracteres.'),
 ('t12.texto',repeat('a',201),'El texto debe tener entre 1 y 200 caracteres.'),
 ('notif.vencimiento.dias_anticipacion','31','El valor está fuera del rango permitido.'),
 ('notif.vencimiento.dias_anticipacion','-1','El valor está fuera del rango permitido.'),
 ('hogar.max_miembros','0','El valor está fuera del rango permitido.'),
 ('hogar.max_miembros','21','El valor está fuera del rango permitido.'),
 ('hogar.invitacion_vigencia_horas','0','El valor está fuera del rango permitido.'),
 ('hogar.invitacion_vigencia_horas','721','El valor está fuera del rango permitido.'),
 ('notif.hora_envio','24:00','La hora debe tener formato HH:MM.'),
 ('notif.hora_envio','9:00','La hora debe tener formato HH:MM.'),
 ('notif.hora_envio','12:60','La hora debe tener formato HH:MM.'),
 ('notif.vencimiento.canales','[]','Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'),
 ('notif.vencimiento.canales','["PUSH","PUSH"]','Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'),
 ('notif.vencimiento.canales','["SMS"]','Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'),
 ('notif.vencimiento.canales','{}','Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'),
 ('t12.inexistente','x','El parámetro no existe.')
 ) v(k,val,msg) loop
 select valor into before_value from public.parametro where clave=t.k;
 actual_message:=null;
 begin perform public.admin_actualizar_parametro(t.k,t.val); exception when raise_exception then actual_message:=sqlerrm; end;
 assert actual_message=t.msg,'T12-CA3/4: mensaje exacto para '||t.k||' con '||t.val;
 assert (select valor from public.parametro where clave=t.k) is not distinct from before_value,'T12-CA3: valor intacto tras fallo '||t.k;
 end loop;
 perform public.admin_actualizar_parametro('t12.decimal','-1.25');
 perform public.admin_actualizar_parametro('t12.booleano','false');
 perform public.admin_actualizar_parametro('t12.json',' { "a": 1 } ');
 perform public.admin_actualizar_parametro('t12.texto',' texto ');
 perform public.admin_actualizar_parametro('notif.vencimiento.dias_anticipacion','0');
 perform public.admin_actualizar_parametro('hogar.max_miembros','20');
 perform public.admin_actualizar_parametro('hogar.invitacion_vigencia_horas','720');
 perform public.admin_actualizar_parametro('notif.hora_envio','23:59');
 perform public.admin_actualizar_parametro('notif.vencimiento.canales','["EMAIL","IN_APP"]');
end $$;
reset role;
do $$ begin
 assert (select valor='42' and actualizado_por='b2120000-0000-0000-0000-000000000002'::uuid from public.parametro where clave='t12.entero'),'T12-CA2: valor normalizado y autor';
 assert exists(select 1 from public.auditoria where entidad='parametro' and entidad_id='t12.entero' and accion='UPDATE' and perfil_id='b2120000-0000-0000-0000-000000000002'),'T12-CA2: UPDATE auditado como superusuario';
 assert (select valor='texto' from public.parametro where clave='t12.texto'),'T12-CA2: trim';
 assert (select valor='{"a": 1}' from public.parametro where clave='t12.json'),'T12-CA2: JSON normalizado';
 assert not has_function_privilege('anon','public.admin_actualizar_parametro(text,text)','EXECUTE'),'T12-CA4: anon sin execute';
 assert not has_function_privilege('public','public.admin_actualizar_parametro(text,text)','EXECUTE'),'T12-CA4: public sin execute';
end $$;
set local role authenticated;
do $$ declare claims text; denied boolean; begin
 foreach claims in array array['{"sub":"b2120000-0000-0000-0000-000000000003","aal":"aal2"}','{"sub":"b2120000-0000-0000-0000-000000000001","aal":"aal1"}'] loop
 perform set_config('request.jwt.claims',claims,true);denied:=false;
 begin perform public.admin_actualizar_parametro('t12.entero','99');exception when insufficient_privilege then denied:=true;end;
 assert denied,'T12-CA4: soporte y aal1 reciben 42501';
 end loop;
end $$;
reset role;
rollback;
