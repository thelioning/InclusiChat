# REP-001 — Reconciliación del esquema desplegado

**Estado:** `CORREGIDO Y VERIFICADO EN STAGING — PRODUCCIÓN PENDIENTE DE AUTORIZACIÓN`  
**Fecha:** 2026-08-23  
**Base GitHub:** `196d5356c7df93d74e061622cd81d1c280b4d32c` + ruta de reparación  
**Rama:** `repair/rep-001-security-baseline`

## 1. Regla de seguridad

No se aplicó ningún DDL correctivo a `InclusiChat` producción. Toda escritura y prueba de REP-001 se ejecutó en el proyecto aislado `InclusiChat-Staging`.

El baseline de staging no contiene datos personales ni datos copiados desde producción.

## 2. Estado real encontrado en producción

La inspección de producción fue exclusivamente de lectura. Se confirmó un esquema parcialmente migrado y no reproducible simplemente ejecutando `001–008` a ciegas.

Hallazgos principales:

- políticas heredadas `FOR ALL` con `USING (true)`/`WITH CHECK (true)` en `contacts`, `contact_requests`, `conversation_participants`, `conversations` y `messages`;
- lectura universal heredada en `message_receipts`;
- `profiles_select_policy` permitía lectura amplia;
- múltiples funciones `SECURITY DEFINER` permanecían ejecutables por `anon` y/o `authenticated`;
- varias funciones tenían `search_path=public` o mutable;
- `citext` estaba instalado en el esquema expuesto `public`;
- `contact_requests` no tenía columna `updated_at`, aunque `send_contact_request`, `accept_contact_request` y `reject_contact_request` intentaban escribirla;
- `delete_message_for_me(uuid)` no estaba desplegada aunque la migración `001` la define;
- `delete_user_account()` tampoco estaba desplegada; su rediseño corresponde a REP-003;
- existían partes de migraciones posteriores (`device_push_tokens`, `chat-media`, `cleared_at`, `metadata`, índice de señales), confirmando drift del esquema.

## 3. Staging aislado

Se creó `InclusiChat-Staging` como proyecto Supabase separado. El proyecto activo no fue clonado con datos.

Se añadió al repositorio:

- `docs/repair/staging/REP-001_STAGING_BASELINE.sql`

Ese archivo reproduce de forma intencional la estructura desplegada y sus defectos para probar la reparación. Está marcado **STAGING ONLY / DO NOT APPLY TO PRODUCTION**.

Después de aplicar el baseline se verificó:

- 47 políticas públicas;
- 7 políticas con `USING (true)`;
- `delete_user_account()` ausente;
- `delete_message_for_me(uuid)` ausente;
- bucket `chat-media` presente.

## 4. Migraciones correctivas creadas

### `20260823_009_deployed_schema_reconciliation.sql`

Corrige el drift observado:

- añade `contact_requests.updated_at`;
- mueve `citext` a `extensions`;
- crea esquema no expuesto `private`;
- mueve helpers internos y trigger functions fuera de `public`;
- fija `search_path`;
- elimina `EXECUTE` anónimo de helpers internos;
- endurece RPC públicas y sus grants;
- crea `delete_message_for_me(uuid)`;
- elimina políticas universales heredadas;
- reconstruye RLS de conversaciones, participantes, mensajes, recibos, reacciones, adjuntos y Storage;
- elimina acceso directo de `anon` a tablas públicas de la aplicación;
- reconcilia índices faltantes/diferentes.

### `20260823_010_private_helper_rebinding.sql`

Staging detectó un defecto de runtime después de mover helpers: `can_send_to_conversation()` todavía referenciaba `public.is_conversation_member()`.

La migración `010`:

- rebindea `private.can_send_to_conversation()` a `private.is_conversation_member()`;
- conserva `search_path=''` y grants mínimos;
- añade trigger `contact_requests_set_updated_at`.

Este fallo fue detectado antes de tocar producción, que es precisamente el objetivo de staging.

## 5. Migraciones aplicadas en staging

Supabase registra:

1. `rep_001_staging_deployed_baseline`
2. `deployed_schema_reconciliation`
3. `private_helper_rebinding`

Las tres se aplicaron correctamente en el entorno aislado.

## 6. Resultado RLS después de la reparación

Después de `009` + `010`:

- políticas públicas: 36;
- políticas públicas con `USING (true)`: **0**;
- políticas públicas con `WITH CHECK (true)`: **0**;
- helpers internos `private.*`: no ejecutables por `anon`;
- `anon` no tiene acceso directo a `profiles`;
- `check_username_available(text)` continúa disponible para el flujo pre-registro de la app.

## 7. Pruebas A/B/C ejecutadas

Identidades ficticias:

- A = usuario participante/emisor;
- B = usuario participante/receptor;
- C = usuario no participante.

No son usuarios reales y fueron eliminados al terminar las pruebas.

### Conversaciones y mensajes

| Prueba | Resultado |
|---|---|
| A crea conversación directa A–B | PASS |
| A envía mensaje con `sender_id=A` | PASS |
| A intenta enviar usando `sender_id=B` | PASS: rechazado `42501` por RLS |
| B consulta el mensaje de A | PASS: visible |
| C consulta conversación A–B | PASS: 0 filas |
| C consulta mensajes A–B | PASS: 0 filas |
| C intenta insertar en A–B | PASS: rechazado `42501` |

### Recibos

| Prueba | Resultado |
|---|---|
| B registra `read` para mensaje enviado por A | PASS |
| A intenta crear recibo con `user_id=B` | PASS: rechazado `42501` |

### Storage privado

Se insertó un objeto ficticio en `chat-media` bajo el path de la conversación A–B.

| Prueba | Resultado |
|---|---|
| B, participante, puede leer el objeto | PASS: 1 fila |
| C, no participante, intenta leerlo | PASS: 0 filas |
| C intenta insertar dentro del path A–B | PASS: rechazado `42501` |

### RPC de contactos

| Prueba | Resultado |
|---|---|
| A envía solicitud a C | PASS |
| A intenta aceptar su propia solicitud en nombre de C | PASS: RPC devuelve `false` |
| C acepta la solicitud | PASS: RPC devuelve `true` |
| `updated_at` y `responded_at` se actualizan | PASS |

### Eliminación por usuario

| Prueba | Resultado |
|---|---|
| B ejecuta `delete_message_for_me()` | PASS: `true` |
| `metadata.deleted_for` contiene solo a B | PASS |
| A continúa viendo el mensaje compartido | PASS: 1 fila |
| B ejecuta `clear_conversation_for_me()` | PASS |
| `cleared_at` cambia solo para B | PASS |

### Superficie anónima

| Prueba | Resultado |
|---|---|
| `anon` ejecuta `check_username_available()` | PASS |
| `anon` intenta `SELECT` directo sobre `profiles` | PASS: `permission denied` |

## 8. Idempotencia y concurrencia

Dos llamadas independientes consecutivas a `create_direct_conversation()` para el mismo par A–C devolvieron exactamente el mismo `conversation_id`.

La función usa `pg_advisory_xact_lock` y existe unicidad de `direct_pair_key`, por lo que la protección estructural contra duplicados está presente.

**Limitación:** no se ejecutó aún una carrera verdaderamente simultánea desde dos clientes físicos/sesiones externas. Esa prueba queda obligatoriamente dentro de REP-010 de integración/E2E. No se declara esa prueba como realizada.

## 9. Advisors posteriores

### Security Advisor

Los avisos peligrosos originales de helpers internos, `search_path` mutable y `citext` en `public` desaparecieron.

Permanecen avisos `SECURITY DEFINER` para RPC públicas que son intencionalmente endpoints de la aplicación:

- `check_username_available`;
- `search_profiles`;
- `send_contact_request`;
- `accept_contact_request`;
- `reject_contact_request`;
- `create_direct_conversation`;
- `delete_message_for_me`.

Se mantienen porque requieren una operación controlada que no puede delegarse a acceso directo de tablas. Todas tienen `search_path=''`, grants explícitos y validación de identidad/alcance. `check_username_available` es la única habilitada para `anon`, porque el cliente la necesita antes de crear la cuenta y solo devuelve un booleano de disponibilidad.

También permanece `Leaked Password Protection Disabled`. La conexión Supabase disponible no expone una acción para cambiar esa configuración de Auth. Debe habilitarse antes del gate final de producción y volver a ejecutar el Advisor.

### Performance Advisor

Se detectaron optimizaciones no bloqueantes de seguridad:

- varias RLS pueden envolver `auth.uid()` como `(select auth.uid())` para evitar reevaluación por fila;
- faltan índices de FK en `conversations.created_by`, `message_reactions.user_id` y `messages.reply_to_message_id`;
- los avisos `unused_index` de staging no son concluyentes porque el entorno tiene muy poco tráfico.

Estas optimizaciones quedan registradas para la fase P2/optimización y no justifican modificar más REP-001 sin medir impacto.

## 10. Hallazgo de reproducibilidad para código libre

El repositorio no contiene una migración inicial completa capaz de construir InclusiChat desde una base Supabase vacía; `001–008` son incrementales y los `supabase_schema.sql` históricos están explícitamente declarados como snapshots forenses que no deben aplicarse.

Para un proyecto de código libre esto es un blocker de reproducibilidad: un colaborador nuevo debe poder levantar la base desde cero sin copiar un esquema de producción.

**Acción obligatoria antes de v1.6.0:** después de cerrar los P0 de base de datos (especialmente REP-003 y REP-004), generar un baseline/squash seguro y reproducible para instalaciones nuevas y probarlo desde un proyecto Supabase vacío dentro del flujo de REP-009/REP-010.

El archivo `REP-001_STAGING_BASELINE.sql` NO cumple esa función porque reproduce deliberadamente el estado inseguro previo solo para pruebas.

## 11. Limpieza de pruebas

Los usuarios ficticios A/B/C y las filas normales asociadas fueron eliminados de staging.

Supabase impide eliminar objetos de `storage.objects` directamente por SQL. El objeto ficticio usado para la prueba de Storage permanece en staging y no contiene información real. Debe eliminarse mediante Storage API o al retirar el proyecto staging; no se desactivó ni eludió la protección `storage.protect_delete()`.

## 12. Rollback

Ver:

`docs/repair/rollback/REP-001_ROLLBACK.md`

Ninguna promoción a producción debe ocurrir sin backup verificable y snapshot inmediatamente anterior.

## 13. Veredicto REP-001

### Staging

`CORREGIDO — VERIFICADO`

Los criterios de aislamiento RLS, `sender_id`, recibos, Storage, RPC y eliminación por usuario pasaron en staging.

### Producción

`NO MODIFICADA — PROMOCIÓN PENDIENTE`

Las políticas inseguras siguen existiendo en producción hasta que `009` y `010` sean promovidas de forma controlada.

**Siguiente decisión:** verificar backup/snapshot de producción y obtener autorización explícita antes de ejecutar cualquier DDL allí.
