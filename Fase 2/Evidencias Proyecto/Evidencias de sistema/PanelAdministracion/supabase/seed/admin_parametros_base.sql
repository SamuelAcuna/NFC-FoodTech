-- Propuestas iniciales editables (D20); no modifica parámetros ya existentes.
begin;
insert into public.parametro(clave,tipo_dato,valor,descripcion,actualizado_por) values
 ('notif.vencimiento.habilitada','BOOLEANO','true','Aviso de vencimiento próximo activo por defecto',null),
 ('notif.vencimiento.dias_anticipacion','ENTERO','3','Días de anticipación del aviso de vencimiento (0–30)',null),
 ('notif.vencimiento.canales','JSON','["PUSH","EMAIL"]','Canales del aviso de vencimiento',null),
 ('notif.lista_compra.habilitada','BOOLEANO','true','Sugerencias de lista de compras activas por defecto',null),
 ('notif.lista_compra.canales','JSON','["PUSH"]','Canales de sugerencias de lista',null),
 ('notif.resumen_semanal.habilitado','BOOLEANO','true','Resumen semanal de estadísticas activo por defecto',null),
 ('notif.resumen_semanal.canales','JSON','["EMAIL"]','Canales del resumen semanal',null),
 ('notif.hora_envio','TEXTO','09:00','Hora local por defecto de envío (HH:MM, 24 h)',null),
 ('hogar.max_miembros','ENTERO','8','Máximo de miembros por hogar (1–20)',null),
 ('hogar.invitacion_vigencia_horas','ENTERO','48','Vigencia del código de invitación en horas (1–720)',null)
on conflict(clave) do nothing;
commit;
