# InclusiChat — Estado vivo de reparación

Este archivo indica el punto exacto de la ruta. Debe leerse junto con `REPAIR_ROADMAP.md`.

**Última actualización:** 2026-08-24  
**Base auditada:** `196d5356c7df93d74e061622cd81d1c280b4d32c`  
**Rama activa:** `repair/rep-002-fcm-lifecycle`

## Estado actual

| Punto | Estado | Evidencia / nota |
|---|---|---|
| REP-001 | `VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE` | `docs/repair/evidence/REP-001_SCHEMA_RECONCILIATION.md` |
| REP-002 | `CÓDIGO CORREGIDO — CI/DISPOSITIVO PENDIENTES` | `docs/repair/evidence/REP-002_FCM_TOKEN_LIFECYCLE.md` |
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

## Gate REP-001

REP-001 pasó las pruebas de comportamiento en `InclusiChat-Staging`, pero producción no ha recibido DDL de esta reparación.

La secuencia validada de promoción sigue siendo:

`009 → 010 → 011 → 012`

Ningún agente debe promoverla sin backup, snapshot sin drift y autorización explícita.

## Trabajo actual — REP-002

La corrección de ciclo de vida FCM está implementada en la rama activa:

- el dispositivo conserva de forma segura qué usuario posee el token registrado;
- logout elimina solo el token exacto del dispositivo actual;
- logout invalida además el token en Firebase;
- las subscriptions se cancelan y `_initializedUserId` se limpia;
- cambio inesperado de cuenta fuerza token nuevo;
- el payload de llamada lleva `receiver_id`;
- foreground/background descartan una llamada que no corresponda al propietario local;
- `AuthService.signOut()` centraliza el cleanup;
- `send-call-notification` con `receiver_id` está desplegada únicamente en staging.

### Gate pendiente de REP-002

No marcar `CERRADO` hasta completar:

1. CI: `dart format`, `flutter analyze` y `flutter test` verdes;
2. teléfono T1: login A → logout → login B;
3. comprobar backend: token A/T1 eliminado y token B/T1 registrado;
4. T1 no recibe llamadas destinadas a A después del logout;
5. T1 sí recibe llamadas destinadas a B;
6. A con dos dispositivos: logout T1 no elimina token T2;
7. comprobar rotación de token;
8. validar background, app terminada y pantalla bloqueada.

## Hallazgos incorporados al backlog

1. **Rendimiento DB:** optimización de RLS con `(select auth.uid())` y tres FK sin índice.
2. **Código libre / reproducibilidad:** antes de `v1.6.0` debe existir un baseline/squash reproducible para una instalación Supabase nueva.
3. **RPC públicas:** mantener revisión explícita de toda RPC `SECURITY DEFINER` como superficie API.

## Regla de producción

`VERIFICADO EN STAGING` o `CÓDIGO CORREGIDO` nunca equivalen a permiso de producción. Toda promoción requiere sus gates y autorización explícita correspondiente.
