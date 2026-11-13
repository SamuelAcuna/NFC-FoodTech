-- Test transaccional para T01: roles administrativos, función de autorización y políticas base.
-- NO ejecutar contra la base real. Lo corre Claude con OK de Samuel.
-- Cubre CA2–CA11 de la spec.

begin;

-- ============================================================
-- Preparación: crear 4 usuarios de prueba con trigger handle_new_user.
-- El trigger crea automáticamente el perfil con estado_cuenta = 'ACTIVA'.
-- ============================================================

-- UUID fijos para reproducibilidad.
do $$
declare
  v_admin_id    uuid := 'a0000000-0000-0000-0000-000000000001';
  v_editor_id   uuid := 'a0000000-0000-0000-0000-000000000002';
  v_sinrol_id   uuid := 'a0000000-0000-0000-0000-000000000003';
  v_suspendido_id uuid := 'a0000000-0000-0000-0000-000000000004';
  v_rol_admin_id   bigint;
  v_rol_editor_id  bigint;
begin
  -- Insertar usuarios en auth.users (el trigger handle_new_user crea el perfil).
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
  values
    (v_admin_id,      'test-admin@t01.local',      crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_editor_id,     'test-editor@t01.local',     crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_sinrol_id,     'test-sinrol@t01.local',     crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_suspendido_id, 'test-suspendido@t01.local', crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  on conflict (id) do nothing;

  -- Suspender la cuenta del usuario suspendido.
  update public.perfil set estado_cuenta = 'SUSPENDIDA' where id = v_suspendido_id;

  -- Asignar roles.
  select id into v_rol_admin_id  from public.rol where codigo = 'ADMIN';
  select id into v_rol_editor_id from public.rol where codigo = 'EDITOR_CATALOGO';

  insert into public.perfil_rol (perfil_id, rol_id) values
    (v_admin_id,      v_rol_admin_id),
    (v_editor_id,     v_rol_editor_id),
    (v_suspendido_id, v_rol_admin_id)
  on conflict (perfil_id, rol_id) do nothing;
end;
$$;

-- ============================================================
-- CA2: ADMIN con aal1 → es_admin() = false
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';

do $$
begin
  assert public.es_admin() = false,
    'CA2 FALLO: ADMIN con aal1 debería obtener es_admin() = false';
end;
$$;

reset role;

-- ============================================================
-- CA3: ADMIN con aal2 → es_admin() = true y es_admin('ROLES_GESTIONAR') = true
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
begin
  assert public.es_admin() = true,
    'CA3a FALLO: ADMIN con aal2 debería obtener es_admin() = true';
  assert public.es_admin('ROLES_GESTIONAR') = true,
    'CA3b FALLO: ADMIN con aal2 debería obtener es_admin(ROLES_GESTIONAR) = true';
end;
$$;

-- Verificar también mi_contexto_admin para ADMIN con aal2.
do $$
declare
  v_ctx jsonb;
begin
  v_ctx := public.mi_contexto_admin();
  assert (v_ctx ->> 'tiene_rol')::boolean = true,
    'CA3c FALLO: mi_contexto_admin para ADMIN debería tener tiene_rol = true';
  assert v_ctx ->> 'aal' = 'aal2',
    'CA3d FALLO: mi_contexto_admin debería reflejar aal2';
  assert v_ctx ->> 'estado_cuenta' = 'ACTIVA',
    'CA3e FALLO: mi_contexto_admin debería reflejar estado_cuenta ACTIVA';
  assert v_ctx -> 'roles' ? 'ADMIN',
    'CA3f FALLO: mi_contexto_admin debería incluir rol ADMIN';
  assert v_ctx -> 'permisos' ? 'ROLES_GESTIONAR',
    'CA3g FALLO: mi_contexto_admin debería incluir permiso ROLES_GESTIONAR';
  -- Verificar que ADMIN tiene los 11 permisos.
  assert jsonb_array_length(v_ctx -> 'permisos') = 11,
    'CA3h FALLO: ADMIN debería tener los 11 permisos';
end;
$$;

-- CA3: ADMIN puede leer la tabla rol.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.rol;
  assert v_count >= 3,
    'CA3i FALLO: ADMIN con aal2 debería poder ver los roles (al menos 3)';
end;
$$;

-- CA3: ADMIN puede leer permiso.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.permiso;
  assert v_count >= 11,
    'CA3j FALLO: ADMIN con aal2 debería poder ver los permisos (al menos 11)';
end;
$$;

-- CA3: ADMIN puede leer perfil_rol (incluso de otros).
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.perfil_rol;
  assert v_count >= 3,
    'CA3k FALLO: ADMIN con aal2 debería poder ver todas las asignaciones perfil_rol';
end;
$$;

-- CA3: ADMIN puede leer perfil (de otros).
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.perfil;
  assert v_count >= 4,
    'CA3l FALLO: ADMIN con aal2 debería poder ver perfiles';
end;
$$;

reset role;

-- ============================================================
-- CA4: EDITOR_CATALOGO con aal2 → es_admin('ROLES_GESTIONAR') = false
--       y NO puede insertar en rol.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
begin
  assert public.es_admin() = true,
    'CA4a FALLO: EDITOR_CATALOGO con aal2 debería tener es_admin() = true (tiene un rol)';
  assert public.es_admin('ROLES_GESTIONAR') = false,
    'CA4b FALLO: EDITOR_CATALOGO no debería tener permiso ROLES_GESTIONAR';
  assert public.es_admin('CATALOGO_GESTIONAR') = true,
    'CA4c FALLO: EDITOR_CATALOGO debería tener permiso CATALOGO_GESTIONAR';
end;
$$;

-- Intentar insertar en rol debe fallar por RLS.
do $$
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('TEST_ROL_ILEGAL', 'Rol de prueba', false);
  -- Si llegamos aquí, la inserción tuvo éxito cuando no debería.
  assert false, 'CA4d FALLO: EDITOR_CATALOGO pudo insertar en rol (no debería)';
exception
  when insufficient_privilege then
    null; -- Esperado: la política de INSERT en rol exige ROLES_GESTIONAR.
end;
$$;

-- EDITOR_CATALOGO puede leer rol (tiene es_admin() = true).
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.rol;
  assert v_count >= 3,
    'CA4e FALLO: EDITOR_CATALOGO debería poder leer roles';
end;
$$;

reset role;

-- ============================================================
-- CA5: Usuario sin rol → no ve filas de rol, permiso, perfil.
--       perfil_rol: no tiene filas propias.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';

do $$
begin
  assert public.es_admin() = false,
    'CA5a FALLO: usuario sin rol debería obtener es_admin() = false';
end;
$$;

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.rol;
  assert v_count = 0,
    'CA5b FALLO: usuario sin rol no debería ver filas de rol (vio ' || v_count || ')';
end;
$$;

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.permiso;
  assert v_count = 0,
    'CA5c FALLO: usuario sin rol no debería ver filas de permiso (vio ' || v_count || ')';
end;
$$;

-- perfil_rol: no tiene asignaciones, y no puede ver las ajenas.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.perfil_rol;
  assert v_count = 0,
    'CA5d FALLO: usuario sin rol no debería ver filas de perfil_rol (vio ' || v_count || ')';
end;
$$;

-- perfil: no es admin, así que la política admin_perfil_select no le permite leer.
-- Nota: si la app móvil tiene sus propias políticas SELECT sobre perfil, podrían
-- permitir leer el perfil propio. Aquí solo verificamos que la política del panel no lo filtra.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.perfil;
  assert v_count = 0,
    'CA5e FALLO: usuario sin rol no debería ver perfiles por política admin (vio ' || v_count || '). '
    || 'Nota: si falla, verificar si hay políticas de la app que permiten leer perfil propio.';
end;
$$;

-- mi_contexto_admin para usuario sin rol: funciona pero tiene_rol = false.
do $$
declare
  v_ctx jsonb;
begin
  v_ctx := public.mi_contexto_admin();
  assert (v_ctx ->> 'tiene_rol')::boolean = false,
    'CA5f FALLO: mi_contexto_admin para usuario sin rol debería tener tiene_rol = false';
  assert v_ctx -> 'roles' = '[]'::jsonb,
    'CA5g FALLO: mi_contexto_admin debería tener roles vacío para usuario sin rol';
  assert v_ctx -> 'permisos' = '[]'::jsonb,
    'CA5h FALLO: mi_contexto_admin debería tener permisos vacío para usuario sin rol';
end;
$$;

reset role;

-- ============================================================
-- CA6: ADMIN con cuenta SUSPENDIDA → es_admin() = false
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000004","role":"authenticated","aal":"aal2"}';

do $$
begin
  assert public.es_admin() = false,
    'CA6 FALLO: ADMIN con cuenta SUSPENDIDA debería obtener es_admin() = false';
end;
$$;

-- Verificar que, a pesar de tener el rol, la cuenta suspendida impide leer tablas protegidas.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.rol;
  assert v_count = 0,
    'CA6b FALLO: ADMIN suspendido no debería ver filas de rol (vio ' || v_count || ')';
end;
$$;

-- mi_contexto_admin para ADMIN suspendido: tiene_rol = true, pero estado_cuenta = 'SUSPENDIDA'.
do $$
declare
  v_ctx jsonb;
begin
  v_ctx := public.mi_contexto_admin();
  assert (v_ctx ->> 'tiene_rol')::boolean = true,
    'CA6c FALLO: mi_contexto_admin debería reportar tiene_rol = true (el rol existe)';
  assert v_ctx ->> 'estado_cuenta' = 'SUSPENDIDA',
    'CA6d FALLO: mi_contexto_admin debería reportar estado_cuenta = SUSPENDIDA';
end;
$$;

reset role;

-- ============================================================
-- CA7: anon no puede ejecutar es_admin ni mi_contexto_admin.
-- ============================================================
set local role anon;

do $$
begin
  perform public.es_admin();
  assert false, 'CA7a FALLO: anon pudo ejecutar es_admin (no debería)';
exception
  when insufficient_privilege then
    null; -- Esperado.
end;
$$;

do $$
begin
  perform public.mi_contexto_admin();
  assert false, 'CA7b FALLO: anon pudo ejecutar mi_contexto_admin (no debería)';
exception
  when insufficient_privilege then
    null; -- Esperado.
end;
$$;

reset role;

-- ============================================================
-- CA8: Ningún rol es_sistema se puede borrar desde el cliente.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- Primero verificar que el ADMIN puede borrar un rol NO es_sistema (si existiera).
-- Crear un rol temporal para probarlo.
do $$
declare
  v_test_rol_id bigint;
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('TEST_TEMPORAL', 'Rol temporal de prueba', false)
  returning id into v_test_rol_id;

  -- Intentar borrar: debe funcionar porque no es es_sistema.
  delete from public.rol where id = v_test_rol_id;
end;
$$;

-- Intentar borrar cada rol es_sistema: debe fallar.
do $$
declare
  v_nombre text;
begin
  for v_nombre in select codigo from public.rol where es_sistema = true loop
    begin
      delete from public.rol where codigo = v_nombre and es_sistema = true;
      -- Si llegó aquí sin borrar (0 filas), está bien por la política.
      -- Pero revisemos si realmente no borró.
      if not exists (select 1 from public.rol where codigo = v_nombre) then
        assert false,
          'CA8 FALLO: se pudo borrar el rol es_sistema ' || v_nombre;
      end if;
    exception
      when insufficient_privilege then
        null; -- También aceptable.
    end;
  end loop;
end;
$$;

-- Verificar que los 3 roles es_sistema siguen existiendo.
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.rol where es_sistema = true;
  assert v_count >= 3,
    'CA8b FALLO: deberían quedar al menos 3 roles es_sistema (quedan ' || v_count || ')';
end;
$$;

reset role;

-- ============================================================
-- CA9: ADMIN con aal2 NO puede actualizar un rol con es_sistema = true.
--      En particular, no puede pasar es_sistema a false (bypass de CA8).
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- 9a: Intentar cambiar nombre de un rol es_sistema → 0 filas afectadas.
do $$
declare
  v_updated int;
begin
  update public.rol set nombre = 'Hackeado' where codigo = 'SOPORTE' and es_sistema = true;
  get diagnostics v_updated = row_count;
  assert v_updated = 0,
    'CA9a FALLO: se pudieron actualizar ' || v_updated || ' filas del rol es_sistema SOPORTE';
end;
$$;

-- 9b: Intentar cambiar es_sistema de true a false → 0 filas afectadas.
do $$
declare
  v_updated int;
begin
  update public.rol set es_sistema = false where codigo = 'ADMIN';
  get diagnostics v_updated = row_count;
  assert v_updated = 0,
    'CA9b FALLO: se pudo cambiar es_sistema a false en ADMIN (' || v_updated || ' filas)';
end;
$$;

-- 9c: Verificar que la secuencia bypass UPDATE + DELETE ya no funciona.
do $$
declare
  v_updated int;
begin
  -- Intentar primero el UPDATE que cambiaría es_sistema.
  update public.rol set es_sistema = false where codigo = 'EDITOR_CATALOGO';
  get diagnostics v_updated = row_count;
  assert v_updated = 0,
    'CA9c FALLO: se pudo desmarcar es_sistema de EDITOR_CATALOGO (' || v_updated || ' filas)';
  -- Como el UPDATE no surtió efecto, verificar que el rol sigue intacto.
  assert exists (select 1 from public.rol where codigo = 'EDITOR_CATALOGO' and es_sistema = true),
    'CA9c2 FALLO: EDITOR_CATALOGO ya no tiene es_sistema = true';
end;
$$;

-- 9d: Un ADMIN SÍ puede actualizar un rol NO es_sistema.
do $$
declare
  v_test_id bigint;
  v_updated int;
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('CA9_TEST', 'Temporal CA9', false)
  returning id into v_test_id;

  update public.rol set nombre = 'Temporal CA9 editado' where id = v_test_id;
  get diagnostics v_updated = row_count;
  assert v_updated = 1,
    'CA9d FALLO: no se pudo actualizar un rol no es_sistema';

  -- Limpiar.
  delete from public.rol where id = v_test_id;
end;
$$;

-- 9e: No se puede convertir un rol no es_sistema en es_sistema via UPDATE.
do $$
declare
  v_test_id bigint;
  v_updated int;
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('CA9E_TEST', 'Temporal CA9E', false)
  returning id into v_test_id;

  -- WITH CHECK rechaza con error 42501 (no con 0 filas); se trata como 0 filas.
  begin
    update public.rol set es_sistema = true where id = v_test_id;
    get diagnostics v_updated = row_count;
  exception when insufficient_privilege then
    v_updated := 0;
  end;
  -- WITH CHECK rechaza que el resultado tenga es_sistema = true → 0 filas o error.
  assert v_updated = 0,
    'CA9e FALLO: se pudo promover un rol a es_sistema via UPDATE (' || v_updated || ' filas)';

  -- Limpiar.
  delete from public.rol where id = v_test_id;
end;
$$;

reset role;

-- ============================================================
-- CA10: ADMIN con aal2 NO puede insertar un rol con es_sistema = true.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- 10a: Insertar con es_sistema = true → debe fallar.
do $$
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('ROL_SISTEMA_FALSO', 'Intentar crear sistema', true);
  assert false,
    'CA10a FALLO: se pudo insertar un rol con es_sistema = true';
exception
  when insufficient_privilege then
    null; -- Esperado: WITH CHECK rechaza la fila.
  when others then
    -- new_row_violates_check_option también es aceptable.
    if sqlerrm like '%new row violates%' or sqlerrm like '%check%' then
      null;
    else
      raise;
    end if;
end;
$$;

-- 10b: Verificar que no quedó insertado.
do $$
begin
  assert not exists (select 1 from public.rol where codigo = 'ROL_SISTEMA_FALSO'),
    'CA10b FALLO: el rol ROL_SISTEMA_FALSO quedó insertado';
end;
$$;

-- 10c: Insertar con es_sistema = false SÍ funciona (sanity check).
do $$
declare
  v_id bigint;
begin
  insert into public.rol (codigo, nombre, es_sistema)
  values ('CA10_NORMAL', 'Rol normal de prueba', false)
  returning id into v_id;
  assert v_id is not null,
    'CA10c FALLO: no se pudo insertar un rol con es_sistema = false';
  -- Limpiar.
  delete from public.rol where id = v_id;
end;
$$;

reset role;

-- ============================================================
-- CA11: Protección del último ADMIN activo.
--       Necesitamos un segundo ADMIN para probar ambos escenarios.
-- ============================================================

-- Crear un segundo ADMIN de prueba.
do $$
declare
  v_admin2_id uuid := 'a0000000-0000-0000-0000-000000000005';
  v_rol_admin_id bigint;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
  values (v_admin2_id, 'test-admin2@t01.local', crypt('Test1234!', gen_salt('bf')), now(),
          'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  on conflict (id) do nothing;

  -- El trigger handle_new_user crea el perfil con estado_cuenta = 'ACTIVA'.

  select id into v_rol_admin_id from public.rol where codigo = 'ADMIN';
  insert into public.perfil_rol (perfil_id, rol_id)
  values (v_admin2_id, v_rol_admin_id)
  on conflict (perfil_id, rol_id) do nothing;
end;
$$;

-- 11a: Con dos ADMIN activos, SÍ se puede quitar uno.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_admin2_id uuid := 'a0000000-0000-0000-0000-000000000005';
  v_rol_admin_id bigint;
  v_deleted int;
begin
  select id into v_rol_admin_id from public.rol where codigo = 'ADMIN';

  delete from public.perfil_rol
  where perfil_id = v_admin2_id and rol_id = v_rol_admin_id;
  get diagnostics v_deleted = row_count;

  assert v_deleted = 1,
    'CA11a FALLO: con dos ADMIN activos, debería poder quitar uno (borró ' || v_deleted || ')';
end;
$$;

reset role;

-- 11b: Ahora solo queda un ADMIN (admin1). Intentar borrar su perfil_rol → debe fallar.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_admin_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_rol_admin_id bigint;
begin
  select id into v_rol_admin_id from public.rol where codigo = 'ADMIN';

  delete from public.perfil_rol
  where perfil_id = v_admin_id and rol_id = v_rol_admin_id;

  assert false,
    'CA11b FALLO: se pudo quitar el último ADMIN activo';
exception
  when raise_exception then
    -- Verificar que el mensaje es el esperado.
    assert sqlerrm = 'No se puede quitar el último administrador activo de la plataforma.',
      'CA11b2 FALLO: mensaje inesperado: ' || sqlerrm;
end;
$$;

-- 11c: El último ADMIN sigue asignado.
do $$
declare
  v_admin_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_count int;
begin
  select count(*) into v_count
  from public.perfil_rol as pr
  join public.rol as r on r.id = pr.rol_id
  where pr.perfil_id = v_admin_id and r.codigo = 'ADMIN';
  assert v_count = 1,
    'CA11c FALLO: la asignación ADMIN del último admin debería seguir (encontró ' || v_count || ')';
end;
$$;

reset role;

-- 11d: Si el segundo ADMIN existe pero está SUSPENDIDO, no cuenta como activo.
--      Restaurar admin2 con estado SUSPENDIDA y verificar que no se puede quitar admin1.
do $$
declare
  v_admin2_id uuid := 'a0000000-0000-0000-0000-000000000005';
  v_rol_admin_id bigint;
begin
  -- Restaurar la asignación del segundo admin (borrada en 11a).
  select id into v_rol_admin_id from public.rol where codigo = 'ADMIN';
  insert into public.perfil_rol (perfil_id, rol_id)
  values (v_admin2_id, v_rol_admin_id)
  on conflict (perfil_id, rol_id) do nothing;

  -- Suspender su cuenta.
  update public.perfil set estado_cuenta = 'SUSPENDIDA' where id = v_admin2_id;
end;
$$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_admin_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_rol_admin_id bigint;
begin
  select id into v_rol_admin_id from public.rol where codigo = 'ADMIN';

  delete from public.perfil_rol
  where perfil_id = v_admin_id and rol_id = v_rol_admin_id;

  assert false,
    'CA11d FALLO: se pudo quitar admin1 cuando admin2 está SUSPENDIDO (no debería)';
exception
  when raise_exception then
    assert sqlerrm = 'No se puede quitar el último administrador activo de la plataforma.',
      'CA11d2 FALLO: mensaje inesperado: ' || sqlerrm;
end;
$$;

reset role;

-- 11e: El borrado de una asignación de un rol NO-ADMIN no dispara la protección.
do $$
declare
  v_editor_id uuid := 'a0000000-0000-0000-0000-000000000002';
  v_rol_editor_id bigint;
  v_deleted int;
begin
  select id into v_rol_editor_id from public.rol where codigo = 'EDITOR_CATALOGO';

  delete from public.perfil_rol
  where perfil_id = v_editor_id and rol_id = v_rol_editor_id;
  get diagnostics v_deleted = row_count;

  assert v_deleted = 1,
    'CA11e FALLO: debería poder borrar la asignación EDITOR_CATALOGO (borró ' || v_deleted || ')';
end;
$$;

-- ============================================================
-- Limpieza: el rollback deshace todo lo que hicimos.
-- ============================================================
rollback;
