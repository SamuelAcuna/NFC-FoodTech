-- Test transaccional para T05: revisión, aprobación y rechazo de productos propuestos.
-- NO ejecutar contra la base real. Lo corre Claude con OK de Samuel.
-- Cubre CA2 a CA8 de la spec.

begin;

-- ============================================================
-- Preparación (superusuario):
-- Usuarios (ADMIN, EDITOR_CATALOGO, SOPORTE, sin rol).
-- Fixtures: Categorías (activa e inactiva), Hogar, Alimentos propuestos/locales/aprobados/rechazados,
-- y una despensa_item que referencia a un alimento propuesto.
-- ============================================================
do $$
declare
  v_admin_id       uuid := 'd0000000-0000-0000-0000-000000000001';
  v_editor_id      uuid := 'd0000000-0000-0000-0000-000000000002';
  v_soporte_id     uuid := 'd0000000-0000-0000-0000-000000000003';
  v_sinrol_id      uuid := 'd0000000-0000-0000-0000-000000000004';

  v_rol_admin      bigint;
  v_rol_editor     bigint;
  v_rol_soporte    bigint;

  v_cat_activa_id   bigint;
  v_cat_inactiva_id bigint;
  v_hogar_id       uuid := 'd0000000-0000-0000-0000-000000000010';
  v_propuesto_1_id bigint;
  v_propuesto_2_id bigint;
  v_propuesto_3_id bigint;
  v_despensa_id    uuid := 'd0000000-0000-0000-0000-000000000020';
begin
  -- 1. Usuarios en auth.users (sin crypt, password null)
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
  values
    (v_admin_id,   'admin-t05@local',   null, now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_editor_id,  'editor-t05@local',  null, now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_soporte_id, 'soporte-t05@local', null, now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_sinrol_id,  'sinrol-t05@local',  null, now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  on conflict (id) do nothing;

  -- 2. Perfil activo
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

  -- 4. Categoría activa e inactiva
  select id into v_cat_activa_id from public.categoria where parent_id is null and activa = true limit 1;
  if v_cat_activa_id is null then
    insert into public.categoria (nombre, activa) values ('Cat Activa T05', true) returning id into v_cat_activa_id;
  end if;

  insert into public.categoria (nombre, activa) values ('Cat Inactiva T05', false) returning id into v_cat_inactiva_id;

  -- 5. Hogar de prueba
  insert into public.hogar (id, nombre, creado_por)
  values (v_hogar_id, 'Hogar Fixture T05', v_sinrol_id)
  on conflict (id) do nothing;

  -- 6. Propuesta 1 (para aprobar en CA4) y su despensa_item asociada
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Yogur Frutilla Propuesto T05', v_cat_activa_id, 'un', 'PROPUESTO', v_hogar_id, v_sinrol_id)
  returning id into v_propuesto_1_id;

  insert into public.despensa_item (id, hogar_id, alimento_id, cantidad_inicial, cantidad_restante)
  values (v_despensa_id, v_hogar_id, v_propuesto_1_id, 2, 2)
  on conflict (id) do nothing;

  -- 7. Propuesta 2 (para rechazar en CA8)
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Snack Raro Propuesto T05', v_cat_activa_id, 'un', 'PROPUESTO', v_hogar_id, v_sinrol_id)
  returning id into v_propuesto_2_id;

  -- 8. Propuesta 3 (para conflicto de duplicado en CA6)
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Pan Molde Propuesto T05', v_cat_activa_id, 'un', 'PROPUESTO', v_hogar_id, v_sinrol_id)
  returning id into v_propuesto_3_id;

  -- 9. Alimento ya existente en catálogo (para provocar 23505 en CA6)
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por, activo)
  values ('Pan Existente En Catalogo T05', v_cat_activa_id, 'un', 'APROBADO', null, v_admin_id, true)
  on conflict do nothing;

  -- 10. Alimentos en estados no propuestos (LOCAL, RECHAZADO, APROBADO) para CA2 y CA5
  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Privado Local T05', v_cat_activa_id, 'un', 'LOCAL', v_hogar_id, v_sinrol_id)
  on conflict do nothing;

  insert into public.alimento (nombre, categoria_id, unidad_base, estado, hogar_id, creado_por)
  values ('Alimento Previamente Rechazado T05', v_cat_activa_id, 'un', 'RECHAZADO', v_hogar_id, v_sinrol_id)
  on conflict do nothing;
end;
$$;

-- ============================================================
-- CA2: Con PROPUESTOS_REVISAR y aal2, admin_listar_propuestos devuelve
--      solo las filas PROPUESTO con hogar_ref ('hogar_...'),
--      y admin_contar_propuestos coincide con ese total.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_count_listar int;
  v_count_contar int;
  v_sample_ref   text;
begin
  select count(*), min(hogar_ref)
  into v_count_listar, v_sample_ref
  from public.admin_listar_propuestos();

  assert v_count_listar >= 3, 'CA2a FALLO: admin_listar_propuestos devolvió menos filas de las esperadas (' || v_count_listar || ')';
  assert v_sample_ref like 'hogar_%', 'CA2b FALLO: hogar_ref no tiene el formato esperado (obtenido: ' || coalesce(v_sample_ref, 'null') || ')';

  select public.admin_contar_propuestos() into v_count_contar;
  assert v_count_contar = v_count_listar,
    'CA2c FALLO: admin_contar_propuestos (' || v_count_contar || ') no coincide con admin_listar_propuestos (' || v_count_listar || ')';
end;
$$;

reset role;

-- ============================================================
-- CA3: Denegación de las 4 funciones para SOPORTE (aal2), ADMIN (aal1) y anon.
-- ============================================================

-- 3.1: SOPORTE con aal2 carece de PROPUESTOS_REVISAR -> 42501
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';

do $$
begin
  perform * from public.admin_listar_propuestos();
  assert false, 'CA3.1a FALLO: SOPORTE pudo listar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_contar_propuestos();
  assert false, 'CA3.1b FALLO: SOPORTE pudo contar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_aprobar_propuesto(1, 'Test', 1, 'un', true, null);
  assert false, 'CA3.1c FALLO: SOPORTE pudo aprobar propuesto';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_rechazar_propuesto(1);
  assert false, 'CA3.1d FALLO: SOPORTE pudo rechazar propuesto';
exception
  when insufficient_privilege then null;
end;
$$;

reset role;

-- 3.2: ADMIN con aal1 carece de aal2 -> 42501
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';

do $$
begin
  perform * from public.admin_listar_propuestos();
  assert false, 'CA3.2a FALLO: ADMIN aal1 pudo listar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_contar_propuestos();
  assert false, 'CA3.2b FALLO: ADMIN aal1 pudo contar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_aprobar_propuesto(1, 'Test', 1, 'un', true, null);
  assert false, 'CA3.2c FALLO: ADMIN aal1 pudo aprobar propuesto';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_rechazar_propuesto(1);
  assert false, 'CA3.2d FALLO: ADMIN aal1 pudo rechazar propuesto';
exception
  when insufficient_privilege then null;
end;
$$;

reset role;

-- 3.3: anon no tiene permiso execute
set local role anon;

do $$
begin
  perform * from public.admin_listar_propuestos();
  assert false, 'CA3.3a FALLO: anon pudo listar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform public.admin_contar_propuestos();
  assert false, 'CA3.3b FALLO: anon pudo contar propuestos';
exception
  when insufficient_privilege then null;
end;
$$;

reset role;

-- ============================================================
-- CA4: Aprobar deja la fila con estado = 'APROBADO', hogar_id = null,
--      activo = true y datos editados. La despensa_item conserva el id.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_propuesto_id bigint;
  v_cat_id       bigint;
  v_ret_id       bigint;
begin
  select id, categoria_id into v_propuesto_id, v_cat_id
  from public.admin_listar_propuestos()
  where nombre = 'Yogur Frutilla Propuesto T05'
  limit 1;

  v_ret_id := public.admin_aprobar_propuesto(
    v_propuesto_id,
    '  Yogur Griego Frutilla Editado T05  ',
    v_cat_id,
    'g',
    true,
    14
  );

  assert v_ret_id = v_propuesto_id, 'CA4a FALLO: id retornado (' || coalesce(v_ret_id::text, 'null') || ') no coincide con el aprobado';
end;
$$;

-- Verificación de estado, datos y despensa_item como superusuario
reset role;

do $$
declare
  v_estado text;
  v_hogar  uuid;
  v_activo boolean;
  v_nombre text;
  v_unidad text;
  v_dias   int;
  v_desp_alim_id bigint;
begin
  select estado, hogar_id, activo, nombre, unidad_base, vida_util_dias_ref
  into v_estado, v_hogar, v_activo, v_nombre, v_unidad, v_dias
  from public.alimento
  where nombre = 'Yogur Griego Frutilla Editado T05';

  assert v_estado = 'APROBADO', 'CA4b FALLO: estado no quedó en APROBADO (obtenido: ' || coalesce(v_estado, 'null') || ')';
  assert v_hogar is null, 'CA4c FALLO: hogar_id no quedó en null';
  assert v_activo = true, 'CA4d FALLO: activo no quedó en true';
  assert v_nombre = 'Yogur Griego Frutilla Editado T05', 'CA4e FALLO: nombre no fue trimmeado/actualizado';
  assert v_unidad = 'g', 'CA4f FALLO: unidad_base no fue actualizada';
  assert v_dias = 14, 'CA4g FALLO: vida_util_dias_ref no fue actualizada';

  -- Comprobar que la despensa_item sigue apuntando a este mismo alimento
  select alimento_id into v_desp_alim_id
  from public.despensa_item
  where id = 'd0000000-0000-0000-0000-000000000020';

  assert exists (select 1 from public.alimento where id = v_desp_alim_id and nombre = 'Yogur Griego Frutilla Editado T05'),
    'CA4h FALLO: despensa_item no apunta al alimento promovido al catálogo';
end;
$$;

-- Ids para CA5 (superusuario; is_local = true, duran hasta el fin de la transacción)
do $$
begin
  perform set_config('t05.local_id', (select id::text from public.alimento where nombre = 'Alimento Privado Local T05'), true);
  perform set_config('t05.rechazado_id', (select id::text from public.alimento where nombre = 'Alimento Previamente Rechazado T05'), true);
  perform set_config('t05.aprobado_id', (select id::text from public.alimento where nombre = 'Yogur Griego Frutilla Editado T05'), true);
  perform set_config('t05.cat_id', (select categoria_id::text from public.alimento where nombre = 'Yogur Griego Frutilla Editado T05'), true);
end;
$$;

-- ============================================================
-- CA5: Aprobar o rechazar fila que no está PROPUESTO o no existe lanza P0001
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

-- 5a: Aprobar id inexistente lanza P0001
do $$
begin
  perform public.admin_aprobar_propuesto(999999999, 'Fantasma', 1, 'un', true, null);
  assert false, 'CA5a FALLO: se permitió aprobar id inexistente';
exception
  when raise_exception then
    assert sqlerrm = 'El producto ya no está pendiente de revisión.', 'CA5a Mensaje inesperado: ' || sqlerrm;
end;
$$;

-- 5b: Rechazar id inexistente lanza P0001
do $$
begin
  perform public.admin_rechazar_propuesto(999999999);
  assert false, 'CA5b FALLO: se permitió rechazar id inexistente';
exception
  when raise_exception then
    assert sqlerrm = 'El producto ya no está pendiente de revisión.', 'CA5b Mensaje inesperado: ' || sqlerrm;
end;
$$;

-- 5c/5d/5e (fix orquestador): como authenticated, RLS oculta las filas con hogar_id,
-- así que los ids se guardan antes como superusuario en variables de la transacción.
-- Antes el bloque buscaba el id como authenticated, quedaba null y se saltaba (test vacío).
do $$
begin
  assert current_setting('t05.local_id', true) is not null, 'CA5 PREP FALLO: no se guardó el id LOCAL';
end;
$$;

-- 5c: Aprobar fila en estado LOCAL lanza P0001
do $$
begin
  perform public.admin_aprobar_propuesto(current_setting('t05.local_id')::bigint, 'Hack Local', current_setting('t05.cat_id')::bigint, 'un', true, null);
  assert false, 'CA5c FALLO: se permitió aprobar fila en estado LOCAL';
exception
  when raise_exception then
    assert sqlerrm = 'El producto ya no está pendiente de revisión.', 'CA5c Mensaje inesperado: ' || sqlerrm;
end;
$$;

-- 5d: Rechazar fila ya RECHAZADO lanza P0001
do $$
begin
  perform public.admin_rechazar_propuesto(current_setting('t05.rechazado_id')::bigint);
  assert false, 'CA5d FALLO: se permitió rechazar una fila ya RECHAZADO';
exception
  when raise_exception then
    assert sqlerrm = 'El producto ya no está pendiente de revisión.', 'CA5d Mensaje inesperado: ' || sqlerrm;
end;
$$;

-- 5e: Aprobar fila ya APROBADO (la promovida en CA4) lanza P0001
do $$
begin
  perform public.admin_aprobar_propuesto(current_setting('t05.aprobado_id')::bigint, 'Hack Aprobado', current_setting('t05.cat_id')::bigint, 'un', true, null);
  assert false, 'CA5e FALLO: se permitió aprobar una fila ya APROBADO';
exception
  when raise_exception then
    assert sqlerrm = 'El producto ya no está pendiente de revisión.', 'CA5e Mensaje inesperado: ' || sqlerrm;
end;
$$;

reset role;

-- 5f: Nada cambió (superusuario)
do $$
begin
  assert (select estado from public.alimento where id = current_setting('t05.local_id')::bigint) = 'LOCAL',
    'CA5f FALLO: la fila LOCAL cambió de estado';
  assert (select estado from public.alimento where id = current_setting('t05.rechazado_id')::bigint) = 'RECHAZADO',
    'CA5f FALLO: la fila RECHAZADO cambió de estado';
  assert (select nombre from public.alimento where id = current_setting('t05.aprobado_id')::bigint) = 'Yogur Griego Frutilla Editado T05',
    'CA5f FALLO: la fila APROBADO fue modificada';
end;
$$;

-- ============================================================
-- CA6: Nombre duplicado al aprobar lanza 23505 y la fila sigue PROPUESTO
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_dup_id bigint;
  v_cat_id bigint;
begin
  select id, categoria_id into v_dup_id, v_cat_id
  from public.admin_listar_propuestos()
  where nombre = 'Pan Molde Propuesto T05';

  begin
    perform public.admin_aprobar_propuesto(
      v_dup_id,
      'Pan Existente En Catalogo T05', -- Nombre idéntico al ya existente en el catálogo
      v_cat_id,
      'un',
      true,
      null
    );
    assert false, 'CA6a FALLO: se permitió aprobar generando un nombre duplicado en catálogo';
  exception
    when unique_violation then
      null; -- Esperado: 23505
  end;
end;
$$;

-- Verificación de que la fila sigue en PROPUESTO (como superusuario)
reset role;

do $$
declare
  v_estado text;
begin
  select estado into v_estado from public.alimento where nombre = 'Pan Molde Propuesto T05';
  assert v_estado = 'PROPUESTO', 'CA6b FALLO: la fila duplicada cambió de estado tras el fallo (estado: ' || coalesce(v_estado, 'null') || ')';
end;
$$;

-- ============================================================
-- CA7: Validaciones de negocio al aprobar: categoría inactiva, nombre y duración
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

-- 7a: Categoría inactiva lanza P0001
do $$
declare
  v_prop_id    bigint;
  v_inactiva_id bigint;
begin
  select id into v_prop_id from public.admin_listar_propuestos() limit 1;
  select id into v_inactiva_id from public.categoria where nombre = 'Cat Inactiva T05';

  begin
    perform public.admin_aprobar_propuesto(v_prop_id, 'Nombre Valido', v_inactiva_id, 'un', true, null);
    assert false, 'CA7a FALLO: se permitió aprobar con categoría inactiva';
  exception
    when raise_exception then
      assert sqlerrm = 'La categoría no existe o está inactiva.', 'CA7a Mensaje inesperado: ' || sqlerrm;
  end;
end;
$$;

-- 7b: Nombre inválido (< 2 caracteres o > 80 caracteres) lanza P0001
do $$
declare
  v_prop_id bigint;
  v_cat_id  bigint;
begin
  select id, categoria_id into v_prop_id, v_cat_id from public.admin_listar_propuestos() limit 1;

  -- 1 carácter
  begin
    perform public.admin_aprobar_propuesto(v_prop_id, 'A', v_cat_id, 'un', true, null);
    assert false, 'CA7b1 FALLO: se permitió aprobar con nombre de 1 carácter';
  exception
    when raise_exception then
      assert sqlerrm = 'El nombre debe tener entre 2 y 80 caracteres.', 'CA7b1 Mensaje inesperado: ' || sqlerrm;
  end;

  -- Solo espacios
  begin
    perform public.admin_aprobar_propuesto(v_prop_id, '     ', v_cat_id, 'un', true, null);
    assert false, 'CA7b2 FALLO: se permitió aprobar con nombre de solo espacios';
  exception
    when raise_exception then
      assert sqlerrm = 'El nombre debe tener entre 2 y 80 caracteres.', 'CA7b2 Mensaje inesperado: ' || sqlerrm;
  end;

  -- 81 caracteres
  begin
    perform public.admin_aprobar_propuesto(v_prop_id, repeat('x', 81), v_cat_id, 'un', true, null);
    assert false, 'CA7b3 FALLO: se permitió aprobar con nombre de 81 caracteres';
  exception
    when raise_exception then
      assert sqlerrm = 'El nombre debe tener entre 2 y 80 caracteres.', 'CA7b3 Mensaje inesperado: ' || sqlerrm;
  end;
end;
$$;

-- 7c: Duración fuera de rango lanza P0001
do $$
declare
  v_prop_id bigint;
  v_cat_id  bigint;
begin
  select id, categoria_id into v_prop_id, v_cat_id from public.admin_listar_propuestos() limit 1;

  -- 0 días
  begin
    perform public.admin_aprobar_propuesto(v_prop_id, 'Nombre Valido', v_cat_id, 'un', true, 0);
    assert false, 'CA7c1 FALLO: se permitió aprobar con duración = 0';
  exception
    when raise_exception then
      assert sqlerrm = 'La duración debe estar entre 1 y 3650 días.', 'CA7c1 Mensaje inesperado: ' || sqlerrm;
  end;

  -- 3651 días
  begin
    perform public.admin_aprobar_propuesto(v_prop_id, 'Nombre Valido', v_cat_id, 'un', true, 3651);
    assert false, 'CA7c2 FALLO: se permitió aprobar con duración = 3651';
  exception
    when raise_exception then
      assert sqlerrm = 'La duración debe estar entre 1 y 3650 días.', 'CA7c2 Mensaje inesperado: ' || sqlerrm;
  end;
end;
$$;

reset role;

-- ============================================================
-- CA8: Rechazar deja estado = 'RECHAZADO' con el mismo hogar_id
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_prop_id bigint;
begin
  select id into v_prop_id
  from public.admin_listar_propuestos()
  where nombre = 'Snack Raro Propuesto T05';

  perform public.admin_rechazar_propuesto(v_prop_id);
end;
$$;

-- Verificación de rechazo como superusuario
reset role;

do $$
declare
  v_estado text;
  v_hogar  uuid;
begin
  select estado, hogar_id into v_estado, v_hogar
  from public.alimento
  where nombre = 'Snack Raro Propuesto T05';

  assert v_estado = 'RECHAZADO', 'CA8a FALLO: estado no quedó en RECHAZADO (obtenido: ' || coalesce(v_estado, 'null') || ')';
  assert v_hogar = 'd0000000-0000-0000-0000-000000000010', 'CA8b FALLO: hogar_id cambió o se perdió al rechazar';
end;
$$;

-- ============================================================
-- Limpieza total: el rollback deshace todas las tablas y usuarios creados
-- ============================================================
rollback;
