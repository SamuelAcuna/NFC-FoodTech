-- T01: aplicar manualmente solo por el orquestador con OK de Samuel.
begin;

insert into public.permiso (codigo, modulo) values
  ('CATEGORIAS_GESTIONAR', 'catalogo'),
  ('CATALOGO_GESTIONAR', 'catalogo'),
  ('PROPUESTOS_REVISAR', 'catalogo'),
  ('PARAMETROS_GESTIONAR', 'configuracion'),
  ('USUARIOS_VER', 'usuarios'),
  ('USUARIOS_SUSPENDER', 'usuarios'),
  ('HOGARES_VER', 'usuarios'),
  ('SOPORTE_GESTIONAR', 'soporte'),
  ('ROLES_GESTIONAR', 'seguridad'),
  ('AUDITORIA_VER', 'seguridad'),
  ('REPORTES_VER', 'reportes')
on conflict (codigo) do nothing;

insert into public.rol (codigo, nombre, es_sistema) values
  ('ADMIN', 'Administrador', true),
  ('EDITOR_CATALOGO', 'Editor de catálogo', true),
  ('SOPORTE', 'Soporte', true)
on conflict (codigo) do nothing;

insert into public.rol_permiso (rol_id, permiso_id)
select r.id, p.id
from public.rol as r
cross join public.permiso as p
where r.codigo = 'ADMIN'
   or (r.codigo = 'EDITOR_CATALOGO' and p.codigo in (
     'CATEGORIAS_GESTIONAR', 'CATALOGO_GESTIONAR',
     'PROPUESTOS_REVISAR', 'PARAMETROS_GESTIONAR'))
   or (r.codigo = 'SOPORTE' and p.codigo in (
     'USUARIOS_VER', 'HOGARES_VER', 'SOPORTE_GESTIONAR'))
on conflict (rol_id, permiso_id) do nothing;

create or replace function public.es_admin(p_permiso text default null)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    and exists (
      select 1
      from public.perfil as p
      join public.perfil_rol as pr on pr.perfil_id = p.id
      join public.rol as r on r.id = pr.rol_id
      where p.id = auth.uid()
        and p.estado_cuenta = 'ACTIVA'
        and (p_permiso is null or exists (
          select 1
          from public.rol_permiso as rp
          join public.permiso as pe on pe.id = rp.permiso_id
          where rp.rol_id = r.id and pe.codigo = p_permiso
        ))
    );
$$;
comment on function public.es_admin(text) is
  'Autoriza al usuario actual con perfil activo, rol administrativo, MFA aal2 y permiso opcional.';
revoke execute on function public.es_admin(text) from public, anon;
grant execute on function public.es_admin(text) to authenticated;

create or replace function public.mi_contexto_admin()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'tiene_rol', exists (
      select 1 from public.perfil_rol as pr
      join public.rol as r on r.id = pr.rol_id
      where pr.perfil_id = auth.uid()
    ),
    'aal', coalesce(auth.jwt() ->> 'aal', ''),
    'estado_cuenta', (
      select p.estado_cuenta from public.perfil as p where p.id = auth.uid()
    ),
    'roles', coalesce((
      select pg_catalog.jsonb_agg(r.codigo order by r.codigo)
      from public.perfil_rol as pr
      join public.rol as r on r.id = pr.rol_id
      where pr.perfil_id = auth.uid()
    ), '[]'::jsonb),
    'permisos', coalesce((
      select pg_catalog.jsonb_agg(c.codigo order by c.codigo)
      from (
        select distinct pe.codigo
        from public.perfil_rol as pr
        join public.rol_permiso as rp on rp.rol_id = pr.rol_id
        join public.permiso as pe on pe.id = rp.permiso_id
        where pr.perfil_id = auth.uid()
      ) as c
    ), '[]'::jsonb)
  );
$$;
comment on function public.mi_contexto_admin() is
  'Contexto del usuario actual para decidir el acceso y el paso MFA tras el login; no exige aal2.';
revoke execute on function public.mi_contexto_admin() from public, anon;
grant execute on function public.mi_contexto_admin() to authenticated;

-- Las tablas ya tienen RLS habilitado. Solo se reemplazan políticas del panel.
drop policy if exists admin_rol_select on public.rol;
create policy admin_rol_select on public.rol for select to authenticated
  using (public.es_admin());
drop policy if exists admin_permiso_select on public.permiso;
create policy admin_permiso_select on public.permiso for select to authenticated
  using (public.es_admin());
drop policy if exists admin_rol_permiso_select on public.rol_permiso;
create policy admin_rol_permiso_select on public.rol_permiso for select to authenticated
  using (public.es_admin());

drop policy if exists admin_rol_insert on public.rol;
create policy admin_rol_insert on public.rol for insert to authenticated
  with check (public.es_admin('ROLES_GESTIONAR') and not es_sistema);
drop policy if exists admin_rol_update on public.rol;
create policy admin_rol_update on public.rol for update to authenticated
  using (public.es_admin('ROLES_GESTIONAR') and not es_sistema)
  with check (public.es_admin('ROLES_GESTIONAR') and not es_sistema);
drop policy if exists admin_rol_delete on public.rol;
create policy admin_rol_delete on public.rol for delete to authenticated
  using (public.es_admin('ROLES_GESTIONAR') and not es_sistema);

drop policy if exists admin_rol_permiso_insert on public.rol_permiso;
create policy admin_rol_permiso_insert on public.rol_permiso for insert to authenticated
  with check (public.es_admin('ROLES_GESTIONAR'));
drop policy if exists admin_rol_permiso_delete on public.rol_permiso;
create policy admin_rol_permiso_delete on public.rol_permiso for delete to authenticated
  using (public.es_admin('ROLES_GESTIONAR'));

drop policy if exists admin_perfil_rol_select on public.perfil_rol;
create policy admin_perfil_rol_select on public.perfil_rol for select to authenticated
  using (public.es_admin('ROLES_GESTIONAR') or perfil_id = auth.uid());
drop policy if exists admin_perfil_rol_insert on public.perfil_rol;
create policy admin_perfil_rol_insert on public.perfil_rol for insert to authenticated
  with check (public.es_admin('ROLES_GESTIONAR'));
drop policy if exists admin_perfil_rol_delete on public.perfil_rol;
create policy admin_perfil_rol_delete on public.perfil_rol for delete to authenticated
  using (public.es_admin('ROLES_GESTIONAR'));

drop policy if exists admin_perfil_select on public.perfil;
create policy admin_perfil_select on public.perfil for select to authenticated
  using (public.es_admin('USUARIOS_VER') or public.es_admin('ROLES_GESTIONAR'));

create or replace function public.admin_proteger_ultimo_admin()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  -- Serializa los borrados de asignaciones ADMIN antes de consultar los restantes.
  perform r.id from public.rol as r
  where r.id = old.rol_id and r.codigo = 'ADMIN'
  for update;

  if found and not exists (
    select 1
    from public.perfil_rol as pr
    join public.rol as r on r.id = pr.rol_id
    join public.perfil as p on p.id = pr.perfil_id
    where r.codigo = 'ADMIN'
      and p.estado_cuenta = 'ACTIVA'
      and pr.perfil_id <> old.perfil_id
  ) then
    raise exception 'No se puede quitar el último administrador activo de la plataforma.';
  end if;

  return old;
end;
$$;

drop trigger if exists admin_proteger_ultimo_admin on public.perfil_rol;
create trigger admin_proteger_ultimo_admin
  before delete on public.perfil_rol
  for each row execute function public.admin_proteger_ultimo_admin();
revoke execute on function public.admin_proteger_ultimo_admin() from public, anon, authenticated;

commit;
