-- T14: aplicar manualmente solo por el orquestador con OK de Samuel.
begin;

alter table public.alimento
  add column if not exists activo boolean not null default true;
comment on column public.alimento.activo is
  'Baja lógica del catálogo maestro (RF84). La app no debe ofrecer alimentos inactivos al agregar.';

create index if not exists admin_alimento_catalogo_ix
  on public.alimento (categoria_id, activo) where hogar_id is null;

-- Catálogo maestro: las filas privadas de un hogar quedan fuera del panel.
drop policy if exists admin_alimento_select on public.alimento;
create policy admin_alimento_select on public.alimento for select to authenticated
  using (hogar_id is null and public.es_admin());

drop policy if exists admin_alimento_insert on public.alimento;
create policy admin_alimento_insert on public.alimento for insert to authenticated
  with check (
    public.es_admin('CATALOGO_GESTIONAR')
    and hogar_id is null
    and estado = 'APROBADO'
    and creado_por = (select auth.uid())
  );

drop policy if exists admin_alimento_update on public.alimento;
create policy admin_alimento_update on public.alimento for update to authenticated
  using (public.es_admin('CATALOGO_GESTIONAR') and hogar_id is null)
  with check (
    public.es_admin('CATALOGO_GESTIONAR')
    and hogar_id is null
    and estado = 'APROBADO'
  );

drop policy if exists admin_alimento_delete on public.alimento;
create policy admin_alimento_delete on public.alimento for delete to authenticated
  using (public.es_admin('CATALOGO_GESTIONAR') and hogar_id is null);

-- Las claves de parámetros se crearán con la semilla de T12.
drop policy if exists admin_parametro_select on public.parametro;
create policy admin_parametro_select on public.parametro for select to authenticated
  using (public.es_admin());

drop policy if exists admin_parametro_update on public.parametro;
create policy admin_parametro_update on public.parametro for update to authenticated
  using (public.es_admin('PARAMETROS_GESTIONAR'))
  with check (
    public.es_admin('PARAMETROS_GESTIONAR')
    and actualizado_por = (select auth.uid())
  );

-- Soporte solo lectura; las escrituras de negocio corresponden a T08.
drop policy if exists admin_solicitud_soporte_select on public.solicitud_soporte;
create policy admin_solicitud_soporte_select on public.solicitud_soporte for select to authenticated
  using (public.es_admin('SOPORTE_GESTIONAR'));

-- Catálogos de referencia: solo lectura administrativa.
drop policy if exists admin_tipo_desperdicio_select on public.tipo_desperdicio;
create policy admin_tipo_desperdicio_select on public.tipo_desperdicio for select to authenticated
  using (public.es_admin());

drop policy if exists admin_region_select on public.region;
create policy admin_region_select on public.region for select to authenticated
  using (public.es_admin());

drop policy if exists admin_comuna_select on public.comuna;
create policy admin_comuna_select on public.comuna for select to authenticated
  using (public.es_admin());

commit;
