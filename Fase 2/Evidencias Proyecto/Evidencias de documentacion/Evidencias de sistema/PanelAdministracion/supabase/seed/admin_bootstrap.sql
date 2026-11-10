-- Bootstrap manual: ejecutar solo por el orquestador con OK de Samuel,
-- después de la migración T01 y de crear la cuenta del administrador.
-- Cambiar únicamente v_email; no guardar un correo real en este archivo.
do $$
declare
  v_email text := 'CAMBIAR@correo';
  v_perfil_id uuid;
  v_rol_id bigint;
begin
  if v_email = 'CAMBIAR@correo' or nullif(btrim(v_email), '') is null then
    raise exception 'Debe configurar el correo del primer administrador.';
  end if;

  select p.id into strict v_perfil_id
  from auth.users as u
  join public.perfil as p on p.id = u.id
  where lower(u.email) = lower(btrim(v_email));

  select r.id into strict v_rol_id
  from public.rol as r where r.codigo = 'ADMIN';

  insert into public.perfil_rol (perfil_id, rol_id)
  values (v_perfil_id, v_rol_id)
  on conflict (perfil_id, rol_id) do nothing;
end;
$$;
