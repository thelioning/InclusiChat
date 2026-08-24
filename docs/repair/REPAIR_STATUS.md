# InclusiChat — Estado vivo de reparación

Este archivo indica el punto exacto de la ruta. Debe leerse junto con `REPAIR_ROADMAP.md`.

**Última actualización:** 2026-08-24  
**Base auditada:** `196d5356c7df93d74e061622cd81d1c280b4d32c`  
**Rama activa:** `repair/rep-001-security-baseline`

## Estado actual

| Punto | Estado | Evidencia / nota |
|---|---|---|
| REP-001 | `VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE` | `docs/repair/evidence/REP-001_SCHEMA_RECONCILIATION.md` |
| REP-002 | `P0 — ABIERTO` | Ciclo de vida del token FCM |
| REP-003 | `P0 — ABIERTO` | Eliminación total de cuenta + Storage |
| REP-004 | `P0 — ABIERTO` | Consentimiento de contacto impuesto por servidor |
| REP-005 | `P0 — ABIERTO` | Firma/versionado/migración de instalaciones |
| REP-006 | `P1 — ABIERTO` | Ciclo completo de llamada push |
| REP-007 | `P1 — ABIERTO` | Unificar notificación nativa |
| REP-008 | `P1 — DECISIÓN REQUERIDA` | Llamadas reales o deshabilitadas en producción |
| REP-009 | `P1 — ABIERTO` | CI reproducible |
| REP-010 | `P1 — ABIERTO` | Integración/E2E real |
| REP-011 | `P2 — ABIERTO` | Polling/eventos |
| REP-012 | `P2 — ABIERTO` | Historial de llamadas |
| REP-013 | `P2 — ABIERTO` | Código/señalización legado |
| REP-014 | `P2 — ABIERTO` | Observabilidad/errores silenciosos |
| REP-015 | `P2 — ABIERTO` | Medios históricos externos |
| REP-016 | `P3 — ABIERTO` | Limpieza de repositorio |
| REP-017 | `P3 — ABIERTO` | Textos/versión/estado del producto |

## Gate actual

REP-001 pasó las pruebas de comportamiento en `InclusiChat-Staging`.

**No está cerrado en producción.** El Supabase activo no ha recibido DDL de esta reparación.

La secuencia correctiva validada en staging es:

1. `20260823_009_deployed_schema_reconciliation.sql`
2. `20260823_010_private_helper_rebinding.sql`
3. `20260824_011_contact_response_invoker.sql`
4. `20260824_012_accept_contact_request_via_trigger.sql`

Las cuatro deben promoverse juntas y en ese orden si más adelante se autoriza producción.

Antes de promover:

1. crear y verificar el backup manual descrito en `docs/repair/backup/FREE_PLAN_PRODUCTION_BACKUP.md`;
2. repetir snapshot de producción y comprobar que no hubo drift;
3. revisar `docs/repair/rollback/REP-001_ROLLBACK.md`;
4. obtener autorización explícita del propietario;
5. aplicar únicamente `009 → 010 → 011 → 012`;
6. repetir pruebas A/B/C y Security/Performance Advisors inmediatamente después.

## Hallazgos incorporados al backlog

1. **Rendimiento DB:** el Performance Advisor detecta optimización de RLS mediante `(select auth.uid())` y tres FK sin índice. Se tratará como optimización posterior, no mezclada con el cierre P0 de REP-001.
2. **Código libre / reproducibilidad:** las migraciones históricas `001–008` no construyen una base completa desde cero. Antes de `v1.6.0` se debe generar y probar un baseline/squash limpio para nuevas instalaciones dentro de REP-009/REP-010.
3. **RPC públicas:** tras la reconciliación, `accept_contact_request` y `reject_contact_request` ya son `SECURITY INVOKER`. Permanecen como `SECURITY DEFINER` solo RPC que requieren acceso controlado más allá de la RLS directa; deben seguir revisándose como superficie API.

## Regla de producción

Ningún desarrollador o agente debe interpretar `VERIFICADO EN STAGING` como permiso para ejecutar DDL en producción.

La promoción requiere autorización explícita, backup verificable y snapshot previo sin drift.
