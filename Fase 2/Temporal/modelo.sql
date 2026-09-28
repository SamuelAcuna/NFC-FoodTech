-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.perfil (
  id uuid NOT NULL,
  nombre text,
  apellido text,
  fecha_nacimiento date,
  sexo text CHECK (sexo = ANY (ARRAY['FEMENINO'::text, 'MASCULINO'::text, 'OTRO'::text, 'NO_INFORMA'::text])),
  zona_horaria text NOT NULL DEFAULT 'America/Santiago'::text,
  avatar_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  estado_cuenta text NOT NULL DEFAULT 'ACTIVA'::text CHECK (estado_cuenta = ANY (ARRAY['ACTIVA'::text, 'SUSPENDIDA'::text, 'BANEADA'::text])),
  CONSTRAINT perfil_pkey PRIMARY KEY (id),
  CONSTRAINT perfil_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.hogar (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nombre text NOT NULL,
  adultos smallint CHECK (adultos >= 0),
  menores smallint CHECK (menores >= 0),
  creado_por uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT hogar_pkey PRIMARY KEY (id),
  CONSTRAINT hogar_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.hogar_miembro (
  hogar_id uuid NOT NULL,
  perfil_id uuid NOT NULL,
  rol text NOT NULL DEFAULT 'MIEMBRO'::text CHECK (rol = ANY (ARRAY['ADMIN'::text, 'MIEMBRO'::text])),
  estado text NOT NULL DEFAULT 'INVITADO'::text CHECK (estado = ANY (ARRAY['ACTIVO'::text, 'INVITADO'::text, 'REMOVIDO'::text])),
  invitado_por uuid,
  joined_at timestamp with time zone,
  CONSTRAINT hogar_miembro_pkey PRIMARY KEY (hogar_id, perfil_id),
  CONSTRAINT hogar_miembro_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id),
  CONSTRAINT hogar_miembro_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id),
  CONSTRAINT hogar_miembro_invitado_por_fkey FOREIGN KEY (invitado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.categoria (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre text NOT NULL,
  parent_id bigint,
  vida_util_dias_ref integer CHECK (vida_util_dias_ref > 0),
  temp_conservacion text CHECK (temp_conservacion = ANY (ARRAY['AMBIENTE'::text, 'REFRIGERADO'::text, 'CONGELADO'::text])),
  CONSTRAINT categoria_pkey PRIMARY KEY (id),
  CONSTRAINT categoria_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categoria(id)
);
CREATE TABLE public.alimento (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre text NOT NULL UNIQUE,
  categoria_id bigint NOT NULL,
  vida_util_dias_ref integer CHECK (vida_util_dias_ref > 0),
  unidad_base text NOT NULL CHECK (unidad_base = ANY (ARRAY['g'::text, 'ml'::text, 'un'::text])),
  es_perecible boolean NOT NULL DEFAULT true,
  estado text NOT NULL DEFAULT 'APROBADO'::text CHECK (estado = ANY (ARRAY['PROPUESTO'::text, 'APROBADO'::text, 'RECHAZADO'::text])),
  CONSTRAINT alimento_pkey PRIMARY KEY (id),
  CONSTRAINT alimento_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categoria(id)
);
CREATE TABLE public.marca (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre text NOT NULL UNIQUE,
  CONSTRAINT marca_pkey PRIMARY KEY (id)
);
CREATE TABLE public.producto (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  codigo text,
  tipo_codigo text NOT NULL CHECK (tipo_codigo = ANY (ARRAY['EAN13'::text, 'EAN8'::text, 'UPC'::text, 'INTERNO'::text, 'SIN_CODIGO'::text])),
  nombre text NOT NULL,
  marca_id bigint,
  marca_texto text,
  alimento_id bigint NOT NULL,
  tipo_medida text NOT NULL CHECK (tipo_medida = ANY (ARRAY['PESO'::text, 'VOLUMEN'::text, 'UNIDAD'::text])),
  cantidad_neta numeric NOT NULL CHECK (cantidad_neta > 0::numeric),
  unidad_neta text NOT NULL CHECK (unidad_neta = ANY (ARRAY['g'::text, 'kg'::text, 'ml'::text, 'l'::text, 'un'::text])),
  peso_drenado numeric CHECK (peso_drenado > 0::numeric),
  unidad_drenado text CHECK (unidad_drenado = ANY (ARRAY['g'::text, 'kg'::text])),
  unidades_envase smallint NOT NULL DEFAULT 1 CHECK (unidades_envase >= 1),
  contenido_unitario numeric,
  imagen_url text,
  atributos jsonb NOT NULL DEFAULT '{}'::jsonb,
  hogar_id uuid,
  estado text NOT NULL DEFAULT 'LOCAL'::text CHECK (estado = ANY (ARRAY['LOCAL'::text, 'PROPUESTO'::text, 'APROBADO'::text, 'RECHAZADO'::text])),
  canonico_id uuid,
  editado_manual boolean NOT NULL DEFAULT false,
  creado_por uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT producto_pkey PRIMARY KEY (id),
  CONSTRAINT producto_marca_id_fkey FOREIGN KEY (marca_id) REFERENCES public.marca(id),
  CONSTRAINT producto_alimento_id_fkey FOREIGN KEY (alimento_id) REFERENCES public.alimento(id),
  CONSTRAINT producto_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id),
  CONSTRAINT producto_canonico_id_fkey FOREIGN KEY (canonico_id) REFERENCES public.producto(id),
  CONSTRAINT producto_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.producto_fuente (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  producto_id uuid NOT NULL,
  fuente text NOT NULL CHECK (fuente = ANY (ARRAY['OPEN_FOOD_FACTS'::text, 'BD_PROPIA'::text, 'MANUAL'::text, 'USUARIO'::text])),
  id_externo text,
  sincronizado_en timestamp with time zone,
  payload jsonb,
  CONSTRAINT producto_fuente_pkey PRIMARY KEY (id),
  CONSTRAINT producto_fuente_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id)
);
CREATE TABLE public.producto_nutricion (
  producto_id uuid NOT NULL,
  porcion_g numeric,
  energia_kcal numeric,
  proteinas_g numeric,
  grasas_totales_g numeric,
  grasas_saturadas_g numeric,
  carbohidratos_g numeric,
  azucares_g numeric,
  sodio_mg numeric,
  sello_alto_calorias boolean NOT NULL DEFAULT false,
  sello_alto_azucar boolean NOT NULL DEFAULT false,
  sello_alto_sodio boolean NOT NULL DEFAULT false,
  sello_alto_grasas_sat boolean NOT NULL DEFAULT false,
  CONSTRAINT producto_nutricion_pkey PRIMARY KEY (producto_id),
  CONSTRAINT producto_nutricion_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id)
);
CREATE TABLE public.despensa_item (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  hogar_id uuid NOT NULL,
  producto_id uuid,
  alimento_id bigint,
  cantidad_inicial numeric NOT NULL CHECK (cantidad_inicial > 0::numeric),
  cantidad_restante numeric NOT NULL,
  fecha_ingreso date NOT NULL DEFAULT CURRENT_DATE,
  fecha_vencimiento date,
  vencimiento_estimado boolean NOT NULL DEFAULT false,
  lote_id uuid,
  ubicacion text NOT NULL DEFAULT 'DESPENSA'::text CHECK (ubicacion = ANY (ARRAY['DESPENSA'::text, 'REFRIGERADOR'::text, 'CONGELADOR'::text])),
  estado text NOT NULL DEFAULT 'DISPONIBLE'::text CHECK (estado = ANY (ARRAY['DISPONIBLE'::text, 'AGOTADO'::text, 'DESECHADO'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  compra_id uuid,
  precio_clp integer CHECK (precio_clp >= 0),
  CONSTRAINT despensa_item_pkey PRIMARY KEY (id),
  CONSTRAINT despensa_item_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id),
  CONSTRAINT despensa_item_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id),
  CONSTRAINT despensa_item_alimento_id_fkey FOREIGN KEY (alimento_id) REFERENCES public.alimento(id),
  CONSTRAINT despensa_item_compra_id_fkey FOREIGN KEY (compra_id) REFERENCES public.compra(id)
);
CREATE TABLE public.tipo_desperdicio (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL UNIQUE,
  nombre text NOT NULL,
  descripcion text,
  es_evitable boolean NOT NULL,
  cuenta_para_vida_util boolean NOT NULL DEFAULT false,
  activo boolean NOT NULL DEFAULT true,
  CONSTRAINT tipo_desperdicio_pkey PRIMARY KEY (id)
);
CREATE TABLE public.movimiento (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  despensa_item_id uuid NOT NULL,
  tipo text NOT NULL CHECK (tipo = ANY (ARRAY['INGRESO'::text, 'CONSUMO'::text, 'DESCARTE'::text, 'AJUSTE'::text])),
  cantidad numeric NOT NULL CHECK (cantidad > 0::numeric),
  tipo_desperdicio_id bigint,
  registrado_por uuid NOT NULL,
  fecha timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT movimiento_pkey PRIMARY KEY (id),
  CONSTRAINT movimiento_despensa_item_id_fkey FOREIGN KEY (despensa_item_id) REFERENCES public.despensa_item(id),
  CONSTRAINT movimiento_tipo_desperdicio_id_fkey FOREIGN KEY (tipo_desperdicio_id) REFERENCES public.tipo_desperdicio(id),
  CONSTRAINT movimiento_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.observacion_duracion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  movimiento_id uuid NOT NULL UNIQUE,
  alimento_id bigint NOT NULL,
  producto_id uuid,
  hogar_id uuid NOT NULL,
  dias_transcurridos integer NOT NULL CHECK (dias_transcurridos >= 0),
  ubicacion text NOT NULL CHECK (ubicacion = ANY (ARRAY['DESPENSA'::text, 'REFRIGERADOR'::text, 'CONGELADOR'::text])),
  registrada_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT observacion_duracion_pkey PRIMARY KEY (id),
  CONSTRAINT observacion_duracion_movimiento_id_fkey FOREIGN KEY (movimiento_id) REFERENCES public.movimiento(id),
  CONSTRAINT observacion_duracion_alimento_id_fkey FOREIGN KEY (alimento_id) REFERENCES public.alimento(id),
  CONSTRAINT observacion_duracion_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id),
  CONSTRAINT observacion_duracion_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id)
);
CREATE TABLE public.estimacion_vida_util (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ambito text NOT NULL CHECK (ambito = ANY (ARRAY['CATEGORIA'::text, 'ALIMENTO'::text, 'PRODUCTO'::text])),
  referencia_id text NOT NULL,
  hogar_id uuid,
  ubicacion text NOT NULL CHECK (ubicacion = ANY (ARRAY['DESPENSA'::text, 'REFRIGERADOR'::text, 'CONGELADOR'::text])),
  dias_mediana numeric NOT NULL,
  dispersion numeric,
  n_observaciones integer NOT NULL CHECK (n_observaciones >= 0),
  actualizada_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT estimacion_vida_util_pkey PRIMARY KEY (id),
  CONSTRAINT estimacion_vida_util_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id)
);
CREATE TABLE public.dispositivo (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  perfil_id uuid NOT NULL,
  push_token text NOT NULL UNIQUE,
  plataforma text NOT NULL CHECK (plataforma = ANY (ARRAY['ANDROID'::text, 'IOS'::text, 'WEB'::text])),
  activo boolean NOT NULL DEFAULT true,
  ultimo_uso timestamp with time zone,
  CONSTRAINT dispositivo_pkey PRIMARY KEY (id),
  CONSTRAINT dispositivo_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id)
);
CREATE TABLE public.plantilla_notificacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL UNIQUE,
  categoria text NOT NULL CHECK (categoria = ANY (ARRAY['VENCIMIENTO'::text, 'RESUMEN'::text, 'HOGAR'::text, 'SISTEMA'::text, 'MODERACION'::text])),
  titulo_tpl text NOT NULL,
  cuerpo_tpl text NOT NULL,
  es_silenciable boolean NOT NULL DEFAULT true,
  CONSTRAINT plantilla_notificacion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.preferencia_notificacion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  perfil_id uuid NOT NULL,
  plantilla_id bigint NOT NULL,
  habilitada boolean NOT NULL DEFAULT true,
  dias_anticipacion smallint CHECK (dias_anticipacion >= 0),
  hora_envio time without time zone,
  CONSTRAINT preferencia_notificacion_pkey PRIMARY KEY (id),
  CONSTRAINT preferencia_notificacion_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id),
  CONSTRAINT preferencia_notificacion_plantilla_id_fkey FOREIGN KEY (plantilla_id) REFERENCES public.plantilla_notificacion(id)
);
CREATE TABLE public.notificacion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  perfil_id uuid NOT NULL,
  plantilla_id bigint NOT NULL,
  despensa_item_id uuid,
  datos jsonb,
  estado text NOT NULL DEFAULT 'PENDIENTE'::text CHECK (estado = ANY (ARRAY['PENDIENTE'::text, 'ENVIADA'::text, 'LEIDA'::text, 'CANCELADA'::text, 'FALLIDA'::text])),
  programada_para timestamp with time zone NOT NULL,
  leida_en timestamp with time zone,
  clave_dedup text NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT notificacion_pkey PRIMARY KEY (id),
  CONSTRAINT notificacion_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id),
  CONSTRAINT notificacion_plantilla_id_fkey FOREIGN KEY (plantilla_id) REFERENCES public.plantilla_notificacion(id),
  CONSTRAINT notificacion_despensa_item_id_fkey FOREIGN KEY (despensa_item_id) REFERENCES public.despensa_item(id)
);
CREATE TABLE public.envio_notificacion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  notificacion_id uuid NOT NULL,
  dispositivo_id uuid,
  canal text NOT NULL CHECK (canal = ANY (ARRAY['PUSH'::text, 'EMAIL'::text, 'IN_APP'::text])),
  resultado text NOT NULL CHECK (resultado = ANY (ARRAY['OK'::text, 'ERROR'::text, 'TOKEN_INVALIDO'::text])),
  mensaje_error text,
  enviado_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT envio_notificacion_pkey PRIMARY KEY (id),
  CONSTRAINT envio_notificacion_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES public.dispositivo(id),
  CONSTRAINT envio_notificacion_notificacion_id_fkey FOREIGN KEY (notificacion_id) REFERENCES public.notificacion(id)
);
CREATE TABLE public.lista_compra (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  hogar_id uuid NOT NULL,
  nombre text NOT NULL,
  estado text NOT NULL DEFAULT 'ABIERTA'::text CHECK (estado = ANY (ARRAY['ABIERTA'::text, 'CERRADA'::text, 'ARCHIVADA'::text])),
  creada_por uuid NOT NULL,
  creada_en timestamp with time zone NOT NULL DEFAULT now(),
  cerrada_en timestamp with time zone,
  CONSTRAINT lista_compra_pkey PRIMARY KEY (id),
  CONSTRAINT lista_compra_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id),
  CONSTRAINT lista_compra_creada_por_fkey FOREIGN KEY (creada_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.lista_compra_item (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  lista_id uuid NOT NULL,
  producto_id uuid,
  alimento_id bigint,
  cantidad numeric NOT NULL CHECK (cantidad > 0::numeric),
  unidad text NOT NULL CHECK (unidad = ANY (ARRAY['g'::text, 'kg'::text, 'ml'::text, 'l'::text, 'un'::text])),
  origen text NOT NULL DEFAULT 'MANUAL'::text CHECK (origen = ANY (ARRAY['MANUAL'::text, 'SUGERIDO_CONSUMO'::text, 'SUGERIDO_VENCIDO'::text])),
  estado text NOT NULL DEFAULT 'PENDIENTE'::text CHECK (estado = ANY (ARRAY['PENDIENTE'::text, 'COMPRADO'::text, 'DESCARTADO'::text])),
  despensa_item_id uuid,
  agregado_por uuid NOT NULL,
  CONSTRAINT lista_compra_item_pkey PRIMARY KEY (id),
  CONSTRAINT lista_compra_item_agregado_por_fkey FOREIGN KEY (agregado_por) REFERENCES public.perfil(id),
  CONSTRAINT lista_compra_item_lista_id_fkey FOREIGN KEY (lista_id) REFERENCES public.lista_compra(id),
  CONSTRAINT lista_compra_item_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id),
  CONSTRAINT lista_compra_item_alimento_id_fkey FOREIGN KEY (alimento_id) REFERENCES public.alimento(id),
  CONSTRAINT lista_compra_item_despensa_item_id_fkey FOREIGN KEY (despensa_item_id) REFERENCES public.despensa_item(id)
);
CREATE TABLE public.rol (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL UNIQUE,
  nombre text NOT NULL,
  descripcion text,
  es_sistema boolean NOT NULL DEFAULT false,
  CONSTRAINT rol_pkey PRIMARY KEY (id)
);
CREATE TABLE public.permiso (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL UNIQUE,
  descripcion text,
  modulo text NOT NULL,
  CONSTRAINT permiso_pkey PRIMARY KEY (id)
);
CREATE TABLE public.rol_permiso (
  rol_id bigint NOT NULL,
  permiso_id bigint NOT NULL,
  CONSTRAINT rol_permiso_pkey PRIMARY KEY (rol_id, permiso_id),
  CONSTRAINT rol_permiso_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.rol(id),
  CONSTRAINT rol_permiso_permiso_id_fkey FOREIGN KEY (permiso_id) REFERENCES public.permiso(id)
);
CREATE TABLE public.perfil_rol (
  perfil_id uuid NOT NULL,
  rol_id bigint NOT NULL,
  asignado_por uuid,
  asignado_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT perfil_rol_pkey PRIMARY KEY (perfil_id, rol_id),
  CONSTRAINT perfil_rol_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id),
  CONSTRAINT perfil_rol_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.rol(id),
  CONSTRAINT perfil_rol_asignado_por_fkey FOREIGN KEY (asignado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.solicitud_moderacion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tipo text NOT NULL CHECK (tipo = ANY (ARRAY['PRODUCTO_NUEVO'::text, 'ALIMENTO_NUEVO'::text, 'CORRECCION'::text, 'DUPLICADO'::text])),
  entidad text NOT NULL,
  entidad_id text,
  payload jsonb,
  estado text NOT NULL DEFAULT 'PENDIENTE'::text CHECK (estado = ANY (ARRAY['PENDIENTE'::text, 'EN_REVISION'::text, 'APROBADA'::text, 'RECHAZADA'::text])),
  prioridad smallint NOT NULL DEFAULT 3 CHECK (prioridad >= 1 AND prioridad <= 5),
  solicitado_por uuid NOT NULL,
  solicitado_en timestamp with time zone NOT NULL DEFAULT now(),
  revisado_por uuid,
  revisado_en timestamp with time zone,
  resolucion_nota text,
  CONSTRAINT solicitud_moderacion_pkey PRIMARY KEY (id),
  CONSTRAINT solicitud_moderacion_solicitado_por_fkey FOREIGN KEY (solicitado_por) REFERENCES public.perfil(id),
  CONSTRAINT solicitud_moderacion_revisado_por_fkey FOREIGN KEY (revisado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.motivo_sancion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL UNIQUE,
  nombre text NOT NULL,
  gravedad smallint NOT NULL CHECK (gravedad >= 1 AND gravedad <= 5),
  CONSTRAINT motivo_sancion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.sancion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  perfil_id uuid NOT NULL,
  tipo text NOT NULL CHECK (tipo = ANY (ARRAY['ADVERTENCIA'::text, 'SUSPENSION'::text, 'BANEO'::text])),
  motivo_id bigint NOT NULL,
  detalle text,
  inicia_en timestamp with time zone NOT NULL DEFAULT now(),
  expira_en timestamp with time zone,
  estado text NOT NULL DEFAULT 'ACTIVA'::text CHECK (estado = ANY (ARRAY['ACTIVA'::text, 'CUMPLIDA'::text, 'REVOCADA'::text])),
  aplicada_por uuid NOT NULL,
  revocada_por uuid,
  revocada_en timestamp with time zone,
  nota_revocacion text,
  CONSTRAINT sancion_pkey PRIMARY KEY (id),
  CONSTRAINT sancion_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id),
  CONSTRAINT sancion_motivo_id_fkey FOREIGN KEY (motivo_id) REFERENCES public.motivo_sancion(id),
  CONSTRAINT sancion_aplicada_por_fkey FOREIGN KEY (aplicada_por) REFERENCES public.perfil(id),
  CONSTRAINT sancion_revocada_por_fkey FOREIGN KEY (revocada_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.auditoria (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  entidad text NOT NULL,
  entidad_id text NOT NULL,
  accion text NOT NULL CHECK (accion = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text, 'APROBAR'::text, 'RECHAZAR'::text, 'SANCIONAR'::text])),
  perfil_id uuid,
  antes jsonb,
  despues jsonb,
  fecha timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT auditoria_pkey PRIMARY KEY (id),
  CONSTRAINT auditoria_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id)
);
CREATE TABLE public.parametro (
  clave text NOT NULL,
  valor text NOT NULL,
  tipo_dato text NOT NULL CHECK (tipo_dato = ANY (ARRAY['TEXTO'::text, 'ENTERO'::text, 'DECIMAL'::text, 'BOOLEANO'::text, 'JSON'::text])),
  descripcion text,
  actualizado_por uuid,
  actualizado_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT parametro_pkey PRIMARY KEY (clave),
  CONSTRAINT parametro_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.perfil(id)
);
CREATE TABLE public.job_ejecucion (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  job_codigo text NOT NULL,
  estado text NOT NULL CHECK (estado = ANY (ARRAY['EN_CURSO'::text, 'OK'::text, 'PARCIAL'::text, 'ERROR'::text])),
  iniciado_en timestamp with time zone NOT NULL DEFAULT now(),
  finalizado_en timestamp with time zone,
  registros_ok integer NOT NULL DEFAULT 0 CHECK (registros_ok >= 0),
  registros_error integer NOT NULL DEFAULT 0 CHECK (registros_error >= 0),
  mensaje_error text,
  resumen jsonb,
  CONSTRAINT job_ejecucion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.log_evento (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nivel text NOT NULL CHECK (nivel = ANY (ARRAY['DEBUG'::text, 'INFO'::text, 'WARN'::text, 'ERROR'::text])),
  origen text NOT NULL CHECK (origen = ANY (ARRAY['APP_MOVIL'::text, 'WEB_ADMIN'::text, 'API'::text, 'JOB'::text])),
  codigo text,
  mensaje text NOT NULL,
  contexto jsonb,
  job_id uuid,
  perfil_id uuid,
  ocurrido_en timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT log_evento_pkey PRIMARY KEY (id),
  CONSTRAINT log_evento_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.job_ejecucion(id),
  CONSTRAINT log_evento_perfil_id_fkey FOREIGN KEY (perfil_id) REFERENCES public.perfil(id)
);
CREATE TABLE public.compra (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  hogar_id uuid NOT NULL,
  fecha date NOT NULL DEFAULT CURRENT_DATE,
  lugar text,
  total_clp integer CHECK (total_clp >= 0),
  registrado_por uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT compra_pkey PRIMARY KEY (id),
  CONSTRAINT compra_hogar_id_fkey FOREIGN KEY (hogar_id) REFERENCES public.hogar(id),
  CONSTRAINT compra_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES public.perfil(id)
);
