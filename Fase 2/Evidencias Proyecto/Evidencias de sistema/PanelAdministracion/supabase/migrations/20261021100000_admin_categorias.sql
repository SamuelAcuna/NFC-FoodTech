-- T03: archivo para aplicación manual por Claude con OK de Samuel.
begin;

alter table public.categoria
  add column if not exists vida_util_refrigerado_dias int null
    check (vida_util_refrigerado_dias between 1 and 3650),
  add column if not exists vida_util_congelado_dias int null
    check (vida_util_congelado_dias between 1 and 3650),
  add column if not exists activa boolean not null default true;

-- CA7 también exige el rango en la columna existente de despensa.
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.categoria'::regclass
      and conname = 'admin_categoria_despensa_dias_check'
  ) then
    alter table public.categoria add constraint admin_categoria_despensa_dias_check
      check (vida_util_dias_ref between 1 and 3650);
  end if;
end;
$$;

comment on column public.categoria.vida_util_dias_ref is
  'Duración referencial en días en DESPENSA; solo para recordatorios, no es vencimiento exacto.';
comment on column public.categoria.vida_util_refrigerado_dias is
  'Duración referencial en días en REFRIGERADOR; null indica sin definir.';
comment on column public.categoria.vida_util_congelado_dias is
  'Duración referencial en días en CONGELADOR; null indica sin definir.';

create unique index if not exists admin_categoria_nombre_uq
  on public.categoria (coalesce(parent_id, 0), lower(btrim(nombre)));

create or replace function public.admin_categoria_validar_arbol()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'Una categoría no puede ser su propio padre.';
    end if;

    -- Serializa los cambios de jerarquía antes de evaluar las relaciones.
    perform pg_catalog.pg_advisory_xact_lock(20261021, 3);
    if exists (
      select 1 from public.categoria as padre
      where padre.id = new.parent_id and padre.parent_id is not null
    ) then
      raise exception 'Solo se permiten dos niveles: el padre debe ser una categoría raíz.';
    end if;
    if exists (
      select 1 from public.categoria as hija where hija.parent_id = new.id
    ) then
      raise exception 'No se puede asignar un padre a una categoría que tiene subcategorías.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists admin_categoria_validar_arbol on public.categoria;
create trigger admin_categoria_validar_arbol
  before insert or update of parent_id on public.categoria
  for each row execute function public.admin_categoria_validar_arbol();
revoke execute on function public.admin_categoria_validar_arbol() from public, anon, authenticated;

drop policy if exists admin_categoria_select on public.categoria;
create policy admin_categoria_select on public.categoria for select to authenticated
  using (public.es_admin());
drop policy if exists admin_categoria_insert on public.categoria;
create policy admin_categoria_insert on public.categoria for insert to authenticated
  with check (public.es_admin('CATEGORIAS_GESTIONAR'));
drop policy if exists admin_categoria_update on public.categoria;
create policy admin_categoria_update on public.categoria for update to authenticated
  using (public.es_admin('CATEGORIAS_GESTIONAR'))
  with check (public.es_admin('CATEGORIAS_GESTIONAR'));
drop policy if exists admin_categoria_delete on public.categoria;
create policy admin_categoria_delete on public.categoria for delete to authenticated
  using (public.es_admin('CATEGORIAS_GESTIONAR'));

commit;
