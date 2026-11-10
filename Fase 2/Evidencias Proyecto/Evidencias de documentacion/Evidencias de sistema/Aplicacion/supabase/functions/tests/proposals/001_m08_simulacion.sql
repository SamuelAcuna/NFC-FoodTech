BEGIN;

CREATE SCHEMA IF NOT EXISTS nfc_m08_local;
REVOKE ALL ON SCHEMA nfc_m08_local FROM PUBLIC, anon, authenticated;

CREATE TABLE nfc_m08_local.solicitud (
  id uuid PRIMARY KEY,
  propietario_hash text NOT NULL CHECK (propietario_hash ~ '^[0-9a-f]{64}$'),
  recibo_hash text NOT NULL CHECK (recibo_hash ~ '^[0-9a-f]{64}$'),
  estado text NOT NULL CHECK (estado IN
    ('RECIBIDA','SIMULADA','BLOQUEADA','RECHAZADA','ERROR','EXPIRADA')),
  codigo text NOT NULL,
  creada timestamptz NOT NULL DEFAULT now(),
  actualizada timestamptz NOT NULL DEFAULT now(),
  vence timestamptz NOT NULL DEFAULT now() + interval '24 hours'
);
CREATE UNIQUE INDEX uq_m08_local_en_curso
ON nfc_m08_local.solicitud(propietario_hash) WHERE estado = 'RECIBIDA';
ALTER TABLE nfc_m08_local.solicitud ENABLE ROW LEVEL SECURITY;
ALTER TABLE nfc_m08_local.solicitud FORCE ROW LEVEL SECURITY;
REVOKE ALL ON nfc_m08_local.solicitud FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.m08_local_reservar(
  p_solicitud uuid, p_propietario_hash text, p_recibo_hash text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v nfc_m08_local.solicitud%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF p_propietario_hash !~ '^[0-9a-f]{64}$' OR p_recibo_hash !~ '^[0-9a-f]{64}$'
     OR p_propietario_hash IS NULL OR p_recibo_hash IS NULL THEN RAISE EXCEPTION 'Solicitud invalida'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_propietario_hash, 808));
  UPDATE nfc_m08_local.solicitud SET estado = 'EXPIRADA', codigo = 'PLAZO_AGOTADO', actualizada = now()
  WHERE propietario_hash = p_propietario_hash AND estado = 'RECIBIDA'
    AND creada < now() - interval '15 minutes';
  SELECT * INTO v FROM nfc_m08_local.solicitud WHERE id = p_solicitud FOR UPDATE;
  IF FOUND THEN
    IF v.propietario_hash <> p_propietario_hash OR v.recibo_hash <> p_recibo_hash
       OR v.vence <= now() THEN RAISE EXCEPTION 'Solicitud no disponible'; END IF;
    RETURN jsonb_build_object('nueva', false, 'estado', v.estado, 'codigo', v.codigo);
  END IF;
  IF EXISTS (SELECT 1 FROM nfc_m08_local.solicitud
             WHERE propietario_hash = p_propietario_hash AND estado = 'RECIBIDA') THEN
    RETURN jsonb_build_object('nueva', false, 'estado', 'BLOQUEADA', 'codigo', 'OTRA_SOLICITUD_EN_CURSO');
  END IF;
  INSERT INTO nfc_m08_local.solicitud(id, propietario_hash, recibo_hash, estado, codigo)
  VALUES(p_solicitud, p_propietario_hash, p_recibo_hash, 'RECIBIDA', 'VERIFICANDO');
  RETURN jsonb_build_object('nueva', true, 'estado', 'RECIBIDA', 'codigo', 'VERIFICANDO');
END $$;

CREATE FUNCTION public.m08_local_finalizar(
  p_solicitud uuid, p_propietario_hash text, p_estado text, p_codigo text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v nfc_m08_local.solicitud%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF p_estado NOT IN ('SIMULADA','BLOQUEADA','RECHAZADA','ERROR') OR p_estado IS NULL
     OR p_codigo IS NULL OR p_codigo !~ '^[A-Z0-9_]{1,80}$' THEN RAISE EXCEPTION 'Estado invalido'; END IF;
  SELECT * INTO v FROM nfc_m08_local.solicitud
  WHERE id = p_solicitud AND propietario_hash = p_propietario_hash FOR UPDATE;
  IF NOT FOUND OR v.vence <= now() THEN RAISE EXCEPTION 'Solicitud no disponible'; END IF;
  IF v.estado = 'RECIBIDA' AND v.creada < now() - interval '15 minutes' THEN
    UPDATE nfc_m08_local.solicitud SET estado = 'EXPIRADA', codigo = 'PLAZO_AGOTADO', actualizada = now()
    WHERE id = p_solicitud;
    RETURN jsonb_build_object('estado', 'EXPIRADA', 'codigo', 'PLAZO_AGOTADO');
  END IF;
  IF v.estado = 'RECIBIDA' THEN
    UPDATE nfc_m08_local.solicitud SET estado = p_estado, codigo = p_codigo, actualizada = now()
    WHERE id = p_solicitud;
    RETURN jsonb_build_object('estado', p_estado, 'codigo', p_codigo);
  END IF;
  IF v.estado <> p_estado OR v.codigo <> p_codigo THEN RAISE EXCEPTION 'Transicion no permitida'; END IF;
  RETURN jsonb_build_object('estado', v.estado, 'codigo', v.codigo);
END $$;

CREATE FUNCTION public.m08_local_estado(p_solicitud uuid, p_recibo_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v nfc_m08_local.solicitud%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v FROM nfc_m08_local.solicitud
  WHERE id = p_solicitud AND recibo_hash = p_recibo_hash AND vence > now();
  IF NOT FOUND THEN RETURN jsonb_build_object('estado', 'NO_DISPONIBLE'); END IF;
  RETURN jsonb_build_object('estado', CASE WHEN v.estado = 'RECIBIDA'
    AND v.creada < now() - interval '15 minutes' THEN 'EXPIRADA' ELSE v.estado END,
    'codigo', CASE WHEN v.estado = 'RECIBIDA' AND v.creada < now() - interval '15 minutes'
      THEN 'PLAZO_AGOTADO' ELSE v.codigo END);
END $$;

CREATE FUNCTION public.m08_local_preflight(p_usuario uuid, p_sesion uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_estado text; v_sesion timestamptz; v_factor text; v_hogares bigint; v_solus bigint;
  v_activos bigint; v_admin bigint; v_sin_relevo bigint; v_historicos bigint; v_invitados bigint;
  v_archivos bigint; v_soporte bigint; v_auditoria bigint; v_fk bigint; v_total_fk bigint := 0;
  v_admin_global boolean;
  v_bloqueos jsonb := '[]'::jsonb; v_ref record;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT p.estado_cuenta INTO v_estado FROM public.perfil p WHERE p.id = p_usuario;
  IF v_estado IS DISTINCT FROM 'ACTIVA' THEN
    v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
      'codigo','CUENTA_NO_ACTIVA','mensaje','La cuenta debe estar activa; una suspension no se resuelve con reactivacion voluntaria.'));
  END IF;
  SELECT s.created_at, to_jsonb(s)->>'factor_id' INTO v_sesion, v_factor FROM auth.sessions s
  WHERE s.id = p_sesion AND s.user_id = p_usuario
    AND ((to_jsonb(s)->>'not_after') IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz > now());
  IF v_sesion IS NULL THEN
    v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
      'codigo','SESION_NO_VIGENTE','mensaje','Inicia sesion nuevamente.'));
  END IF;
  SELECT count(*) INTO v_hogares FROM public.hogar WHERE creado_por = p_usuario;
  SELECT count(*) INTO v_solus FROM public.hogar h WHERE h.creado_por = p_usuario
    AND NOT EXISTS (SELECT 1 FROM public.hogar_miembro hm JOIN public.perfil p ON p.id = hm.perfil_id
      WHERE hm.hogar_id = h.id AND hm.perfil_id <> p_usuario AND hm.estado = 'ACTIVO' AND p.estado_cuenta = 'ACTIVA');
  SELECT count(*) FILTER (WHERE estado = 'ACTIVO'),
         count(*) FILTER (WHERE estado = 'ACTIVO' AND rol = 'ADMIN'),
         count(*) FILTER (WHERE estado = 'REMOVIDO'), count(*) FILTER (WHERE estado = 'INVITADO')
  INTO v_activos, v_admin, v_historicos, v_invitados
  FROM public.hogar_miembro WHERE perfil_id = p_usuario;
  SELECT count(*) INTO v_sin_relevo FROM public.hogar_miembro hm
  WHERE hm.perfil_id = p_usuario AND hm.estado = 'ACTIVO' AND hm.rol = 'ADMIN'
    AND NOT EXISTS (SELECT 1 FROM public.hogar_miembro otro JOIN public.perfil p ON p.id = otro.perfil_id
      WHERE otro.hogar_id = hm.hogar_id AND otro.perfil_id <> p_usuario
      AND otro.estado = 'ACTIVO' AND otro.rol = 'ADMIN' AND p.estado_cuenta = 'ACTIVA');
  IF v_solus > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','CREADOR_SIN_RELEVO','mensaje','El cierre seguro del hogar donde eres creador sin otro integrante activo esta pendiente. No se eliminara automaticamente.')); END IF;
  IF v_hogares > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','CREADOR_HOGAR','mensaje','Transfiere la administracion y la responsabilidad del hogar antes de continuar.')); END IF;
  IF v_activos > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','MEMBRESIA_ACTIVA','mensaje','Abandona el hogar; si corresponde, transfiere primero la administracion.')); END IF;
  IF v_sin_relevo > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','ADMIN_SIN_RELEVO','mensaje','Debe existir otro administrador con membresia y cuenta activas.')); END IF;
  SELECT EXISTS (SELECT 1 FROM public.perfil_rol pr JOIN public.rol r ON r.id = pr.rol_id
    WHERE pr.perfil_id = p_usuario AND r.codigo = 'ADMIN') INTO v_admin_global;
  IF v_admin_global AND NOT EXISTS (
    SELECT 1 FROM public.perfil_rol pr JOIN public.rol r ON r.id = pr.rol_id
    JOIN public.perfil p ON p.id = pr.perfil_id
    WHERE r.codigo = 'ADMIN' AND p.estado_cuenta = 'ACTIVA' AND pr.perfil_id <> p_usuario
  ) THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','ADMIN_GLOBAL_SIN_RELEVO','mensaje','Debe conservarse otro administrador global activo.'));
  END IF;
  SELECT count(*) INTO v_archivos FROM storage.objects o
  WHERE o.owner_id = p_usuario::text OR (o.bucket_id = 'fotos_perfil' AND o.name LIKE p_usuario::text || '/%');
  IF v_archivos > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','STORAGE_PENDIENTE','mensaje','Existen archivos propios. Falta validar su limpieza separada mediante Storage, sin tocar archivos compartidos.')); END IF;
  SELECT count(*) INTO v_soporte FROM public.solicitud_soporte WHERE solicitado_por = p_usuario;
  IF v_soporte > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','CONSERVACION_SOPORTE','mensaje','Debe resolverse la conservacion de las solicitudes de soporte antes del borrado en cascada.')); END IF;
  SELECT count(*) INTO v_auditoria FROM public.auditoria
  WHERE perfil_id = p_usuario OR entidad_id = p_usuario::text
    OR coalesce(antes::text,'') LIKE '%' || p_usuario::text || '%'
    OR coalesce(despues::text,'') LIKE '%' || p_usuario::text || '%';
  IF v_auditoria > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','CONSERVACION_AUDITORIA','mensaje','Debe revisarse la conservacion de datos identificatorios en auditoria; SET NULL no limpia los documentos JSON.')); END IF;
  FOR v_ref IN
    SELECT co.conrelid, co.conkey, co.confkey, co.confrelid, a.attname, destino.attname AS destino
    FROM pg_catalog.pg_constraint co
    JOIN pg_catalog.pg_attribute a ON a.attrelid = co.conrelid AND a.attnum = co.conkey[1]
    JOIN pg_catalog.pg_attribute destino ON destino.attrelid = co.confrelid AND destino.attnum = co.confkey[1]
    WHERE co.contype = 'f' AND co.confrelid IN ('auth.users'::regclass, 'public.perfil'::regclass)
      AND co.confdeltype IN ('a','r')
  LOOP
    IF cardinality(v_ref.conkey) <> 1 OR v_ref.destino <> 'id' THEN
      v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
        'codigo','REFERENCIA_NO_COMPATIBLE','mensaje','Una referencia requiere revision tecnica antes de continuar.'));
    ELSE
      EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', v_ref.conrelid::regclass, v_ref.attname)
      INTO v_fk USING p_usuario;
      v_total_fk := v_total_fk + v_fk;
    END IF;
  END LOOP;
  IF v_total_fk > 0 THEN v_bloqueos := v_bloqueos || jsonb_build_array(jsonb_build_object(
    'codigo','REFERENCIA_BLOQUEANTE','mensaje','Existen referencias NO ACTION o RESTRICT que deben resolverse sin borrar historiales compartidos.')); END IF;
  RETURN jsonb_build_object('apto', jsonb_array_length(v_bloqueos) = 0, 'bloqueos', v_bloqueos,
    'sesion_creada', v_sesion, 'sesion_factor', v_factor,
    'resumen', jsonb_build_object('estado_cuenta', v_estado, 'hogares_creados', v_hogares,
      'creador_sin_relevo', v_solus, 'membresias_activas', v_activos, 'administraciones', v_admin,
      'sin_otro_admin_activo', v_sin_relevo, 'membresias_removidas', v_historicos,
      'admin_global', v_admin_global,
      'invitaciones', v_invitados, 'archivos', v_archivos, 'soporte', v_soporte,
      'auditoria', v_auditoria, 'referencias_bloqueantes', v_total_fk),
    'consecuencias', jsonb_build_array(
      'Los historiales compartidos con autoria SET NULL se conservan; no deben vaciarse.',
      'Las membresias REMOVIDO e INVITADO no son activas y no bloquean por si mismas.',
      'CASCADE eliminaria perfil, identificacion y datos personales dependientes segun el esquema vigente.',
      'La politica de nuevo registro con el mismo RUT sigue pendiente; no se crea una lista de RUT eliminados.',
      'Falta validar todos los triggers, referencias transitivas y reglas de privacidad antes del borrado real.'
    ));
END $$;

CREATE FUNCTION public.m08_local_purgar()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_total bigint;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  DELETE FROM nfc_m08_local.solicitud WHERE vence <= now();
  GET DIAGNOSTICS v_total = ROW_COUNT;
  RETURN v_total;
END $$;

REVOKE ALL ON FUNCTION public.m08_local_reservar(uuid,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.m08_local_finalizar(uuid,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.m08_local_estado(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.m08_local_preflight(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.m08_local_reservar(uuid,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.m08_local_finalizar(uuid,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.m08_local_estado(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.m08_local_preflight(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.m08_local_purgar() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.m08_local_purgar() TO service_role;

COMMIT;
