# REP-001 — Plan de rollback

**Ámbito:** migraciones `009`, `010`, `011` y `012` de la reconciliación REP-001.

## Regla principal

No promover REP-001 a producción sin un backup verificable del proyecto activo y un snapshot inmediatamente anterior de políticas, funciones, índices, triggers y grants.

El baseline `docs/repair/staging/REP-001_STAGING_BASELINE.sql` es exclusivamente de pruebas. **Nunca debe aplicarse a producción.**

## Secuencia autorizada de promoción

Si más adelante el propietario autoriza producción, aplicar en este orden y sin saltos:

1. `20260823_009_deployed_schema_reconciliation.sql`
2. `20260823_010_private_helper_rebinding.sql`
3. `20260824_011_contact_response_invoker.sql`
4. `20260824_012_accept_contact_request_via_trigger.sql`

`011` y `012` son necesarias: staging demostró que convertir las RPC de respuesta de contactos a `SECURITY INVOKER` requiere que `accept_contact_request()` delegue la creación recíproca de contactos al trigger privado.

## Antes de promover

1. Confirmar que staging sigue verde con las pruebas A/B/C.
2. Obtener backup/restauración verificable del Supabase activo.
3. Capturar `pg_policies`, funciones `public/private`, triggers, índices y grants actuales.
4. Confirmar que no apareció drift desde el snapshot utilizado para preparar la reconciliación.
5. Ejecutar `009 → 010 → 011 → 012` en una ventana controlada.
6. Repetir inmediatamente las pruebas de autorización y los Security/Performance Advisors.

## Rollback durante una migración

Cada migración usa una transacción. Si una sentencia falla antes del `COMMIT`, PostgreSQL revierte esa migración. No se debe continuar manualmente desde la mitad.

Si falla una migración de la secuencia, detener la promoción y no ejecutar las siguientes hasta determinar la causa.

## Rollback después del COMMIT

### Opción preferida

Si aparece una regresión grave después de la promoción, restaurar el backup/PITR tomado inmediatamente antes. Es la forma más fiel de regresar a un estado conocido.

### Rollback lógico de emergencia

Solo si restaurar el backup no es viable y existe un snapshot exacto del estado anterior:

1. poner el cliente/servicio afectado en mantenimiento;
2. restaurar definiciones anteriores de RPC y helpers desde el snapshot;
3. restaurar grants anteriores;
4. restaurar políticas RLS anteriores solo si resulta imprescindible para recuperar disponibilidad;
5. restaurar índices y triggers modificados;
6. ejecutar pruebas de autorización antes de reabrir servicio.

**Advertencia:** el estado anterior contiene políticas permisivas conocidas. Un rollback lógico completo puede reintroducir vulnerabilidades. Si eso ocurriera, la aplicación no debe considerarse segura ni apta para producción.

## Lo que REP-001 no toca

- no copia ni modifica datos de usuarios de producción;
- no cambia la aplicación Flutter;
- no modifica Firebase;
- no implementa el borrado total de cuenta de REP-003;
- no impone todavía el consentimiento de contacto para abrir conversación de REP-004;
- no despliega Edge Functions.

## Criterio para abortar promoción

Abortar y no continuar si:

- el snapshot de producción ya no coincide con el utilizado para preparar `009–012`;
- no existe backup recuperable;
- una prueba A/B/C falla;
- reaparecen políticas universales en tablas críticas;
- `anon` obtiene acceso directo a tablas de usuario;
- un helper interno vuelve a quedar ejecutable por `anon`;
- Storage permite lectura/escritura a un no participante;
- `accept_contact_request()` deja de crear los dos contactos recíprocos mediante el trigger privado.

## Staging

`InclusiChat-Staging` puede reconstruirse sin afectar producción. Los datos A/B/C son ficticios. El objeto de Storage creado para probar RLS no contiene información real y debe eliminarse mediante Storage API o al retirar el entorno staging; no se debe desactivar `storage.protect_delete()` para borrarlo por SQL.
