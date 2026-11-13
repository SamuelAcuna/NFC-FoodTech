-- Test transaccional para T03: mantenedor de categorías, árbol y duraciones referenciales.
-- NO ejecutar contra la base real. Lo corre Claude con OK de Samuel.
-- Cubre CA2 a CA7 y CA9 de la spec.

begin;

-- ============================================================
-- Preparación: usuarios de prueba con roles ADMIN, EDITOR_CATALOGO, SOPORTE y sin rol.
-- El trigger handle_new_user crea el perfil con estado_cuenta = 'ACTIVA'.
-- ============================================================
do $$
declare
  v_admin_id      uuid := 'a0000000-0000-0000-0000-000000000001';
  v_editor_id     uuid := 'a0000000-0000-0000-0000-000000000002';
  v_sinrol_id     uuid := 'a0000000-0000-0000-0000-000000000003';
  v_soporte_id    uuid := 'a0000000-0000-0000-0000-000000000006';
  v_rol_admin     bigint;
  v_rol_editor    bigint;
  v_rol_soporte   bigint;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud, instance_id)
  values
    (v_admin_id,   'admin-t03@local',   crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_editor_id,  'editor-t03@local',  crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_soporte_id, 'soporte-t03@local', crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
    (v_sinrol_id,  'sinrol-t03@local',  crypt('Test1234!', gen_salt('bf')), now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  on conflict (id) do nothing;

  select id into v_rol_admin   from public.rol where codigo = 'ADMIN';
  select id into v_rol_editor  from public.rol where codigo = 'EDITOR_CATALOGO';
  select id into v_rol_soporte from public.rol where codigo = 'SOPORTE';

  insert into public.perfil_rol (perfil_id, rol_id) values
    (v_admin_id,   v_rol_admin),
    (v_editor_id,  v_rol_editor),
    (v_soporte_id, v_rol_soporte)
  on conflict (perfil_id, rol_id) do nothing;
end;
$$;

-- ============================================================
-- CA2: Con aal2 y CATEGORIAS_GESTIONAR (EDITOR_CATALOGO o ADMIN),
--      se puede crear raíz, crear subcategoría, editar, activar/desactivar y eliminar.
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_raiz_id bigint;
  v_sub_id  bigint;
  v_updated int;
  v_deleted int;
begin
  -- 2a: Crear categoría raíz
  insert into public.categoria (nombre, temp_conservacion)
  values ('Frutas Test T03', 'AMBIENTE')
  returning id into v_raiz_id;

  assert v_raiz_id is not null, 'CA2a FALLO: no se pudo insertar categoría raíz con aal2 y CATEGORIAS_GESTIONAR';

  -- 2b: Crear subcategoría bajo la raíz
  insert into public.categoria (nombre, parent_id, temp_conservacion)
  values ('Cítricos Test T03', v_raiz_id, 'REFRIGERADO')
  returning id into v_sub_id;

  assert v_sub_id is not null, 'CA2b FALLO: no se pudo insertar subcategoría';

  -- 2c: Editar nombre y conservación
  update public.categoria
  set nombre = 'Cítricos Modificados T03', temp_conservacion = 'AMBIENTE'
  where id = v_sub_id;
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA2c FALLO: no se pudo actualizar la subcategoría';

  -- 2d: Activar / desactivar
  update public.categoria set activa = false where id = v_sub_id;
  get diagnostics v_updated = row_count;

  assert v_updated = 1, 'CA2d FALLO: no se pudo cambiar el estado activa a false';

  -- 2e: Eliminar categoría sin alimentos ni dependientes
  delete from public.categoria where id = v_sub_id;
  get diagnostics v_deleted = row_count;

  assert v_deleted = 1, 'CA2e FALLO: no se pudo eliminar la categoría sin relaciones';

  -- Limpiar la raíz creada para esta prueba
  delete from public.categoria where id = v_raiz_id;
end;
$$;

reset role;

-- ============================================================
-- CA3: RLS - Denegación de escritura para SOPORTE (aal2) y ADMIN (aal1).
-- ============================================================

-- 3a: SOPORTE con aal2 NO puede insertar en categoria
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000006","role":"authenticated","aal":"aal2"}';

do $$
begin
  insert into public.categoria (nombre) values ('Intento Soporte');
  assert false, 'CA3a FALLO: SOPORTE pudo insertar en categoria';
exception
  when insufficient_privilege then
    null; -- Esperado: WITH CHECK falla con 42501
end;
$$;

-- 3b: SOPORTE con aal2 NO puede actualizar categoria (0 filas o 42501)
do $$
declare
  v_updated int;
begin
  update public.categoria set nombre = 'Hack Soporte' where id = 1;
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA3b FALLO: SOPORTE pudo actualizar categoria (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

-- 3c: SOPORTE con aal2 NO puede borrar categoria (0 filas o 42501)
do $$
declare
  v_deleted int;
begin
  delete from public.categoria where id = 1;
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA3c FALLO: SOPORTE pudo borrar categoria (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- 3d: ADMIN con aal1 NO puede insertar en categoria
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';

do $$
begin
  insert into public.categoria (nombre) values ('Intento ADMIN aal1');
  assert false, 'CA3d FALLO: ADMIN con aal1 pudo insertar en categoria';
exception
  when insufficient_privilege then
    null; -- Esperado
end;
$$;

-- 3e: ADMIN con aal1 NO puede actualizar categoria
do $$
declare
  v_updated int;
begin
  update public.categoria set nombre = 'Hack aal1' where id = 1;
  get diagnostics v_updated = row_count;
  assert v_updated = 0, 'CA3e FALLO: ADMIN con aal1 pudo actualizar categoria (' || v_updated || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

-- 3f: ADMIN con aal1 NO puede borrar categoria
do $$
declare
  v_deleted int;
begin
  delete from public.categoria where id = 1;
  get diagnostics v_deleted = row_count;
  assert v_deleted = 0, 'CA3f FALLO: ADMIN con aal1 pudo borrar categoria (' || v_deleted || ' filas)';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

-- 3g: Usuario sin rol no puede ver filas de categoria
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.categoria;
  assert v_count = 0, 'CA3g FALLO: usuario sin rol no debería ver categorias por política admin (vio ' || v_count || ')';
end;
$$;

reset role;

-- ============================================================
-- CA4: Árbol de máximo 2 niveles (trigger admin_categoria_validar_arbol).
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_padre_id bigint;
  v_hijo_id  bigint;
begin
  insert into public.categoria (nombre) values ('Raiz Arbol T04') returning id into v_padre_id;
  insert into public.categoria (nombre, parent_id) values ('Sub Arbol T04', v_padre_id) returning id into v_hijo_id;

  -- 4a: Auto-paternidad (parent_id = id)
  begin
    update public.categoria set parent_id = v_padre_id where id = v_padre_id;
    assert false, 'CA4a FALLO: se permitió que una categoría sea su propio padre';
  exception
    when raise_exception then
      assert sqlerrm = 'Una categoría no puede ser su propio padre.',
        'CA4a Mensaje inesperado: ' || sqlerrm;
  end;

  -- 4b: Tercer nivel (asignar como padre a una subcategoría)
  begin
    insert into public.categoria (nombre, parent_id) values ('Nivel 3 Prohibido', v_hijo_id);
    assert false, 'CA4b FALLO: se permitió insertar un tercer nivel en el árbol';
  exception
    when raise_exception then
      assert sqlerrm = 'Solo se permiten dos niveles: el padre debe ser una categoría raíz.',
        'CA4b Mensaje inesperado: ' || sqlerrm;
  end;

  -- 4c: Asignar padre a una categoría que ya tiene hijas
  begin
    update public.categoria set parent_id = v_hijo_id where id = v_padre_id;
    assert false, 'CA4c FALLO: se permitió asignar padre a una categoría con hijas';
  exception
    when raise_exception then
      -- Podría disparar 'Solo se permiten dos niveles...' o 'No se puede asignar un padre a una categoría que tiene subcategorías.'
      assert sqlerrm in (
        'No se puede asignar un padre a una categoría que tiene subcategorías.',
        'Solo se permiten dos niveles: el padre debe ser una categoría raíz.'
      ), 'CA4c Mensaje inesperado: ' || sqlerrm;
  end;

  -- Probar específicamente 'No se puede asignar un padre a una categoría que tiene subcategorías.'
  -- creando otra raíz libre y tratando de asignarla como padre a v_padre_id:
  declare
    v_otra_raiz bigint;
  begin
    insert into public.categoria (nombre) values ('Otra Raiz T04') returning id into v_otra_raiz;
    begin
      update public.categoria set parent_id = v_otra_raiz where id = v_padre_id;
      assert false, 'CA4d FALLO: se permitió asignar padre a una categoría que tiene hijas';
    exception
      when raise_exception then
        assert sqlerrm = 'No se puede asignar un padre a una categoría que tiene subcategorías.',
          'CA4d Mensaje inesperado: ' || sqlerrm;
    end;
    delete from public.categoria where id = v_otra_raiz;
  end;

  -- Limpieza
  delete from public.categoria where id = v_hijo_id;
  delete from public.categoria where id = v_padre_id;
end;
$$;

reset role;

-- ============================================================
-- CA5: Unicidad (nombre normalizado bajo el mismo padre).
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_raiz1 bigint;
  v_raiz2 bigint;
  v_sub1  bigint;
begin
  insert into public.categoria (nombre) values ('Unicidad Raiz A') returning id into v_raiz1;
  insert into public.categoria (nombre) values ('Unicidad Raiz B') returning id into v_raiz2;

  -- 5a: Mismo nombre exacto en la raíz -> falla 23505
  begin
    insert into public.categoria (nombre) values ('Unicidad Raiz A');
    assert false, 'CA5a FALLO: se permitió duplicar nombre en categoría raíz';
  exception
    when unique_violation then
      null; -- Esperado
  end;

  -- 5b: Mismo nombre con mayúsculas/espacios en la raíz -> falla 23505
  begin
    insert into public.categoria (nombre) values ('   uNicIdAd rAiZ a   ');
    assert false, 'CA5b FALLO: se permitió duplicar nombre con mayúsculas/espacios';
  exception
    when unique_violation then
      null; -- Esperado
  end;

  -- 5c: Subcategoría con mismo nombre bajo padres distintos -> SÍ se permite
  insert into public.categoria (nombre, parent_id) values ('Sub Común', v_raiz1) returning id into v_sub1;
  insert into public.categoria (nombre, parent_id) values ('Sub Común', v_raiz2);

  -- 5d: Subcategoría con mismo nombre bajo el mismo padre -> falla 23505
  begin
    insert into public.categoria (nombre, parent_id) values ('  sub común  ', v_raiz1);
    assert false, 'CA5d FALLO: se permitió duplicar subcategoría bajo el mismo padre';
  exception
    when unique_violation then
      null; -- Esperado
  end;

  -- Limpieza
  delete from public.categoria where parent_id in (v_raiz1, v_raiz2);
  delete from public.categoria where id in (v_raiz1, v_raiz2);
end;
$$;

reset role;

-- ============================================================
-- CA6: FK - Eliminar categoría con alimentos o subcategorías falla.
-- ============================================================
-- Preparación como superusuario: crear alimento referenciando una categoría
do $$
declare
  v_cat_con_alimento bigint;
  v_cat_con_hija     bigint;
  v_cat_hija         bigint;
begin
  insert into public.categoria (nombre) values ('Cat FK Alimento T06') returning id into v_cat_con_alimento;
  insert into public.categoria (nombre) values ('Cat FK Padre T06') returning id into v_cat_con_hija;
  insert into public.categoria (nombre, parent_id) values ('Cat FK Hija T06', v_cat_con_hija) returning id into v_cat_hija;

  insert into public.alimento (nombre, categoria_id, unidad_base)
  values ('Alimento Test FK', v_cat_con_alimento, 'un');
end;
$$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

-- 6a: Intentar eliminar categoría que tiene alimentos -> falla por FK (23503)
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where nombre = 'Cat FK Alimento T06';

  begin
    delete from public.categoria where id = v_cat_id;
    assert false, 'CA6a FALLO: se permitió borrar una categoría con alimentos';
  exception
    when foreign_key_violation then
      null; -- Esperado (23503)
  end;

  -- Verificar que la categoría sigue existiendo
  assert exists (select 1 from public.categoria where id = v_cat_id),
    'CA6a2 FALLO: la categoría con alimentos fue eliminada a pesar del error';
end;
$$;

-- 6b: Intentar eliminar categoría que tiene subcategorías -> falla por FK (23503)
do $$
declare
  v_cat_id bigint;
begin
  select id into v_cat_id from public.categoria where nombre = 'Cat FK Padre T06';

  begin
    delete from public.categoria where id = v_cat_id;
    assert false, 'CA6b FALLO: se permitió borrar una categoría con subcategorías';
  exception
    when foreign_key_violation then
      null; -- Esperado (23503)
  end;

  assert exists (select 1 from public.categoria where id = v_cat_id),
    'CA6b2 FALLO: la categoría padre fue eliminada a pesar de tener hijas';
end;
$$;

reset role;

-- Limpieza de alimentos creados para la prueba
do $$
begin
  delete from public.alimento where nombre = 'Alimento Test FK';
  delete from public.categoria where nombre = 'Cat FK Hija T06';
  delete from public.categoria where nombre = 'Cat FK Padre T06';
  delete from public.categoria where nombre = 'Cat FK Alimento T06';
end;
$$;

-- ============================================================
-- CA7: Restricciones CHECK en rangos de días (1 a 3650).
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
declare
  v_cat_id bigint;
begin
  insert into public.categoria (nombre) values ('Check Dias T07') returning id into v_cat_id;

  -- 7a: Valores válidos (1, 3650, null)
  update public.categoria
  set vida_util_dias_ref = 1,
      vida_util_refrigerado_dias = 3650,
      vida_util_congelado_dias = null
  where id = v_cat_id;

  -- 7b: Despensa con 0 -> falla 23514
  begin
    update public.categoria set vida_util_dias_ref = 0 where id = v_cat_id;
    assert false, 'CA7b FALLO: se permitió vida_util_dias_ref = 0';
  exception
    when check_violation then
      null;
  end;

  -- 7c: Despensa con 3651 -> falla 23514
  begin
    update public.categoria set vida_util_dias_ref = 3651 where id = v_cat_id;
    assert false, 'CA7c FALLO: se permitió vida_util_dias_ref = 3651';
  exception
    when check_violation then
      null;
  end;

  -- 7d: Refrigerado con -5 -> falla 23514
  begin
    update public.categoria set vida_util_refrigerado_dias = -5 where id = v_cat_id;
    assert false, 'CA7d FALLO: se permitió refrigerado negativo';
  exception
    when check_violation then
      null;
  end;

  -- 7e: Congelado con 4000 -> falla 23514
  begin
    update public.categoria set vida_util_congelado_dias = 4000 where id = v_cat_id;
    assert false, 'CA7e FALLO: se permitió congelado > 3650';
  exception
    when check_violation then
      null;
  end;

  delete from public.categoria where id = v_cat_id;
end;
$$;

reset role;

-- ============================================================
-- CA9: La función trigger NO es ejecutable por anon ni por authenticated.
-- ============================================================
-- 9a: anon no puede ejecutar la función
set local role anon;

do $$
begin
  perform public.admin_categoria_validar_arbol();
  assert false, 'CA9a FALLO: anon pudo ejecutar admin_categoria_validar_arbol';
exception
  when insufficient_privilege then
    null; -- Esperado
end;
$$;

reset role;

-- 9b: authenticated no puede ejecutar la función directamente
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';

do $$
begin
  perform public.admin_categoria_validar_arbol();
  assert false, 'CA9b FALLO: authenticated pudo ejecutar admin_categoria_validar_arbol';
exception
  when insufficient_privilege then
    null; -- Esperado
end;
$$;

reset role;

-- ============================================================
-- Limpieza total: el rollback deshace usuarios, categorías y modificaciones.
-- ============================================================
rollback;
