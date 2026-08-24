# REP-001 — Reverificación adicional de staging (2026-08-24)

Esta nota complementa `REP-001_SCHEMA_RECONCILIATION.md` y registra una reverificación ejecutada antes de avanzar a REP-002.

## Alcance

Solo `InclusiChat-Staging`. Producción no fue modificada.

## Resultados repetidos

- A no puede insertar un mensaje con `sender_id=B`: rechazado con `42501` por RLS.
- C no puede insertar mensajes en la conversación A–B: rechazado con `42501`.
- B puede registrar su propio recibo de lectura.
- C no puede registrar un recibo para un mensaje A–B: rechazado con `42501`.
- A no puede crear un recibo con `user_id=B`: rechazado con `42501`.
- Storage `chat-media`, sobre el objeto ficticio de REP-001:
  - A ve 1 objeto;
  - B ve 1 objeto;
  - C ve 0 objetos.
- `accept_contact_request` y `reject_contact_request` están desplegadas como `SECURITY INVOKER`, `search_path=''`, sin `EXECUTE` para `anon` y con `EXECUTE` para `authenticated`.
- Security Advisor ya no reporta las políticas universales ni los helpers internos originales. Permanecen advertencias de RPC públicas `SECURITY DEFINER` que están registradas para revisión explícita y no deben interpretarse como resueltas por silencio.
- Performance Advisor mantiene recomendaciones de optimización de RLS e índices; se registran para la fase de rendimiento.

## Limitación del entorno

El runtime usado para la reparación no tiene resolución DNS saliente hacia el endpoint público de Supabase. Por ello no se repitió desde este runtime una prueba HTTP externa Auth/Storage. Las pruebas SQL/RLS sobre el proyecto staging sí se ejecutaron y el objeto de Storage existente fue consultado bajo identidades simuladas `authenticated` A/B/C.

## Estado

`REP-001: VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE DE AUTORIZACIÓN`

No promover `009 → 010 → 011 → 012` a producción sin backup, snapshot de drift, rollback revisado y autorización explícita.
