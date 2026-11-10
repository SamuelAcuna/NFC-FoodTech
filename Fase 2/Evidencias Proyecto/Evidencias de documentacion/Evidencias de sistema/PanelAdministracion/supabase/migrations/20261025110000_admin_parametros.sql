begin;
create or replace function public.admin_actualizar_parametro(p_clave text,p_valor text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tipo text; v_valor text:=btrim(p_valor); v_json jsonb; v_num numeric;
begin
 if not public.es_admin('PARAMETROS_GESTIONAR') then raise exception 'No autorizado.' using errcode='42501'; end if;
 select tipo_dato into v_tipo from public.parametro where clave=p_clave for update;
 if not found then raise exception 'El parámetro no existe.'; end if;
 if v_tipo='ENTERO' and (v_valor is null or v_valor !~ '^-?[0-9]+$') then raise exception 'El valor debe ser un número entero.'; end if;
 if v_tipo='DECIMAL' and (v_valor is null or v_valor !~ '^-?[0-9]+(\.[0-9]+)?$') then raise exception 'El valor debe ser un número decimal.'; end if;
 if v_tipo='BOOLEANO' and (v_valor is null or v_valor not in ('true','false')) then raise exception 'El valor debe ser verdadero o falso.'; end if;
 if v_tipo='TEXTO' and (v_valor is null or char_length(v_valor) not between 1 and 200) then raise exception 'El texto debe tener entre 1 y 200 caracteres.'; end if;
 if v_tipo='JSON' then
   begin v_json:=v_valor::jsonb; if v_json is null then raise exception 'JSON nulo'; end if;
   exception when others then raise exception 'El valor debe ser JSON válido.'; end;
   v_valor:=v_json::text;
 end if;
 if p_clave in ('notif.vencimiento.dias_anticipacion','hogar.max_miembros','hogar.invitacion_vigencia_horas') then
   -- Comparar como numeric evita overflow de int en entradas fuera del rango.
   begin v_num:=v_valor::numeric; exception when others then raise exception 'El valor está fuera del rango permitido.'; end;
   if v_num is null or (p_clave='notif.vencimiento.dias_anticipacion' and v_num not between 0 and 30)
    or (p_clave='hogar.max_miembros' and v_num not between 1 and 20)
    or (p_clave='hogar.invitacion_vigencia_horas' and v_num not between 1 and 720) then raise exception 'El valor está fuera del rango permitido.'; end if;
 end if;
 if p_clave='notif.hora_envio' and (v_valor is null or v_valor !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then raise exception 'La hora debe tener formato HH:MM.'; end if;
 if p_clave like '%.canales' then
   if jsonb_typeof(v_json) is distinct from 'array' then raise exception 'Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'; end if;
   if jsonb_array_length(v_json)=0 or exists(select 1 from jsonb_array_elements(v_json) e where e not in ('"PUSH"'::jsonb,'"EMAIL"'::jsonb,'"IN_APP"'::jsonb))
    or (select count(*) from jsonb_array_elements(v_json))<>(select count(distinct e) from jsonb_array_elements(v_json) e)
    then raise exception 'Los canales deben ser una lista no vacía de PUSH, EMAIL o IN_APP.'; end if;
 end if;
 update public.parametro set valor=v_valor,actualizado_por=auth.uid(),actualizado_en=now() where clave=p_clave;
end;
$$;
revoke execute on function public.admin_actualizar_parametro(text,text) from public,anon;
grant execute on function public.admin_actualizar_parametro(text,text) to authenticated;
commit;
