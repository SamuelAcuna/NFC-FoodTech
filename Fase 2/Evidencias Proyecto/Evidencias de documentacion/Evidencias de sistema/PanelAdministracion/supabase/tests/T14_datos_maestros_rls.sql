-- Test transaccional para T14: políticas del panel para catálogo, parámetros, soporte y referencias.
-- NO ejecutar contra la base real. Lo corre Claude con OK de Samuel.
-- Cubre CA2 a CA10 de la spec.

begin;

-- ============================================================
-- Preparación: usuarios de prueba (ADMIN, EDITOR_CATALOGO, SOPORTE, sin rol).
-- Fixtures para CA4 (hogar y alimento privado), CA6 (alimento en despensa),
-- CA7 (parámetro), CA8 (solicitud de soporte) y CA9 (referencias).
-- ============================================================
do $$
declare
  v_admin_id     uuid := 'c0000000-0000-0000-0000-000000000001';
  v_editor_id    uuid := 'c0000000-0000-0000-0000-000000000002';
  v_soporte_id   uuid := 'c0000000-0000-0000-0000-000000000003';
  v_sinrol_id    uuid := 'c0000000-0000-0000-0000-000000000004';

  v_rol_admin    bigint;
  v_rol_editor   bigint;
  v_rol_soporte  bigint;

  v_cat_id       bigint;
  v_hogar_id     uuid := 'c0000000-0000-0000-0000-000000000010';
  v_alim_cat_id  bigint;
  v_despensa_id  uuid := 'c0000000-0000-0000-0000-000000000020';
  v_soporte_id_t uuid := 'c0000000-0000-0000-0000-000000000030';
  v_region_id    smallint;
begin
  -- 1. Usuarios en auth.users
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
  values
    (v_admin_id,   'admin-t14@local',   crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_editor_id,  'editor-t14@local',  crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_soporte_id, 'soporte-t14@local', crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_sinrol_id,  'sinrol-t14@local',  crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  on conflict (id) do nothing;

  -- 2. Asegurar perfil activo
  insert into public.perfil (id, estado_cuenta)
  values
    (v_admin_id,   'ACTIVA'),
    (v_editor_id,  'ACTIVA'),
    (v_soporte_id, 'ACTIVA'),
    (v_sinrol_id,  'ACTIVA')
  on conflict (id) do update set estado_cuenta = 'ACTIVA';

  -- 3. Asignación de roles
  select id into v_rol_admin   from public.rol where codigo = 'ADMIN';
  select id into v_rol_editor  from public.rol where codigo = 'EDITOR_CATALOGO';
  select id into v_rol_soporte from public.rol where codigo = 'SOPORTE';

  insert into public.perfil_rol (perfil_id, rol_id) values
    (v_admin_id,   v_rol_admin),
    (v_editor_id,  v_rol_editor),
    (v_soporte_id, v_rol_soporte)
  on conflict (perfil_id, rol_id) do nothing;

  -- 4. Categoría base para pruebas
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  if v_cat_id is null then
    insert into public.categoria (nombre) values ('Categoria Fixture T14') returning id into v_cat_id;
  end if;

  -- 5. Fixture CA4: Hogar y alimento privado (LOCAL)
  insert into public.hogar (id, nombre, creado_por)
  values (v_hogar_id, 'Hogar Fixture T14', v_sinrol_id)
  on conflict (id) do nothing;

  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id)
  values ('Alimento Privado Hogar T14', v_cat_id, 'un', 'LOCAL', v_hogar_id)
  on conflict do nothing;

  -- 6. Fixture CA6: Alimento de catálogo referenciado por despensa_item
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id)
  values ('Alimento Catalogo En Despensa T14', v_cat_id, 'un', 'APROBADO', null)
  returning id into v_alim_cat_id;

  insert into public.despensa_item (id, hogar_id, alimento_id, cantidad_inicial, cantidad_restante)
  values (v_despensa_id, v_hogar_id, v_alim_cat_id, 2, 2)
  on conflict (id) do nothing;

  -- 7. Fixture CA7: Parámetro de prueba
  insert into public.parametro (clave, valor, tipo_dato, descripcion, actualizado_por)
  values ('PARAM_TEST_T14', '100', 'ENTERO', 'Parámetro fixture T14', null)
  on conflict (clave) do nothing;

  -- 8. Fixture CA8: Solicitud de soporte de prueba
  insert into public.solicitud_soporte (id, tipo, asunto, mensaje, solicitado_por, estado)
  values (v_soporte_id_t, 'CONSULTA', 'Ticket Fixture T14', 'Mensaje de soporte T14', v_sinrol_id, 'PENDIENTE')
  on conflict (id) do nothing;

  -- 9. Fixture CA9: Asegurar filas en tipo_desperdicio y comuna
  insert into public.tipo_desperdicio (codigo, nombre, es_evitable)
  values ('TEST_DESP_T14', 'Desperdicio Fixture T14', true)
  on conflict (codigo) do nothing;

  select min(id) into v_region_id from public.region;
  if v_region_id is not null then
    insert into public.comuna (id, nombre, region_id)
    values (99998, 'Comuna Fixture T14', v_region_id)
    on conflict (id) do nothing;
  end if;
end;
$$;

-- ============================================================
-- CA2: EDITOR_CATALOGO con aal2 puede crear, editar, dar de baja,
--      reactivar y borrar alimento del catálogo no referenciado.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_cat_id      bigint;
  v_alimento_id bigint;
  v_updated     int;
  v_deleted     int;
  v_activo      boolean;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;

  -- 2a: Crear alimento en el catálogo maestro (hogar_id null, creado_por = auth.uid(), estado = 'APROBADO')
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por, activo)
  values ('Manzana Fuji T14', v_cat_id, 'un', 'APROBADO', null, 'c0000000-0000-0000-0000-000000000002', true)
  returning id into v_alimento_id;

  assert v_alimento_id is not null, 'CA2a FALLO: EDITOR_CATALOGO con aal2 no pudo crear alimento en el catálogo';

  -- 2b: Editar atributos (nombre)
  update public.alimento
  set nombre = 'Manzana Fuji Extra T14'
  where id = v_alimento_id;
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA2b FALLO: EDITOR_CATALOGO no pudo editar el alimento creado';

  -- 2c: Dar de baja lógica (activo = false)
  update public.alimento
  set activo = false
  where id = v_alimento_id;
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA2c FALLO: EDITOR_CATALOGO no pudo dar de baja lógica el alimento';

  select activo into v_activo from public.alimento where id = v_alimento_id;
  assert v_activo = false, 'CA2c FALLO: activo no quedó en false tras la baja';

  -- 2d: Reactivar (activo = true)
  update public.alimento
  set activo = true
  where id = v_alimento_id;
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA2d FALLO: EDITOR_CATALOGO no pudo reactivar el alimento';

  select activo into v_activo from public.alimento where id = v_alimento_id;
  assert v_activo = true, 'CA2d FALLO: activo no quedó en true tras la reactivación';

  -- 2e: Borrar alimento no en uso
  delete from public.alimento where id = v_alimento_id;
  get diagnostics v_deleted = row_count;

  assert v_deleted = 1, 'CA2e FALLO: EDITOR_CATALOGO no pudo eliminar el alimento sin dependencias';
end;
$$;

reset role;

-- ============================================================
-- CA3: Denegación de escrituras en alimento para ADMIN (aal1) y SOPORTE (aal2).
--      INSERT rechazado lanza 42501. UPDATE y DELETE afectan 0 filas o lanzan 42501.
-- ============================================================

-- 3.1: ADMIN con aal1
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';

-- 3.1a: ADMIN aal1 INSERT falla con 42501
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Intento ADMIN aal1', v_cat_id, 'un', 'APROBADO', null, 'c0000000-0000-0000-0000-000000000001');
  assert false, 'CA3.1a FALLO: ADMIN con aal1 pudo insertar alimento';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 3.1b: ADMIN aal1 UPDATE afecta 0 filas o lanza 42501
do $$
declare
  v_updated int;
begin
  update public.alimento set nombre = 'Hack ADMIN aal1' where hogar_id is null;
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA3.1b FALLO: ADMIN con aal1 pudo actualizar alimento (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null; -- Esperado si lanza 42501
end;
$$;

-- 3.1c: ADMIN aal1 DELETE afecta 0 filas o lanza 42501
do $$
declare
  v_deleted int;
begin
  delete from public.alimento where hogar_id is null;
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA3.1c FALLO: ADMIN con aal1 pudo borrar alimento (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null; -- Esperado si lanza 42501
end;
$$;

reset role;

-- 3.2: SOPORTE con aal2
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';

-- 3.2a: SOPORTE aal2 INSERT falla con 42501
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Intento SOPORTE aal2', v_cat_id, 'un', 'APROBADO', null, 'c0000000-0000-0000-0000-000000000003');
  assert false, 'CA3.2a FALLO: SOPORTE con aal2 pudo insertar alimento';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 3.2b: SOPORTE aal2 UPDATE afecta 0 filas o lanza 42501
do $$
declare
  v_updated int;
begin
  update public.alimento set nombre = 'Hack SOPORTE' where hogar_id is null;
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA3.2b FALLO: SOPORTE con aal2 pudo actualizar alimento (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

-- 3.2c: SOPORTE aal2 DELETE afecta 0 filas o lanza 42501
do $$
declare
  v_deleted int;
begin
  delete from public.alimento where hogar_id is null;
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA3.2c FALLO: SOPORTE con aal2 pudo borrar alimento (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- ============================================================
-- CA4: Ningún rol del panel ve filas con hogar_id no nulo,
--      ni puede insertar con hogar_id no nulo ni con estado != 'APROBADO' (42501),
--      ni asignar hogar_id a una fila del catálogo mediante UPDATE (42501).
-- ============================================================

-- 4a: Visibilidad - Ni ADMIN aal2, ni EDITOR aal2, ni SOPORTE aal2 ven alimentos privados
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.alimento where hogar_id is not null;
  assert v_count = 0, 'CA4a1 FALLO: ADMIN aal2 no debe ver alimentos con hogar_id no nulo (vio ' || v_count || ')';
end;
$$;

set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.alimento where hogar_id is not null;
  assert v_count = 0, 'CA4a2 FALLO: EDITOR_CATALOGO aal2 no debe ver alimentos con hogar_id no nulo (vio ' || v_count || ')';
end;
$$;

set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.alimento where hogar_id is not null;
  assert v_count = 0, 'CA4a3 FALLO: SOPORTE aal2 no debe ver alimentos con hogar_id no nulo (vio ' || v_count || ')';
end;
$$;

-- 4b: INSERT con hogar_id no nulo lanza 42501
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Con Hogar Prohibido', v_cat_id, 'un', 'APROBADO', 'c0000000-0000-0000-0000-000000000010', 'c0000000-0000-0000-0000-000000000002');
  assert false, 'CA4b FALLO: se permitió insertar alimento con hogar_id no nulo';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 4c: INSERT con estado distinto de APROBADO lanza 42501
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Propuesto Prohibido', v_cat_id, 'un', 'PROPUESTO', null, 'c0000000-0000-0000-0000-000000000002');
  assert false, 'CA4c FALLO: se permitió insertar alimento con estado distinto de APROBADO';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 4d: UPDATE para asignar hogar_id a fila de catálogo lanza 42501
do $$
declare
  v_id bigint;
begin
  select id into v_id from public.alimento where hogar_id is null limit 1;
  update public.alimento set hogar_id = 'c0000000-0000-0000-0000-000000000010' where id = v_id;
  assert false, 'CA4d FALLO: se permitió asignar hogar_id a fila del catálogo mediante UPDATE';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501 por WITH CHECK
end;
$$;

-- 4e: UPDATE para cambiar estado a distinto de APROBADO lanza 42501
do $$
declare
  v_id bigint;
begin
  select id into v_id from public.alimento where hogar_id is null limit 1;
  update public.alimento set estado = 'RECHAZADO' where id = v_id;
  assert false, 'CA4e FALLO: se permitió cambiar estado a no APROBADO mediante UPDATE';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501 por WITH CHECK
end;
$$;

reset role;

-- ============================================================
-- CA5: INSERT con creado_por distinto de auth.uid() lanza 42501.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

-- 5a: creado_por de otro usuario lanza 42501
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Otro Autor', v_cat_id, 'un', 'APROBADO', null, 'c0000000-0000-0000-0000-000000000001');
  assert false, 'CA5a FALLO: se permitió insertar con creado_por ajeno';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 5b: creado_por nulo lanza 42501
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where parent_id is null limit 1;
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Sin Autor', v_cat_id, 'un', 'APROBADO', null, null);
  assert false, 'CA5b FALLO: se permitió insertar con creado_por nulo';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

reset role;

-- ============================================================
-- CA6: Borrar alimento referenciado por despensa_item falla con 23503
--      y la fila sigue existiendo.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_alim_id bigint;
begin
  -- Fix orquestador: como authenticated no se ve despensa_item (RLS, regla 6); se busca por nombre del catalogo.
  select id into v_alim_id from public.alimento where nombre = 'Alimento Catalogo En Despensa T14';

  begin
    delete from public.alimento where id = v_alim_id;
    assert false, 'CA6 FALLO: se permitió borrar un alimento referenciado por despensa_item';
  exception
    when foreign_key_violation then
      null; -- Esperado: 23503
  end;

  -- Comprobar persistencia de la fila
  assert exists (select 1 from public.alimento where id = v_alim_id),
    'CA6 FALLO: la fila de alimento desapareció a pesar del error de FK';
end;
$$;

reset role;

-- ============================================================
-- CA7: parametro: EDITOR_CATALOGO con aal2 actualiza si actualizado_por = auth.uid().
--      Con otro actualizado_por lanza 42501. SOPORTE no puede actualizar (0 filas o 42501).
--      Ningún rol del panel puede insertar ni borrar.
-- ============================================================

-- 7a: EDITOR_CATALOGO aal2 actualiza con actualizado_por = auth.uid()
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_updated int;
begin
  update public.parametro
  set valor = '150', actualizado_por = 'c0000000-0000-0000-0000-000000000002'
  where clave = 'PARAM_TEST_T14';
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA7a FALLO: EDITOR_CATALOGO con aal2 no pudo actualizar parámetro con actualizado_por propio';
end;
$$;

-- 7b: EDITOR_CATALOGO aal2 con otro actualizado_por lanza 42501
do $$
begin
  update public.parametro
  set valor = '160', actualizado_por = 'c0000000-0000-0000-0000-000000000001'
  where clave = 'PARAM_TEST_T14';
  assert false, 'CA7b FALLO: se permitió actualizar parámetro con actualizado_por ajeno';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501 por WITH CHECK
end;
$$;

-- 7c: SOPORTE aal2 no puede actualizar parámetro (0 filas o 42501)
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_updated int;
begin
  update public.parametro
  set valor = '999', actualizado_por = 'c0000000-0000-0000-0000-000000000003'
  where clave = 'PARAM_TEST_T14';
  get diagnostics v_updated = row_count;

  assert v_updated = 0, 'CA7c FALLO: SOPORTE pudo actualizar parámetro (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

-- 7d: ADMIN aal2 NO puede insertar en parametro (sin política INSERT -> 42501)
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
begin
  insert into public.parametro (clave, valor, tipo_dato)
  values ('NUEVA_CLAVE_HACK', 'valor', 'TEXTO');
  assert false, 'CA7d FALLO: ADMIN aal2 pudo insertar en parametro';
exception
  when insufficient_privilege then
    null; -- Esperado: 42501
end;
$$;

-- 7e: ADMIN aal2 NO puede borrar de parametro (sin política DELETE -> 0 filas o 42501)
do $$
declare
  v_deleted int;
begin
  delete from public.parametro where clave = 'PARAM_TEST_T14';
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA7e FALLO: ADMIN aal2 pudo borrar de parametro (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- ============================================================
-- CA8: solicitud_soporte: SOPORTE y ADMIN con aal2 la leen.
--      EDITOR_CATALOGO ve 0 filas. Nadie del panel puede actualizar (0 filas o 42501).
-- ============================================================

-- 8a: SOPORTE aal2 la lee
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.solicitud_soporte;
  assert v_count >= 1, 'CA8a FALLO: SOPORTE con aal2 debe leer solicitud_soporte (vio ' || v_count || ')';
end;
$$;

-- 8b: ADMIN aal2 la lee
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.solicitud_soporte;
  assert v_count >= 1, 'CA8b FALLO: ADMIN con aal2 debe leer solicitud_soporte (vio ' || v_count || ')';
end;
$$;

-- 8c: EDITOR_CATALOGO aal2 ve 0 filas
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.solicitud_soporte;
  assert v_count = 0, 'CA8c FALLO: EDITOR_CATALOGO aal2 no debe leer solicitud_soporte (vio ' || v_count || ')';
end;
$$;

-- 8d: SOPORTE aal2 NO puede actualizar solicitud_soporte (0 filas o 42501)
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_updated int;
begin
  update public.solicitud_soporte set respuesta = 'Respuesta directa no permitida';
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA8d FALLO: SOPORTE aal2 pudo actualizar solicitud_soporte (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

-- 8e: ADMIN aal2 NO puede actualizar solicitud_soporte (0 filas o 42501)
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_updated int;
begin
  update public.solicitud_soporte set estado = 'CERRADA';
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA8e FALLO: ADMIN aal2 pudo actualizar solicitud_soporte (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- ============================================================
-- CA9: tipo_desperdicio, region y comuna: lectura con cualquier rol y aal2.
--      Sin rol o con aal1 ve 0 filas. Nadie del panel escribe.
-- ============================================================

-- 9a: Lectura permitida para ADMIN aal2, EDITOR aal2 y SOPORTE aal2
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_td int;
  v_rg int;
  v_cm int;
begin
  select count(*) into v_td from public.tipo_desperdicio;
  select count(*) into v_rg from public.region;
  select count(*) into v_cm from public.comuna;

  assert v_td >= 1, 'CA9a1 FALLO: ADMIN aal2 no pudo leer tipo_desperdicio';
  assert v_rg >= 1, 'CA9a1 FALLO: ADMIN aal2 no pudo leer region';
  assert v_cm >= 1, 'CA9a1 FALLO: ADMIN aal2 no pudo leer comuna';
end;
$$;

set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_td int;
  v_rg int;
  v_cm int;
begin
  select count(*) into v_td from public.tipo_desperdicio;
  select count(*) into v_rg from public.region;
  select count(*) into v_cm from public.comuna;

  assert v_td >= 1, 'CA9a2 FALLO: EDITOR aal2 no pudo leer tipo_desperdicio';
  assert v_rg >= 1, 'CA9a2 FALLO: EDITOR aal2 no pudo leer region';
  assert v_cm >= 1, 'CA9a2 FALLO: EDITOR aal2 no pudo leer comuna';
end;
$$;

set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_td int;
  v_rg int;
  v_cm int;
begin
  select count(*) into v_td from public.tipo_desperdicio;
  select count(*) into v_rg from public.region;
  select count(*) into v_cm from public.comuna;

  assert v_td >= 1, 'CA9a3 FALLO: SOPORTE aal2 no pudo leer tipo_desperdicio';
  assert v_rg >= 1, 'CA9a3 FALLO: SOPORTE aal2 no pudo leer region';
  assert v_cm >= 1, 'CA9a3 FALLO: SOPORTE aal2 no pudo leer comuna';
end;
$$;

-- 9b: Sin rol (aal2) o con rol pero aal1 ve 0 filas
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000004","role":"authenticated","aal":"aal2"}';
do $$
declare
  v_td int;
  v_rg int;
  v_cm int;
begin
  select count(*) into v_td from public.tipo_desperdicio;
  select count(*) into v_rg from public.region;
  select count(*) into v_cm from public.comuna;

  assert v_td = 0 and v_rg = 0 and v_cm = 0,
    'CA9b1 FALLO: usuario sin rol no debe leer referencias (vio td=' || v_td || ', rg=' || v_rg || ', cm=' || v_cm || ')';
end;
$$;

set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';
do $$
declare
  v_td int;
  v_rg int;
  v_cm int;
begin
  select count(*) into v_td from public.tipo_desperdicio;
  select count(*) into v_rg from public.region;
  select count(*) into v_cm from public.comuna;

  assert v_td = 0 and v_rg = 0 and v_cm = 0,
    'CA9b2 FALLO: usuario con aal1 no debe leer referencias (vio td=' || v_td || ', rg=' || v_rg || ', cm=' || v_cm || ')';
end;
$$;

-- 9c: Escritura denegada en referencias para cualquier rol del panel (ADMIN aal2)
set local request.jwt.claims = '{"sub":"c0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
do $$
begin
  insert into public.tipo_desperdicio (codigo, nombre, es_evitable)
  values ('HACK_DESP', 'Hack Desperdicio', true);
  assert false, 'CA9c1 FALLO: se permitió insertar en tipo_desperdicio';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
declare
  v_updated int;
begin
  update public.region set nombre = 'Region Modificada' where id = 13;
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA9c2 FALLO: se permitió actualizar region (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
declare
  v_deleted int;
begin
  delete from public.comuna where id = 99998;
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA9c3 FALLO: se permitió borrar en comuna (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- ============================================================
-- CA10: Columna activo en alimento y filas existentes con activo = true.
-- ============================================================
do $$
declare
  v_inactivos int;
  v_col_exists boolean;
begin
  -- 10a: Verificar existencia y tipo de la columna
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'alimento'
      and column_name = 'activo'
      and data_type = 'boolean'
      and is_nullable = 'NO'
  ) into v_col_exists;

  assert v_col_exists = true, 'CA10a FALLO: columna alimento.activo boolean not null no existe';

  -- 10b: Todas las filas maestras preexistentes deben tener activo = true
  select count(*) into v_inactivos
  from public.alimento
  where hogar_id is null and activo is not true;

  assert v_inactivos = 0, 'CA10b FALLO: existen filas del catálogo con activo != true (' || v_inactivos || ')';
end;
$$;

-- ============================================================
-- Limpieza total: rollback deshace usuarios, fixtures y modificaciones.
-- ============================================================
rollback;
