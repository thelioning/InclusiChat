# InclusiChat — Estado vivo de reparación

Este archivo indica el punto exacto de la ruta. Debe leerse junto con `REPAIR_ROADMAP.md`.

**Última actualización:** 2026-08-23  
**Base auditada:** `196d5356c7df93d74e061622cd81d1c280b4d32c`  
**Rama activa:** `repair/rep-001-security-baseline`

## Estado actual

| Punto | Estado | Evidencia / nota |
|---|---|---|
| REP-001 | `VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE` | `docs/repair/evidence/REP-001_SCHEMA_RECONCILIATION.md` |
| REP-002 | `P0 — ABIERTO` | No iniciar como cierre hasta resolver/promover REP-001 |
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

REP-001 pasó sus pruebas de comportamiento en `InclusiChat-Staging`.

**No está cerrado en producción.** El Supabase activo conserva todavía el estado inseguro original hasta una promoción controlada.

Antes de promover:

1. verificar backup recuperable;
2. repetir snapshot de producción y comprobar que no hubo drift desde la inspección;
3. revisar `docs/repair/rollback/REP-001_ROLLBACK.md`;
4. obtener autorización explícita del propietario;
5. aplicar únicamente las migraciones `009` y `010` en orden;
6. repetir pruebas y Advisors inmediatamente después.

## Hallazgos nuevos incorporados al backlog

Durante REP-001 aparecieron tres requisitos que no deben perderse:

1. **Auth:** `Leaked Password Protection` está deshabilitado. Debe resolverse antes del gate de producción final.
2. **Rendimiento DB:** el Performance Advisor detectó optimización de RLS (`(select auth.uid())`) y tres FK sin índice. Se tratará en la fase de rendimiento, sin mezclarlo con el cierre de seguridad REP-001.
3. **Código libre / reproducibilidad:** las migraciones actuales no construyen una base completa desde cero. Después de cerrar los P0 de base de datos se debe generar y probar un baseline/squash seguro para instalaciones nuevas dentro del trabajo de CI/E2E de REP-009/REP-010.

## Regla de producción

Ningún desarrollador o agente debe interpretar `VERIFICADO EN STAGING` como permiso para ejecutar DDL en producción.

La promoción requiere autorización explícita y evidencia de backup.
