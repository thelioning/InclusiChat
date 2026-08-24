# REP-001 — Plan de rollback

**Ámbito:** migraciones `20260823_009_deployed_schema_reconciliation.sql` y `20260823_010_private_helper_rebinding.sql`.

## Regla principal

No promover REP-001 a producción sin un backup verificable del proyecto activo y un snapshot previo de políticas, funciones, índices y grants.

El baseline `docs/repair/staging/REP-001_STAGING_BASELINE.sql` es exclusivamente de pruebas. **Nunca debe aplicarse a producción.**

## Antes de promover

1. Confirmar que staging sigue verde con las pruebas A/B/C.
2. Obtener backup/restauración verificable del Supabase activo.
3. Capturar `pg_policies`, funciones `public/private`, triggers, índices y grants actuales.
4. Confirmar que no aparecieron cambios manuales en producción desde el snapshot usado por REP-001.
5. Ejecutar `009` y `010` en una ventana controlada y en ese orden.
6. Repetir inmediatamente las consultas de verificación y los Security/Performance Advisors.

## Rollback durante la migración

Ambas migraciones usan transacción (`BEGIN/COMMIT`). Si una sentencia DDL falla antes del `COMMIT`, PostgreSQL revierte la migración completa. No se debe intentar continuar manualmente desde la mitad.

## Rollback después del COMMIT

### Opción preferida

Si aparece una regresión grave después del commit, restaurar el backup/PITR tomado inmediatamente antes de la promoción. Es la única forma de volver con fidelidad al estado anterior sin reconstruir manualmente decenas de políticas y ACL.

### Rollback lógico de emergencia

Solo si restaurar el backup no es viable y existe un snapshot exacto del estado anterior:

1. deshabilitar temporalmente el cliente afectado o poner el servicio en mantenimiento;
2. restaurar definiciones anteriores de RPC y helpers desde el snapshot;
3. restaurar grants anteriores;
4. restaurar políticas RLS anteriores únicamente si es imprescindible para recuperar servicio;
5. restaurar índices/triggers modificados;
6. verificar integridad y ejecutar pruebas de autorización antes de reabrir el servicio.

**Advertencia:** el estado anterior contiene políticas permisivas `USING (true)`. Un rollback lógico completo reintroduciría vulnerabilidades conocidas. Si fuera necesario regresar a ese estado por disponibilidad, la aplicación no debe considerarse segura ni apta para producción hasta reaplicar una corrección validada.

## Lo que REP-001 no toca

- no copia ni modifica datos de usuarios de producción;
- no cambia la aplicación Flutter;
- no modifica Firebase;
- no implementa aún el borrado total de cuenta de REP-003;
- no impone aún consentimiento de contacto para abrir conversación de REP-004;
- no despliega Edge Functions.

## Staging

`InclusiChat-Staging` puede reconstruirse desde cero si fuera necesario. Los usuarios A/B/C usados en las pruebas son ficticios. Un objeto ficticio de Storage creado para probar RLS permanece en staging porque Supabase protege la eliminación directa desde SQL; no contiene información real y debe eliminarse mediante Storage API o al retirar el staging.

## Criterio para abortar promoción

Abortar y no continuar si:

- el snapshot de producción ya no coincide con el utilizado para preparar `009`/`010`;
- no existe backup recuperable;
- una prueba A/B/C falla;
- reaparecen políticas universales en tablas críticas;
- `anon` obtiene acceso directo a tablas de usuario;
- una RPC interna vuelve a quedar ejecutable por `anon`;
- Storage permite lectura/escritura a un no participante.
