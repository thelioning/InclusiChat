# REP-001 — Reconciliación del esquema desplegado

**Estado:** `EN PROGRESO — STAGING PENDIENTE`  
**Fecha de inspección:** 2026-08-23  
**Base GitHub:** `196d5356c7df93d74e061622cd81d1c280b4d32c` + ruta de reparación  
**Regla:** no aplicar DDL correctivo directamente al proyecto activo hasta validar primero en un entorno staging aislado.

## 1. Objetivo

REP-001 exige comprobar que el esquema autoritativo de `supabase/migrations/` puede llevar el entorno desplegado a un estado seguro y coherente, con pruebas reales de RLS, Storage y RPC antes de promover cambios a producción.

## 2. Restricción encontrada

Se intentó crear una Development Branch de Supabase para usarla como staging. Supabase rechazó la operación porque Branching requiere plan Pro o superior.

No se creó una rama de Supabase y no se ejecutó ninguna modificación DDL sobre el proyecto activo.

La alternativa segura es usar un proyecto Supabase independiente como staging o disponer de un plan que permita Branching. No se debe sustituir staging por pruebas destructivas sobre producción.

## 3. Snapshot del esquema activo

La inspección se realizó mediante consultas de solo lectura.

### 3.1 Estado parcial de migraciones

El esquema desplegado no coincide limpiamente con un punto único de las migraciones `001` a `008`.

Se confirmó:

- existen conversaciones con `direct_pair_key`;
- no existen valores `direct_pair_key` duplicados en el snapshot inspeccionado;
- existe la tabla `device_push_tokens` y contiene filas;
- existe el bucket privado `chat-media`;
- existe `conversation_participants.cleared_at`;
- existe `messages.metadata`;
- existe `messages_call_signal_lookup_idx`;
- NO existe `conversations_direct_pair_key_uidx`.

Esto demuestra un estado parcialmente migrado: elementos de migraciones posteriores están presentes mientras una pieza de la migración de seguridad inicial sigue ausente.

**Conclusión:** no aplicar `001–008` a ciegas. Primero debe reconciliarse el estado real y comprobar idempotencia/compatibilidad en staging.

## 4. Hallazgo crítico: políticas RLS heredadas permisivas

En el esquema activo coexisten políticas específicas con políticas antiguas universales. Se observaron políticas `FOR ALL` con `USING (true)` y `WITH CHECK (true)` en tablas sensibles, incluyendo:

- `contacts_access_policy`;
- `contact_requests_access_policy`;
- `conversation_participants_access_policy`;
- `conversations_access_policy`;
- `messages_access_policy`.

También permanece una política de recibos con lectura universal.

Las políticas permisivas de PostgreSQL pueden combinarse mediante OR. Por tanto, una política universal puede neutralizar las restricciones de otra política más estricta.

**Impacto:** el hecho de que existan políticas nuevas seguras no demuestra que RLS esté realmente cerrada mientras las políticas heredadas permisivas continúen activas.

**Severidad:** `P0 / CRÍTICO PARA RELEASE`.

## 5. Hallazgo crítico: funciones SECURITY DEFINER expuestas

El asesor de seguridad y el snapshot de privilegios confirmaron varias funciones `SECURITY DEFINER` ejecutables por `anon` y/o `authenticated` y, en varios casos, con `search_path=public` o sin `search_path` fijado.

Entre las funciones que requieren reconciliación se encuentran:

- `accept_contact_request(uuid)`;
- `can_send_to_conversation(uuid, uuid)`;
- `create_direct_conversation(uuid)`;
- `handle_new_user()`;
- `is_conversation_admin(uuid, uuid)`;
- `is_conversation_member(uuid, uuid)`;
- `is_conversation_participant(uuid, uuid)`;
- `reject_contact_request(uuid)`;
- `search_profiles(text)`;
- `send_contact_request(text)`;
- `update_conversation_last_activity()`;
- funciones trigger auxiliares observadas por el asesor.

No todas estas funciones deben necesariamente convertirse a `SECURITY INVOKER`: algunas pueden necesitar privilegios elevados por diseño. La reparación correcta es revisar caso por caso, fijar `search_path`, revocar `EXECUTE` de `PUBLIC/anon` cuando no sea una RPC pública intencional y conceder solo los roles necesarios.

## 6. Otros avisos de seguridad detectados

El asesor de Supabase también reportó:

- funciones con `search_path` mutable;
- extensión `citext` instalada en `public`;
- protección contra contraseñas filtradas deshabilitada.

Estos avisos se registran para tratamiento posterior. REP-001 prioriza primero RLS, RPCs y coherencia del esquema. La configuración de Auth se incorporará al gate de seguridad antes de release.

## 7. Diferencia frente a `20260820_001_security_baseline.sql`

La migración `001` ya intenta eliminar varias políticas universales y crear políticas por membresía, pero el snapshot activo demuestra que el despliegue real no refleja completamente ese resultado.

Además, el entorno contiene políticas y funciones con nombres/definiciones que no están representados por completo en el snapshot histórico del repositorio. Esto obliga a preparar una reconciliación contra el esquema desplegado real en lugar de asumir que la base parte del SQL histórico.

## 8. Próximo paso obligatorio

Antes de modificar producción:

1. crear un proyecto staging independiente o habilitar Branching;
2. reproducir en staging el esquema necesario;
3. aplicar las migraciones autoritativas en orden;
4. preparar una migración de reconciliación para políticas/grants heredados que no queden cubiertos;
5. ejecutar asesores de seguridad y rendimiento;
6. crear usuarios de prueba A, B y C;
7. verificar aislamiento RLS, `sender_id`, recibos, Storage y RPCs;
8. documentar rollback/promoción;
9. solo después evaluar promoción a producción.

## 9. Criterio de cierre de REP-001

REP-001 NO puede marcarse `RESUELTO` todavía.

Solo se cerrará cuando exista evidencia de que:

- A no puede leer o escribir conversaciones donde no participa;
- A no puede falsificar mensajes como B;
- A no puede crear/actualizar recibos como B;
- un no participante no puede leer objetos de `chat-media`;
- ninguna política heredada universal mantiene abiertas las tablas críticas;
- las RPC privilegiadas tienen privilegios mínimos y `search_path` seguro;
- las migraciones/reconciliación se aplican sin errores en staging desde un estado conocido;
- los asesores posteriores no muestran advertencias de seguridad de severidad incompatible con release.

## 10. Evidencia de esta iteración

- Proyecto Supabase activo inspeccionado exclusivamente mediante lectura.
- Intento de Development Branch rechazado por limitación de plan; sin cambios aplicados.
- Snapshot de políticas RLS obtenido.
- Snapshot de columnas/índices/bucket/token table obtenido.
- Snapshot de privilegios de RPC obtenido.
- Supabase Security Advisor ejecutado.
- Rama GitHub de trabajo: `repair/rep-001-security-baseline`.

**Riesgo residual:** ALTO hasta que el esquema sea saneado y probado en staging.