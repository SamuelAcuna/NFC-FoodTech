-- Semilla manual, después de T03; ejecutar solo con OK de Samuel.
-- Solo nombres: no define ni modifica duraciones, incluso en filas existentes.
begin;
insert into public.categoria (nombre) values
  ('Frutas'),
  ('Verduras'),
  ('Lácteos'),
  ('Carnes rojas'),
  ('Aves'),
  ('Pescados y mariscos'),
  ('Huevos'),
  ('Panadería'),
  ('Cereales y legumbres'),
  ('Conservas'),
  ('Congelados'),
  ('Bebidas'),
  ('Salsas y aderezos'),
  ('Snacks y dulces')
on conflict do nothing;
commit;
