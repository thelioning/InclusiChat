# REP-001 — Reconciliación del esquema desplegado

**Estado:** `CORREGIDO Y VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE DE AUTORIZACIÓN`  
**Fecha:** 2026-08-24  
**Base GitHub:** `196d5356c7df93d74e061622cd81d1c280b4d32c` + ruta de reparación  
**Rama:** `repair/rep-001-security-baseline`

## 1. Regla de seguridad

No se aplicó ningún DDL correctivo a `InclusiChat` producción. Toda escritura y prueba de REP-001 se ejecutó en el proyecto aislado `InclusiChat-Staging`.

El staging usa datos ficticios y no contiene datos personales copiados desde producción.

## 2. Estado real encontrado en producción

La inspección de producción fue exclusivamente de lectura. Se confirmó un esquema parcialmente migrado y con drift:

- políticas heredadas `FOR ALL` con `USING (true)`/`WITH CHECK (true)` en tablas críticas;
- lectura universal heredada en `message_receipts`;
- `profiles_select_policy` demasiado amplia;
- múltiples funciones `SECURITY DEFINER` expuestas a `anon` y/o `authenticated`;
- funciones con `search_path=public` o mutable;
- `citext` instalado en el esquema expuesto `public`;
- `contact_requests` sin `updated_at`, aunque varias RPC intentaban escribirla;
- `delete_message_for_me(uuid)` y `delete_user_account()` ausentes pese a aparecer en snapshots/migraciones históricas;
- partes de migraciones posteriores ya presentes (`device_push_tokens`, `chat-media`, `cleared_at`, `metadata`, índice de señales), confirmando drift.

## 3. Staging reproducido desde el estado desplegado

Se creó `InclusiChat-Staging` como proyecto Supabase separado. El baseline técnico de prueba está en:

`docs/repair/staging/REP-001_STAGING_BASELINE.sql`

Ese archivo reproduce deliberadamente el estado desplegado para probar la reparación y está marcado **STAGING ONLY / DO NOT APPLY TO PRODUCTION**.

Después del baseline se verificó:

- 47 políticas públicas;
- 7 políticas con `USING (true)`;
- `delete_user_account()` ausente;
- `delete_message_for_me(uuid)` ausente;
- bucket `chat-media` presente.

## 4. Migraciones correctivas creadas

### `20260823_009_deployed_schema_reconciliation.sql`

- añade `contact_requests.updated_at`;
- mueve `citext` a `extensions`;
- crea esquema no expuesto `private`;
- mueve helpers internos y trigger functions fuera de `public`;
- fija `search_path`;
- endurece grants de funciones;
- crea `delete_message_for_me(uuid)`;
- elimina políticas universales heredadas;
- reconstruye RLS de conversaciones, participantes, mensajes, recibos, reacciones, adjuntos y Storage;
- elimina acceso directo de `anon` a tablas públicas de la aplicación.

### `20260823_010_private_helper_rebinding.sql`

Staging detectó que `private.can_send_to_conversation()` todavía referenciaba al antiguo helper público. La `010`:

- rebindea el helper al esquema `private`;
- conserva `search_path=''` y grants mínimos;
- añade trigger `contact_requests_set_updated_at`.

### `20260824_011_contact_response_invoker.sql`

El Security Advisor mostró que `accept_contact_request` y `reject_contact_request` podían operar con privilegios del caller. La `011`:

- convierte ambas RPC a `SECURITY INVOKER`;
- elimina `EXECUTE` de `public` y `anon`;
- mantiene `EXECUTE` solo para `authenticated`.

### `20260824_012_accept_contact_request_via_trigger.sql`

La prueba posterior a `011` encontró una regresión real: `accept_contact_request()` intentaba insertar directamente los dos contactos recíprocos y RLS lo bloqueaba al ejecutarse como caller.

La `012` corrige el diseño:

- `accept_contact_request()` solo cambia la solicitud `pending → accepted`;
- el trigger privado `private.create_contacts_after_acceptance()` crea los dos contactos recíprocos;
- la RPC permanece `SECURITY INVOKER`.

Este defecto fue detectado y corregido antes de tocar producción.

## 5. Migraciones aplicadas en staging

El historial de staging registra, en orden:

1. `rep_001_staging_deployed_baseline`
2. `deployed_schema_reconciliation`
3. `private_helper_rebinding`
4. `contact_response_invoker`
5. `accept_contact_request_via_trigger`

Todas aplicaron correctamente.

## 6. Resultado RLS después de la reparación

Después de `009–012`:

- políticas públicas con `USING (true)`: **0**;
- políticas públicas con `WITH CHECK (true)`: **0**;
- helpers `private.*` no son ejecutables por `anon`;
- `anon` no tiene lectura directa de tablas de usuario;
- `accept_contact_request` y `reject_contact_request` son `SECURITY INVOKER`;
- las RPC que continúan `SECURITY DEFINER` tienen `search_path=''` y grants explícitos.

## 7. Pruebas A/B/C

Identidades ficticias:

- A = participante/emisor;
- B = participante/receptor;
- C = no participante.

### Conversaciones y mensajes

| Prueba | Resultado |
|---|---|
| A crea conversación directa A–B | PASS |
| A envía mensaje con `sender_id=A` | PASS |
| A intenta enviar usando `sender_id=B` | PASS: rechazado `42501` |
| B lee el mensaje de A | PASS |
| C ve conversación A–B | PASS: 0 filas |
| C ve mensajes A–B | PASS: 0 filas |
| C intenta insertar en A–B | PASS: rechazado `42501` |

### Recibos

| Prueba | Resultado |
|---|---|
| B registra `read` para mensaje de A | PASS |
| A intenta crear recibo con `user_id=B` | PASS: rechazado `42501` |
| C consulta recibos A–B | PASS: 0 filas |

### Storage privado

| Prueba | Resultado |
|---|---|
| A ve el objeto A–B | PASS: 1 fila |
| B ve el objeto A–B | PASS: 1 fila |
| C intenta leerlo | PASS: 0 filas |
| C intenta insertar en el path A–B | PASS: rechazado `42501` |

### Contactos

| Prueba | Resultado |
|---|---|
| A envía solicitud | PASS |
| receptor rechaza como usuario normal | PASS |
| receptor acepta como usuario normal tras `012` | PASS |
| `updated_at` y `responded_at` se actualizan | PASS |
| trigger privado crea exactamente 2 contactos recíprocos | PASS |

### Eliminación privada de mensaje

| Prueba | Resultado |
|---|---|
| B ejecuta `delete_message_for_me()` | PASS |
| `metadata.deleted_for` contiene a B | PASS |

## 8. Idempotencia de conversaciones directas

La función versionada `create_direct_conversation()` usa `pg_advisory_xact_lock(hashtextextended(pair_key,0))` y el esquema tiene unicidad sobre `direct_pair_key`.

En staging se comprobó además que el par de prueba A–B tiene **una sola conversación persistida** para su `direct_pair_key`.

**Limitación:** la integración bloqueó una repetición adicional de la RPC bajo rol JWT simulado y no se ejecutó una carrera verdaderamente simultánea desde dos clientes externos. La prueba de concurrencia real queda en REP-010. La protección estructural contra duplicados sí está presente.

## 9. Security Advisor posterior

Los avisos originales sobre políticas universales, helpers internos y `search_path` fueron eliminados.

Después de `011/012`, desaparecieron también los avisos para:

- `accept_contact_request`;
- `reject_contact_request`.

Permanecen avisos sobre RPC públicas `SECURITY DEFINER` que requieren revisión explícita como superficie API:

- `check_username_available` — disponible también para `anon`, devuelve solo disponibilidad;
- `search_profiles`;
- `send_contact_request`;
- `create_direct_conversation`;
- `delete_message_for_me`.

No se consideran automáticamente vulnerabilidades cerradas: deben conservar validaciones internas, `search_path=''` y grants mínimos, y seguir bajo pruebas de integración.

## 10. Performance Advisor

Se registraron advertencias no bloqueantes de seguridad:

- varias RLS pueden optimizar `auth.uid()` a `(select auth.uid())`;
- faltan índices de FK en `conversations.created_by`, `message_reactions.user_id` y `messages.reply_to_message_id`;
- los avisos de índices no usados en staging no son concluyentes por el bajo tráfico del entorno.

Estas mejoras quedan para la fase de rendimiento y no se mezclan con el cierre P0 de REP-001.

## 11. Reproducibilidad para código libre

Las migraciones históricas no construyen InclusiChat desde una base Supabase completamente vacía. Para un proyecto de código libre esto debe corregirse antes de `v1.6.0`.

Después de cerrar los P0 de base de datos se debe generar y probar un baseline/squash seguro y reproducible para instalaciones nuevas dentro de REP-009/REP-010.

`REP-001_STAGING_BASELINE.sql` no es ese baseline: reproduce deliberadamente el estado inseguro previo para pruebas.

## 12. Rollback

Ver:

`docs/repair/rollback/REP-001_ROLLBACK.md`

La promoción requiere backup verificable y snapshot inmediatamente anterior.

## 13. Veredicto

### Staging

`CORREGIDO — VERIFICADO`

Los criterios de aislamiento RLS, `sender_id`, recibos, Storage, RPC de contacto y borrado privado de mensaje pasaron.

### Producción

`NO MODIFICADA — PROMOCIÓN PENDIENTE`

Si se autoriza posteriormente, la secuencia validada es estrictamente:

`009 → 010 → 011 → 012`

No se debe promover una secuencia parcial.
