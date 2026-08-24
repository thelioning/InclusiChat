# InclusiChat — Ruta obligatoria de reparación

**Base técnica:** commit `196d5356c7df93d74e061622cd81d1c280b4d32c`  
**Estado de partida:** beta técnica avanzada, no habilitada todavía para producción.  
**Objetivo:** cerrar en orden los riesgos confirmados de seguridad, datos, llamadas, distribución, pruebas y operación antes de declarar una versión release.

> Este documento es normativo. Toda reparación posterior al commit base debe respetar el orden, dependencias y criterios de cierre definidos aquí. No se debe marcar un punto como resuelto por existir código: debe existir evidencia de prueba.

## 1. Reglas de ejecución

1. Trabajar en ramas separadas; no reparar directamente sobre `main`.
2. Un cambio P0 o P1 debe incluir prueba específica y regresión.
3. Las migraciones se prueban primero en Supabase staging con datos representativos/anónimos.
4. Ninguna credencial, `google-services.json`, service account, keystore o secreto se versiona.
5. No se publica un APK `release` firmado con clave debug.
6. No se declara una función disponible si la UI la simula pero el transporte real no existe.
7. Los fallos no deben resolverse silenciando excepciones, desactivando RLS, eliminando validaciones o reduciendo pruebas.
8. Cada punto cerrado debe registrar: commit, prueba ejecutada, resultado y riesgo residual.

## 2. Orden de reparación

### Fase P0 — Seguridad, identidad de dispositivo y datos

Estos puntos bloquean cualquier Release Candidate.

### REP-001 — Validar y aplicar el esquema autoritativo en staging

**Problema:** las migraciones correctivas existen en `supabase/migrations`, pero el estado real de Supabase no está verificado.

**Trabajo requerido:**
- Crear o disponer de un proyecto Supabase de staging.
- Obtener un snapshot del esquema desplegado actual.
- Compararlo con las migraciones `001` a `008`.
- Resolver incompatibilidades o duplicados antes de ejecutar DDL.
- Aplicar las migraciones en orden.
- Probar RLS con al menos tres identidades: usuario A, usuario B y usuario C no participante.
- Probar Storage privado, RPCs, recibos, eliminación por usuario y creación concurrente de conversaciones.
- Documentar rollback.

**Criterio de cierre:**
- A no puede leer/escribir conversaciones de B/C donde no participa.
- Un usuario no puede falsificar `sender_id`.
- Un usuario no puede escribir recibos en nombre de otro.
- Un usuario no participante no puede obtener adjuntos privados.
- Todas las migraciones se aplican en staging desde estado conocido sin errores no explicados.

**Estado inicial:** `P0 — NO VERIFICADO`.

---

### REP-002 — Corregir el ciclo de vida del token FCM

**Problema:** el token push puede quedar asociado a una cuenta después de cerrar sesión y el servicio mantiene estado de inicialización entre usuarios del mismo dispositivo.

**Trabajo requerido:**
- Guardar localmente qué usuario posee el token registrado.
- Al cerrar sesión, eliminar del backend el token perteneciente a la sesión saliente.
- Ejecutar `PushNotificationService.reset()` antes o durante el cierre de sesión.
- En cambio A → B, forzar registro del token para B.
- Manejar rotación de token, reinstalación y token inválido.
- No borrar tokens de otros dispositivos del mismo usuario.

**Pruebas obligatorias:**
- Login A → logout → login B en el mismo teléfono.
- A deja de recibir llamadas en ese dispositivo.
- B recibe correctamente.
- Dos dispositivos de A pueden coexistir.
- Token rotado reemplaza/actualiza asociación sin duplicación peligrosa.

**Criterio de cierre:** ningún dispositivo recibe push de una cuenta que ya cerró sesión en ese dispositivo.

**Estado inicial:** `P0 — ABIERTO`.

---

### REP-003 — Hacer real la eliminación total de cuenta

**Problema:** `delete_user_account()` elimina filas, pero puede dejar imágenes, audios y documentos del usuario en Supabase Storage. También debe limpiar tokens push.

**Trabajo requerido:**
- Diseñar un flujo server-side autorizado para enumerar y borrar objetos del usuario en `chat-media`.
- Eliminar `device_push_tokens` de la cuenta.
- Borrar primero recursos que no se eliminan por FK/cascade y luego la identidad.
- Hacer la operación idempotente o recuperable si falla a mitad.
- Registrar qué elementos no pudieron borrarse y reintentar de forma segura.
- Revisar el texto de UI para que coincida exactamente con lo que realmente se elimina.

**Pruebas obligatorias:** cuenta con texto, imágenes, audio, documentos y varios tokens; tras eliminación no deben quedar objetos ni tokens atribuibles al usuario.

**Criterio de cierre:** no quedan filas ni objetos de Storage propiedad de la cuenta salvo datos que deban conservarse por obligación explícita y documentada.

**Estado inicial:** `P0 — ABIERTO`.

---

### REP-004 — Cerrar la autorización del modelo de contactos

**Problema:** la creación de conversación directa no exige actualmente una relación de contacto aceptada y el cliente mantiene fallbacks que pueden modificar solicitudes directamente.

**Decisión de producto para esta ruta:** una conversación directa nueva requiere aceptación mutua previa. Si en el futuro se desea permitir mensajes de desconocidos, debe diseñarse como función separada y explícita.

**Trabajo requerido:**
- Hacer que `create_direct_conversation()` compruebe relación aceptada/contacto mutuo.
- Separar políticas de `contact_requests`: emisor puede crear/cancelar; receptor puede aceptar/rechazar; ninguno puede apropiarse de la transición del otro.
- Eliminar fallbacks de cliente que eludan las RPC autoritativas.
- Corregir la UI de búsqueda para que tocar un resultado no inicie chat antes de aceptación.
- Evitar enumeración excesiva de perfiles y mantener `is_searchable` como condición.

**Pruebas obligatorias:** A solicita a B; A no puede aceptar por B; C no puede intervenir; antes de aceptación no se crea chat; después de aceptación sí.

**Criterio de cierre:** el servidor, no la UI, impone el consentimiento de contacto.

**Estado inicial:** `P0 — ABIERTO`.

---

### REP-005 — Resolver firma, identidad de aplicación y transición desde builds debug

**Problema:** la nueva configuración impide firmar release con debug, pero instalaciones antiguas firmadas con una clave distinta no pueden actualizarse en sitio con una nueva clave de producción.

**Trabajo requerido:**
- Crear keystore de producción fuera del repositorio.
- Definir custodia, backup y recuperación de la clave.
- Confirmar con qué certificado se firmaron los APK ya distribuidos.
- Si los APK públicos anteriores están firmados con debug y no se conservará esa firma, documentar una migración de instalación: desinstalar/reinstalar o cambiar `applicationId` antes de una adopción mayor.
- Nunca publicar una nueva producción con clave debug para conservar compatibilidad.
- Incrementar versión y build: objetivo inicial `1.6.0+<build mayor que 44>`.

**Criterio de cierre:** APK release verificable, firmado por la clave de producción prevista, instalable en dispositivo limpio y con una estrategia explícita para usuarios de builds anteriores.

**Estado inicial:** `P0 — ABIERTO`.

## 3. Fase P1 — Llamadas, CI y validación real

### REP-006 — Completar el ciclo de notificación de llamada

**Problema:** el inicio de llamada usa FCM, pero cancelar/terminar desde el emisor no tiene un push de cierre equivalente cuando el receptor está con la app terminada.

**Trabajo requerido:**
- Definir eventos server-side: `incoming_call`, `call_cancelled`, `call_accepted`, `call_rejected`, `call_ended` cuando deban cruzar estados de proceso terminado.
- Invalidar la notificación nativa cuando el emisor cuelga.
- Garantizar idempotencia por `call_id`.
- Evitar que una notificación vencida abra una pantalla de llamada activa.
- Registrar llamadas perdidas una sola vez.

**Criterio de cierre:** el receptor deja de sonar/mostrar llamada inmediatamente al cancelar, dentro de las limitaciones normales de entrega de FCM.

**Estado inicial:** `P1 — ABIERTO`.

---

### REP-007 — Unificar la infraestructura de llamada nativa

**Problema:** coexisten `flutter_callkit_incoming` y la notificación manual de `MainActivity`/`CallActionReceiver`. El receiver antiguo solo detiene sonido y no siempre actualiza el estado remoto.

**Trabajo requerido:**
- Elegir un único camino autoritativo para incoming-call UI.
- Retirar código legado que duplique timbre/notificación si ya no es necesario.
- Aceptar/rechazar siempre debe persistir el estado de llamada.
- Probar cold start, background, pantalla bloqueada y foreground.

**Criterio de cierre:** una llamada produce una sola notificación/UI y todas las acciones del sistema modifican el estado remoto correcto.

**Estado inicial:** `P1 — ABIERTO`.

---

### REP-008 — Decidir el alcance real de voz/video para la primera producción

**Situación:** la versión actual tiene señalización y UI, pero no transporte de audio/video.

**Regla de release:**
- Si los botones de llamada están visibles en producción, debe existir transporte real probado (por ejemplo WebRTC con STUN/TURN, control de audio/cámara y manejo de red).
- Si ese trabajo no está listo para `v1.6.0`, la función de llamadas debe quedar deshabilitada/oculta mediante feature flag en el build de producción.
- No se permite una UI que indique llamada conectada sin transmitir audio/video.

**E2EE:** no es requisito obligatorio de la primera producción si la aplicación no lo promete. Sí es obligatorio que ningún texto afirme E2EE hasta su implementación y auditoría.

**Criterio de cierre:** una de estas dos condiciones debe cumplirse y documentarse: `CALLS_ENABLED_AND_REAL` o `CALLS_DISABLED_IN_PRODUCTION`.

**Estado inicial:** `P1 — DECISIÓN REQUERIDA`.

---

### REP-009 — Hacer reproducible el CI con Firebase y configuración segura

**Problema:** el workflow compila Android, pero `google-services.json` no está versionado y debe generarse de forma segura en CI.

**Trabajo requerido:**
- Guardar la configuración necesaria como GitHub Secret/Environment secret.
- Crear `google-services.json` temporalmente durante el job.
- Borrarlo al finalizar.
- Mantener secrets fuera de logs y artifacts.
- Ejecutar format, analyze, tests y build desde checkout limpio.
- Añadir validación de migraciones/SQL estática y, cuando sea posible, pruebas de integración contra staging aislado.

**Criterio de cierre:** un commit limpio en la rama de release obtiene CI verde sin depender de archivos existentes en la máquina del desarrollador.

**Estado inicial:** `P1 — ABIERTO`.

---

### REP-010 — Incorporar pruebas de integración y E2E reales

**Problema:** gran parte de la suite actual verifica texto/código estáticamente.

**Trabajo requerido:**
- Pruebas multicuenta de RLS y contactos.
- Pruebas Storage con URLs firmadas y usuario no autorizado.
- Prueba de cambio de sesión A/B y tokens FCM.
- Prueba de borrado de cuenta con recursos.
- Dos dispositivos físicos para notificaciones de llamada.
- Pruebas de red: background, reconexión, timeout y latencia razonable.

**Criterio de cierre:** los flujos críticos se validan por comportamiento, no solo por presencia de cadenas en código.

**Estado inicial:** `P1 — ABIERTO`.

## 4. Fase P2 — Consumo, consistencia y mantenimiento

### REP-011 — Reducir polling y usar eventos

**Problema:** refresco del home cada 3 s, chequeo de llamada cada 1.4 s y polling de estado de llamada cada 700 ms.

**Trabajo requerido:**
- Sustituir refrescos frecuentes por Realtime/eventos donde sea confiable.
- Mantener un fallback de reconciliación con intervalo mayor, no como camino principal.
- Medir consultas por usuario/minuto antes y después.

**Criterio de cierre:** la UI sigue actualizándose correctamente con una reducción demostrable de consultas periódicas.

**Estado inicial:** `P2 — ABIERTO`.

---

### REP-012 — Corregir el modelo de historial de llamadas

**Problema:** el emisor del mensaje `end` puede interpretarse como caller aunque solo sea quien colgó.

**Trabajo requerido:**
- Persistir `caller_id` y `receiver_id` como identidad original de la llamada.
- Definir una sola fuente de historial: tabla dedicada o registros de señal con metadatos completos.
- Evitar reconstruir dirección basándose en quién emitió `end`.

**Criterio de cierre:** entrante/saliente, duración y estado coinciden en ambos dispositivos.

**Estado inicial:** `P2 — ABIERTO`.

---

### REP-013 — Eliminar señalización/código legado no utilizado

**Problema:** permanece `CallSignalingService` con canales Broadcast antiguos y código nativo duplicado.

**Trabajo requerido:**
- Confirmar referencias reales.
- Eliminar solo después de pruebas de regresión.
- No mantener dos arquitecturas para el mismo evento sin una razón documentada.

**Criterio de cierre:** una sola arquitectura de señalización y notificación está documentada.

**Estado inicial:** `P2 — ABIERTO`.

---

### REP-014 — Mejorar observabilidad y eliminar errores silenciosos críticos

**Problema:** aún existen `catch (_) {}` en flujos relevantes.

**Trabajo requerido:**
- Clasificar excepciones tolerables vs. errores que deben reportarse.
- Introducir una capa mínima de logging estructurado.
- No registrar tokens, mensajes privados, credenciales ni contenido sensible.
- Añadir crash reporting respetuoso de privacidad antes de producción si se adopta proveedor externo.

**Criterio de cierre:** errores de autenticación, mensajes, Storage, push y llamadas dejan evidencia diagnóstica sin exponer datos sensibles.

**Estado inicial:** `P2 — ABIERTO`.

---

### REP-015 — Migrar o retirar medios históricos externos

**Problema:** adjuntos antiguos pueden continuar referenciando hosting externo aunque los nuevos usen Storage privado.

**Trabajo requerido:**
- Inventariar referencias históricas.
- Decidir migrar, invalidar o informar indisponibilidad.
- No reintroducir URLs externas como fallback silencioso.

**Criterio de cierre:** no existe contenido histórico privado publicado anónimamente por la arquitectura anterior, o su riesgo está explícitamente aceptado/documentado.

**Estado inicial:** `P2 — ABIERTO`.

## 5. Fase P3 — Repositorio y calidad de entrega

### REP-016 — Limpiar archivos ajenos al producto y binarios innecesarios

**Problema:** el repositorio contiene una copia HTML grande de Gemini y recursos descargados, además de imágenes pesadas de referencia.

**Trabajo requerido:**
- Mover documentación de referencia a una ubicación externa o eliminarla del árbol activo.
- Optimizar assets empaquetados por Flutter.
- Mantener únicamente recursos que tengan una función en build, pruebas o documentación vigente.

**Criterio de cierre:** repositorio limpio, sin dumps web ni assets duplicados innecesarios.

**Estado inicial:** `P3 — ABIERTO`.

---

### REP-017 — Alinear textos, versión y estado del producto

**Problema:** todavía existe `Release Estable` mientras varias funciones siguen siendo experimentales y no existe E2EE.

**Trabajo requerido:**
- Usar `Beta`, `Release Candidate` o `Production` según el gate real.
- No utilizar “E2EE”, “videollamada segura” o equivalentes hasta que el comportamiento lo respalde.
- Mantener privacidad/seguridad descrita en términos concretos: TLS, Auth, RLS, Storage privado, etc.

**Criterio de cierre:** ninguna afirmación pública excede la implementación verificada.

**Estado inicial:** `P3 — ABIERTO`.

## 6. Dependencias y secuencia obligatoria

```text
REP-001 ─┬─> REP-004 ───────────────┐
         ├─> REP-003                │
         └─> REP-010                │
REP-002 ─────> REP-006 ─> REP-007 ──┤
REP-005 ─────> REP-009 ─────────────┤
REP-008 ────────────────────────────┤
REP-011/012/013/014/015 ────────────┤
REP-016/017 ────────────────────────┤
                                      v
                               RELEASE CANDIDATE
                                      v
                              PRODUCTION DONE GATE
```

No se debe adelantar una publicación para compensar un P0 abierto.

## 7. Registro de avance obligatorio

Para cada `REP-XXX` cerrado agregar al PR o informe de reparación:

```text
REP-XXX:
Estado: RESUELTO | CORREGIDO-NO-VERIFICADO | BLOQUEADO
Commit:
Pruebas:
Entorno:
Resultado:
Riesgo residual:
Evidencia:
```

Los estados `CORREGIDO-NO-VERIFICADO` y `BLOQUEADO` no permiten cerrar un P0/P1 para release.

## 8. Condición para pasar al plan de producción

Se puede iniciar formalmente la etapa Release Candidate cuando:

- todos los P0 están `RESUELTO`;
- todos los P1 necesarios para las funciones habilitadas están `RESUELTO`;
- CI parte de checkout limpio y está verde;
- staging reproduce el esquema esperado;
- existe APK release firmado correctamente;
- no existen claims de funciones inexistentes.

El gate final y la definición exacta de `DONE` están en `docs/release/PRODUCTION_RELEASE_PLAN.md`.
