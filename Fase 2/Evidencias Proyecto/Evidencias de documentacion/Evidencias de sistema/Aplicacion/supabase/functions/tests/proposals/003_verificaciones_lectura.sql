SELECT p.oid::regprocedure AS funcion, p.prosecdef AS security_definer,
       p.proconfig AS configuracion,
       NOT has_function_privilege('anon',p.oid,'EXECUTE') AS anon_sin_acceso,
       NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_sin_acceso,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS backend_con_acceso
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'm08_local_%'
ORDER BY 1;

SELECT c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
       NOT EXISTS (SELECT 1 FROM pg_constraint co WHERE co.conrelid = c.oid AND co.contype = 'f')
         AS registro_sin_fk_cascade
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'nfc_m08_local' AND c.relname = 'solicitud';

SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'nfc_m08_local' AND tablename = 'solicitud';

SELECT pg_get_functiondef(to_regprocedure('public.m16_gestionar_miembro(uuid,text,uuid)'))
  AS revisar_guardias_promover_transferir;
