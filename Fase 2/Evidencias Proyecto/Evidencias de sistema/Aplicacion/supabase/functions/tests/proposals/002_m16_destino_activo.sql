BEGIN;

-- No crear una funcion nueva con permisos por defecto si falta la original.
DO $comprobar$
BEGIN
    IF pg_catalog.to_regprocedure('public.m16_gestionar_miembro(uuid,text,uuid)') IS NULL THEN
        RAISE EXCEPTION 'M16 no encontrada; revisar la firma antes de aplicar la propuesta';
    END IF;
END;
$comprobar$;

-- La misma firma con CREATE OR REPLACE conserva propietario, OID y ACL.
-- No se ejecutan DROP FUNCTION, ALTER OWNER, GRANT ni REVOKE.
CREATE OR REPLACE FUNCTION public.m16_gestionar_miembro(p_hogar_id uuid, p_accion text, p_perfil_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_usuario uuid;
    v_creador uuid;
    v_rol_actual text;
    v_rol_destino text;
    v_cantidad_admin integer;
BEGIN
    v_usuario := auth.uid();

    IF v_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes iniciar sesión';
    END IF;

    -- Solo se consulta el perfil propio identificado por Auth.
    -- Perfil antes de hogar, como M08. NOWAIT evita esperar por un perfil
    -- retenido por otra operacion, incluso si el caller ya tiene bloqueos.
    BEGIN
        PERFORM p.id
        FROM public.perfil p
        WHERE p.id = v_usuario
          AND p.estado_cuenta = 'ACTIVA'
        FOR SHARE NOWAIT;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'M16_SOLICITANTE_NO_ACTIVO: el solicitante debe tener una cuenta ACTIVA';
        END IF;
    EXCEPTION
        WHEN lock_not_available THEN
            RAISE EXCEPTION USING
                ERRCODE = '55P03',
                MESSAGE = 'El perfil del solicitante esta siendo gestionado por otra operacion. Reintenta cuando termine.';
    END;
    -- Impide desactivar al solicitante entre la validacion y las escrituras.
    -- Se aplica tambien a ABANDONAR, sin excepciones por rol o accion.

    -- Serializa las operaciones M16 del mismo hogar.
    SELECT h.creado_por
    INTO v_creador
    FROM public.hogar h
    WHERE h.id = p_hogar_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hogar no encontrado';
    END IF;

    -- El solicitante debe pertenecer al hogar.
    SELECT hm.rol
    INTO v_rol_actual
    FROM public.hogar_miembro hm
    WHERE hm.hogar_id = p_hogar_id
      AND hm.perfil_id = v_usuario
      AND hm.estado = 'ACTIVO';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No perteneces a este hogar';
    END IF;

    -- Contar administradores activos.
    SELECT count(*)
    INTO v_cantidad_admin
    FROM public.hogar_miembro hm
    WHERE hm.hogar_id = p_hogar_id
      AND hm.estado = 'ACTIVO'
      AND hm.rol = 'ADMIN';

    -- ==========================================
    -- ABANDONAR HOGAR
    -- ==========================================
    IF p_accion = 'ABANDONAR' THEN

        IF v_creador = v_usuario THEN
            RAISE EXCEPTION
                'Debes transferir la administración antes de abandonar';
        END IF;

        IF v_rol_actual = 'ADMIN'
           AND v_cantidad_admin <= 1 THEN
            RAISE EXCEPTION
                'El hogar debe conservar un administrador';
        END IF;

        UPDATE public.hogar_miembro
        SET estado = 'REMOVIDO'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = v_usuario
          AND estado = 'ACTIVO';

        RETURN;
    END IF;

    -- Las demás acciones requieren rol ADMIN.
    IF v_rol_actual <> 'ADMIN' THEN
        RAISE EXCEPTION
            'Solo un administrador puede realizar esta acción';
    END IF;

    IF p_perfil_id IS NULL THEN
        RAISE EXCEPTION
            'Debes seleccionar un integrante';
    END IF;

    IF p_perfil_id = v_usuario THEN
        RAISE EXCEPTION
            'Esta acción no se puede realizar sobre tu propia cuenta';
    END IF;

    SELECT hm.rol
    INTO v_rol_destino
    FROM public.hogar_miembro hm
    WHERE hm.hogar_id = p_hogar_id
      AND hm.perfil_id = p_perfil_id
      AND hm.estado = 'ACTIVO';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'El integrante no está activo en este hogar';
    END IF;

    -- ==========================================
    -- PROMOVER A ADMIN
    -- ==========================================
    IF p_accion = ANY (ARRAY['PROMOVER', 'TRANSFERIR']) THEN
        -- Solicitante ADMIN y destinatario ACTIVO del hogar ya verificados.
        -- M08 bloquea perfil antes de hogar: no esperar por ese perfil aqui.
        BEGIN
            PERFORM p.id
            FROM public.perfil p
            WHERE p.id = p_perfil_id
              AND p.estado_cuenta = 'ACTIVA'
            FOR SHARE NOWAIT;

            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'M16_DESTINO_NO_ACTIVO: el destinatario debe tener una cuenta ACTIVA';
            END IF;
        EXCEPTION
            WHEN lock_not_available THEN
                RAISE EXCEPTION USING
                    ERRCODE = '55P03',
                    MESSAGE = 'El perfil del destinatario esta siendo gestionado por otra operacion. Reintenta cuando termine.';
        END;
        -- Si se obtuvo, FOR SHARE dura hasta terminar la transaccion exterior.
    END IF;

    IF p_accion = 'PROMOVER' THEN

        UPDATE public.hogar_miembro
        SET rol = 'ADMIN'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = p_perfil_id
          AND estado = 'ACTIVO';

        RETURN;
    END IF;

    -- ==========================================
    -- DEGRADAR A MIEMBRO
    -- ==========================================
    IF p_accion = 'DEGRADAR' THEN

        IF p_perfil_id = v_creador THEN
            RAISE EXCEPTION
                'Primero debes transferir la administración del creador';
        END IF;

        IF v_rol_destino = 'ADMIN'
           AND v_cantidad_admin <= 1 THEN
            RAISE EXCEPTION
                'No puedes quitar al último administrador';
        END IF;

        UPDATE public.hogar_miembro
        SET rol = 'MIEMBRO'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = p_perfil_id
          AND estado = 'ACTIVO';

        RETURN;
    END IF;

    -- ==========================================
    -- REMOVER INTEGRANTE
    -- ==========================================
    IF p_accion = 'REMOVER' THEN

        IF p_perfil_id = v_creador THEN
            RAISE EXCEPTION
                'No puedes remover al creador sin transferir la administración';
        END IF;

        IF v_rol_destino = 'ADMIN'
           AND v_cantidad_admin <= 1 THEN
            RAISE EXCEPTION
                'No puedes remover al último administrador';
        END IF;

        UPDATE public.hogar_miembro
        SET estado = 'REMOVIDO'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = p_perfil_id
          AND estado = 'ACTIVO';

        RETURN;
    END IF;

    -- ==========================================
    -- TRANSFERIR ADMINISTRACIÓN
    -- ==========================================
    IF p_accion = 'TRANSFERIR' THEN

        -- Primero activar como administrador al destino.
        UPDATE public.hogar_miembro
        SET rol = 'ADMIN'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = p_perfil_id
          AND estado = 'ACTIVO';

        -- El administrador actual pasa a MIEMBRO.
        UPDATE public.hogar_miembro
        SET rol = 'MIEMBRO'
        WHERE hogar_id = p_hogar_id
          AND perfil_id = v_usuario
          AND estado = 'ACTIVO';

        -- Si el solicitante era el creador,
        -- transferir también la titularidad técnica.
        IF v_creador = v_usuario THEN
            UPDATE public.hogar
            SET creado_por = p_perfil_id,
                updated_at = now()
            WHERE id = p_hogar_id;
        END IF;

        RETURN;
    END IF;

    RAISE EXCEPTION 'Acción no válida';
END;
$function$;

COMMIT;

/*
VALIDACION PROPUESTA, NO EJECUTADA

Aplicar solamente en una copia aislada con cuentas y hogares sinteticos.
El cuerpo explicito usa la definicion M16 facilitada como base: comparar contra
la version desplegada antes de autorizar. No se ha consultado el backend.
Las pruebas siguientes son instrucciones comentadas; aplicar la propuesta no
las ejecuta. No crean ni eliminan usuarios Auth. Terminar siempre ROLLBACK.

1. PRIVILEGIOS

Ejecutar antes y despues de aplicar: OID, propietario y ACL deben ser identicos.
Revisar tambien permisos heredados; no corregirlos dentro de esta propuesta.

SELECT p.oid, pg_catalog.pg_get_userbyid(p.proowner) AS propietario,
       p.proacl, p.prosecdef, p.proconfig,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_catalog.pg_get_function_result(p.oid) AS retorno,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.m16_gestionar_miembro(uuid,text,uuid)'::regprocedure;

2. REGRESION CON ASERCIONES

Fixture restaurada: hogar H, A creador ADMIN, B MIEMBRO, C MIEMBRO,
todos con membresia ACTIVO y perfil ACTIVA. D MIEMBRO ACTIVO de H con perfil
DESACTIVADA; repetir con otro D SUSPENDIDA y BANEADA. La fixture se prepara
expresamente en staging: no se asume que M08 conserve membresias activas.
No usar cuentas reales. Respetar las restricciones reales al crear la fixture.
Configurar una vez en la conexion, sustituyendo los marcadores:

SELECT set_config('m16_test.hogar', '<UUID_H>', false);
SELECT set_config('m16_test.a', '<UUID_A>', false);
SELECT set_config('m16_test.b', '<UUID_B>', false);
SELECT set_config('m16_test.c', '<UUID_C>', false);
SELECT set_config('m16_test.d', '<UUID_D>', false);

BEGIN;
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.a'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.a'), 'role', 'authenticated')::text, true);

DO $regresion$
DECLARE
    h uuid := current_setting('m16_test.hogar')::uuid;
    a uuid := current_setting('m16_test.a')::uuid;
    b uuid := current_setting('m16_test.b')::uuid;
    c uuid := current_setting('m16_test.c')::uuid;
    d uuid := current_setting('m16_test.d')::uuid;
    accion text;
    mensaje text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.hogar WHERE id = h AND creado_por = a)
       OR NOT EXISTS (SELECT 1 FROM public.hogar_miembro
           WHERE hogar_id = h AND perfil_id = a AND rol = 'ADMIN' AND estado = 'ACTIVO')
       OR (SELECT count(*) FROM public.hogar_miembro
           WHERE hogar_id = h AND perfil_id IN (b,c,d) AND rol = 'MIEMBRO' AND estado = 'ACTIVO') <> 3
       OR (SELECT count(*) FROM public.perfil WHERE id IN (a,b,c) AND estado_cuenta = 'ACTIVA') <> 3
       OR NOT EXISTS (SELECT 1 FROM public.perfil WHERE id = d
           AND estado_cuenta IN ('DESACTIVADA','SUSPENDIDA','BANEADA')) THEN
        RAISE EXCEPTION 'Fixture incorrecta';
    END IF;

    FOREACH accion IN ARRAY ARRAY['PROMOVER', 'TRANSFERIR'] LOOP
        BEGIN
            PERFORM public.m16_gestionar_miembro(h, accion, d);
            RAISE EXCEPTION USING ERRCODE = 'P9000', MESSAGE = 'Se acepto un destinatario restringido';
        EXCEPTION WHEN raise_exception THEN
            GET STACKED DIAGNOSTICS mensaje = MESSAGE_TEXT;
            IF mensaje <> 'M16_DESTINO_NO_ACTIVO: el destinatario debe tener una cuenta ACTIVA' THEN RAISE; END IF;
        END;
    END LOOP;

    PERFORM public.m16_gestionar_miembro(h, 'PROMOVER', b);
    IF NOT EXISTS (SELECT 1 FROM public.hogar_miembro
        WHERE hogar_id = h AND perfil_id = b AND rol = 'ADMIN' AND estado = 'ACTIVO') THEN
        RAISE EXCEPTION 'PROMOVER no conservo membresia activa';
    END IF;

    PERFORM public.m16_gestionar_miembro(h, 'DEGRADAR', b);
    IF NOT EXISTS (SELECT 1 FROM public.hogar_miembro
        WHERE hogar_id = h AND perfil_id = b AND rol = 'MIEMBRO' AND estado = 'ACTIVO') THEN
        RAISE EXCEPTION 'DEGRADAR no cambio rol o altero estado';
    END IF;

    PERFORM public.m16_gestionar_miembro(h, 'REMOVER', c);
    IF NOT EXISTS (SELECT 1 FROM public.hogar_miembro
        WHERE hogar_id = h AND perfil_id = c AND estado = 'REMOVIDO') THEN
        RAISE EXCEPTION 'REMOVER no conservo membresia historica';
    END IF;

    PERFORM public.m16_gestionar_miembro(h, 'TRANSFERIR', b);
    IF NOT EXISTS (SELECT 1 FROM public.hogar WHERE id = h AND creado_por = b)
       OR NOT EXISTS (SELECT 1 FROM public.hogar_miembro
           WHERE hogar_id = h AND perfil_id = a AND rol = 'MIEMBRO' AND estado = 'ACTIVO')
       OR NOT EXISTS (SELECT 1 FROM public.hogar_miembro
           WHERE hogar_id = h AND perfil_id = b AND rol = 'ADMIN' AND estado = 'ACTIVO') THEN
        RAISE EXCEPTION 'TRANSFERIR no conservo roles o titularidad';
    END IF;

    PERFORM public.m16_gestionar_miembro(h, 'ABANDONAR', NULL);
    IF NOT EXISTS (SELECT 1 FROM public.hogar_miembro
        WHERE hogar_id = h AND perfil_id = a AND estado = 'REMOVIDO') THEN
        RAISE EXCEPTION 'ABANDONAR no conservo membresia historica';
    END IF;
END;
$regresion$;
ROLLBACK;

Casos negativos adicionales, cada uno con fixture restaurada y ROLLBACK:
- Sin sesion, solicitante sin membresia ACTIVO, destino propio, NULL o no ACTIVO:
  conservar los rechazos anteriores de M16.
- C/MIEMBRO intentando PROMOVER o TRANSFERIR hacia D: rechazo por rol ADMIN,
  nunca M16_DESTINO_NO_ACTIVO. Repetir con destino ajeno e inexistente.
  Esto verifica que no se inspeccionen perfiles antes de autorizar al solicitante.
- B/ADMIN distinto de A intentando DEGRADAR o REMOVER al creador A: rechazo.
- A/creador intentando ABANDONAR: exige transferencia y no muta membresia.
- Fixture excepcional separada: creador C/MIEMBRO y unico ADMIN A, ACTIVO ambos.
  ABANDONAR de A debe rechazar 'El hogar debe conservar un administrador'.
  Permite ejercitar esa guardia sin que se dispare primero la del creador.
- Transferencia por B/ADMIN no creador hacia C: A sigue como creado_por,
  B pasa a MIEMBRO y C a ADMIN. No transferir la titularidad tecnica de A.
- PROMOVER de un destinatario ya ADMIN/ACTIVA conserva ADMIN y otros roles.
- Accion desconocida: rechazo sin cambios.
- Ninguna de las cinco acciones debe modificar perfil.estado_cuenta.

2A. SOLICITANTES RESTRINGIDOS: LAS CINCO ACCIONES

En una fixture separada mantener A ADMIN/ACTIVA y creador de H, B MIEMBRO/ACTIVA,
y D ADMIN con membresia ACTIVO en H pero perfil DESACTIVADA. Repetir con D
SUSPENDIDA y BANEADA. Se conserva deliberadamente sesion y membresia activas:
la prueba no depende de que M08 quite o cambie la membresia.
Configurar m16_test.hogar/b/d como antes. Cada ejecucion termina ROLLBACK.

BEGIN;
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.d'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.d'), 'role', 'authenticated')::text, true);

DO $solicitante_restringido$
DECLARE
    h uuid := current_setting('m16_test.hogar')::uuid;
    b uuid := current_setting('m16_test.b')::uuid;
    d uuid := current_setting('m16_test.d')::uuid;
    accion text;
    mensaje text;
    miembros_antes jsonb;
    hogar_antes jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.hogar_miembro
        WHERE hogar_id = h AND perfil_id = d AND rol = 'ADMIN' AND estado = 'ACTIVO')
       OR NOT EXISTS (SELECT 1 FROM public.perfil WHERE id = d
        AND estado_cuenta IN ('DESACTIVADA','SUSPENDIDA','BANEADA')) THEN
        RAISE EXCEPTION 'Fixture de solicitante restringido incorrecta';
    END IF;
    SELECT jsonb_agg(to_jsonb(hm) ORDER BY hm.perfil_id) INTO miembros_antes
    FROM public.hogar_miembro hm WHERE hm.hogar_id = h;
    SELECT to_jsonb(hogar) INTO hogar_antes FROM public.hogar hogar WHERE hogar.id = h;

    FOREACH accion IN ARRAY ARRAY['PROMOVER','TRANSFERIR','ABANDONAR','REMOVER','DEGRADAR'] LOOP
        BEGIN
            PERFORM public.m16_gestionar_miembro(h, accion,
                CASE WHEN accion = 'ABANDONAR' THEN NULL::uuid ELSE b END);
            RAISE EXCEPTION USING ERRCODE = 'P9000', MESSAGE = 'Se acepto un solicitante restringido';
        EXCEPTION WHEN raise_exception THEN
            GET STACKED DIAGNOSTICS mensaje = MESSAGE_TEXT;
            IF mensaje <> 'M16_SOLICITANTE_NO_ACTIVO: el solicitante debe tener una cuenta ACTIVA' THEN RAISE; END IF;
        END;
    END LOOP;

    IF miembros_antes IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(hm) ORDER BY hm.perfil_id)
        FROM public.hogar_miembro hm WHERE hm.hogar_id = h)
       OR hogar_antes IS DISTINCT FROM (SELECT to_jsonb(hogar) FROM public.hogar hogar WHERE hogar.id = h) THEN
        RAISE EXCEPTION 'Un rechazo de solicitante restringido modifico el hogar o sus miembros';
    END IF;
END;
$solicitante_restringido$;
ROLLBACK;

El rechazo de cuenta no ACTIVA usa P0001 y M16_SOLICITANTE_NO_ACTIVO.
Los conflictos de bloqueo usan 55P03 y un mensaje de operacion concurrente.
No interpretar 55P03 como cuenta no ACTIVA. Repetir tambien sin perfil propio:
el solicitante debe ser rechazado sin acceder a hogares o perfiles ajenos.

3. CONCURRENCIA: M08 RETIENE PERFIL Y M16 RETIENE HOGAR

Dos conexiones persistentes a la misma copia aislada, READ COMMITTED.
No usar pestanas que compartan una sola transaccion del SQL Editor.
Fixture: A creador ADMIN/ACTIVA y B ADMIN/ACTIVA, ambos ACTIVO en H.
Configurar m16_test.hogar/a/b en AMBAS conexiones con sus UUID de staging.
En cada sesion establecer claims consistentes como en la prueba anterior:
request.jwt.claim.sub, request.jwt.claim.role y request.jwt.claims.
Sesion 1 usa B; sesion 2 usa A. Usar statement_timeout 10s como limite.

Sesion 1/B (prefijo de bloqueos de M08, sin modificar su funcion):

BEGIN;
SET LOCAL statement_timeout = '10s';
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.b'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.b'), 'role', 'authenticated')::text, true);
SELECT id FROM public.perfil WHERE id = current_setting('m16_test.b')::uuid FOR UPDATE;
-- Mantener abierta.

Sesion 2/A:

BEGIN;
SET LOCAL statement_timeout = '10s';
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.a'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.a'), 'role', 'authenticated')::text, true);
SELECT id FROM public.hogar WHERE id = current_setting('m16_test.hogar')::uuid FOR UPDATE;
-- Mantener abierta y volver a sesion 1.

Sesion 1:

SELECT id FROM public.hogar WHERE id = current_setting('m16_test.hogar')::uuid FOR UPDATE;
-- Debe esperar: es la segunda arista del orden de M08.

Sesion 2, mientras sesion 1 espera:

SAVEPOINT intento_m16;
SELECT public.m16_gestionar_miembro(
  current_setting('m16_test.hogar')::uuid, 'TRANSFERIR', current_setting('m16_test.b')::uuid);
-- Debe fallar inmediatamente con 55P03, no 40P01, 57014 ni exito.
ROLLBACK TO SAVEPOINT intento_m16;
ROLLBACK;
-- El ROLLBACK exterior libera el hogar tomado ANTES del savepoint.
-- No reintentar conservando esa transaccion ni su bloqueo previo del hogar.

Sesion 1 debe obtener ahora el hogar. Probar tambien el M08 real de staging:

SAVEPOINT intento_m08;
SELECT nfc_seguridad.m08_desactivar_cuenta();
-- Aceptacion o rechazo segun las reglas ya existentes de M08.
ROLLBACK TO SAVEPOINT intento_m08;
ROLLBACK;

Verificar que perfiles, titularidad y membresias conservan la fixture.
Repetir cambiando TRANSFERIR por PROMOVER, con B ya ADMIN.
La secuencia controla el prefijo perfil/hogar sin instrumentar M08 ni depender
de pausas dentro de su cuerpo. No demuestra ausencia de otros bloqueos internos.

4. CONCURRENCIA: M16 OBTIENE PRIMERO EL PERFIL

Restaurar fixture A/B ADMIN/ACTIVA, ACTIVO en H, y configurar claims como antes.
Sesion 2/A:

BEGIN;
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.a'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.a'), 'role', 'authenticated')::text, true);
SELECT public.m16_gestionar_miembro(current_setting('m16_test.hogar')::uuid,
  'TRANSFERIR', current_setting('m16_test.b')::uuid);
-- No confirmar: conserva hogar FOR UPDATE y perfil B FOR SHARE.

Sesion 1/B:

BEGIN;
SET LOCAL statement_timeout = '10s';
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.b'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.b'), 'role', 'authenticated')::text, true);
SELECT nfc_seguridad.m08_desactivar_cuenta();
-- Debe esperar por perfil B, sin que M16 espere por B.

Sesion 2/A: ROLLBACK antes del timeout de sesion 1.
Sesion 1/B: M08 continua o rechaza por negocio; terminar ROLLBACK.
No confirmar ninguna desactivacion de prueba en esta copia.

4A. CONCURRENCIA SOBRE EL PROPIO SOLICITANTE

Fixture restaurada A/ADMIN/ACTIVA y creador, B/MIEMBRO/ACTIVA, ACTIVO ambos en H.
Configurar m16_test.hogar/a/b en ambas conexiones. Usar claims A en sesion 2.

Sesion 1:
BEGIN;
SELECT id FROM public.perfil WHERE id = current_setting('m16_test.a')::uuid FOR UPDATE;
-- Simula el bloqueo inicial de M08 al desactivar A. Mantener abierta.

Sesion 2:
BEGIN;
SET LOCAL statement_timeout = '10s';
SELECT set_config('request.jwt.claim.sub', current_setting('m16_test.a'), true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('m16_test.a'), 'role', 'authenticated')::text, true);
SELECT public.m16_gestionar_miembro(current_setting('m16_test.hogar')::uuid,
  'PROMOVER', current_setting('m16_test.b')::uuid);
-- Debe fallar inmediatamente con 55P03 y mensaje del SOLICITANTE ocupado,
-- no con M16_SOLICITANTE_NO_ACTIVO, 40P01 ni timeout 57014.
ROLLBACK;

Sesion 1: ROLLBACK.
Reintentar con A aun ACTIVA y sin bloqueo: PROMOVER debe funcionar; ROLLBACK.
Con A ya DESACTIVADA/SUSPENDIDA/BANEADA y sin bloqueo, ejecutar 2A: debe fallar
con P0001/M16_SOLICITANTE_NO_ACTIVO en las cinco acciones, no con 55P03.

Orden inverso: sesion 2/A ejecuta M16 con exito y deja la transaccion abierta.
Sesion 1/A llama nfc_seguridad.m08_desactivar_cuenta() con claims A: debe esperar
por el FOR SHARE del perfil A hasta ROLLBACK de sesion 2. Finalmente ROLLBACK
en sesion 1, tanto si M08 acepta como si rechaza por sus reglas de negocio.
La cuenta no puede desactivarse entre la comprobacion de M16 y sus escrituras.

5. CAMBIO DE ESTADO Y LIMITES

Perfil B no ACTIVA, membresia ACTIVO, sin bloqueo abierto: PROMOVER y TRANSFERIR
deben rechazar M16_DESTINO_NO_ACTIVO, no aceptar un estado leido anteriormente.
55P03 significa perfil ocupado, no cuenta desactivada. No hay reintentos internos.
En RPC aborta la transaccion; en transacciones explicitas usar ROLLBACK completo
antes de reintentar, especialmente si el caller retuvo bloqueos previos.
FOR SHARE impide actualizar/eliminar los perfiles protegidos mientras M16 completa
la operacion. El solicitante se bloquea antes del hogar, en orden coherente con
M08; el destinatario solo despues de autorizar y verificar su membresia, siempre
con NOWAIT para no introducir una espera hogar -> perfil. No se modifica M08.
NOWAIT solo afecta al bloqueo de filas solicitado: no evita esperas por DDL,
triggers, otros perfiles ni bloqueos previos del caller u otras RPC.
No se afirma ausencia global de deadlocks: observar 55P03/40P01/40001 y validar
contra el esquema y M08 reales antes de autorizar un despliegue.
*/
