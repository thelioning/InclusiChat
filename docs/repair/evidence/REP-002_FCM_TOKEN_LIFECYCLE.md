# REP-002 — Ciclo de vida del token FCM

**Estado:** `CÓDIGO CORREGIDO — CI Y DISPOSITIVO FÍSICO PENDIENTES`  
**Fecha:** 2026-08-24  
**Rama:** `repair/rep-002-fcm-lifecycle`

## Problema confirmado

El servicio de push anterior registraba el token FCM con el usuario presente al inicializarse y mantenía `_initialized=true`. `AuthService.signOut()` solo cerraba Supabase Auth.

Eso permitía dos fallos de privacidad/correctitud:

1. el token de un dispositivo podía seguir almacenado en `device_push_tokens` bajo la cuenta A después de logout;
2. en el mismo proceso, el login posterior de B podía encontrar el servicio todavía inicializado para A y no volver a registrar correctamente el dispositivo.

## Cambios implementados

### `push_notification_service.dart`

- registra el usuario propietario del token en `FlutterSecureStorage`;
- registra también el token FCM localmente;
- mantiene `_initializedUserId` además de `_initialized`;
- detecta un cambio inesperado de propietario y fuerza invalidación del token FCM anterior;
- el refresh de token verifica que la sesión activa todavía corresponde al propietario inicializado;
- al rotar token, registra primero el nuevo y después elimina el token anterior del mismo usuario;
- añade `prepareForSignOut()`;
- al cerrar sesión elimina del backend únicamente el token exacto de este dispositivo y este usuario;
- cancela subscriptions y resetea la UI nativa de llamada;
- ejecuta `FirebaseMessaging.deleteToken()` para invalidar la ruta FCM del dispositivo;
- si ni la eliminación backend ni la invalidación FCM consiguen proteger el dispositivo, el logout no continúa silenciosamente;
- limpia primero el propietario local para que un push que ya estuviera en tránsito falle de forma cerrada.

### `AuthService.signOut()`

`signOut()` ahora ejecuta `PushNotificationService.prepareForSignOut()` antes de destruir la sesión Supabase.

Si Supabase falla al cerrar la sesión después de haber limpiado el push, se intenta reinicializar FCM para la sesión que todavía continúa activa.

Esto centraliza el comportamiento: el logout del Home y el logout de Seguridad pasan por el mismo flujo.

### `send-call-notification`

El payload de llamada incluye ahora:

`receiver_id: body.receiver_id`

El handler foreground y el handler background comparan ese ID con el propietario de push del dispositivo. Si no coincide, la llamada se descarta.

El background handler también descarta llamadas si ya no existe propietario local del push, reduciendo el riesgo de mostrar una llamada que llegó durante la carrera de logout.

## Staging

La versión modificada de `send-call-notification` fue desplegada únicamente en `InclusiChat-Staging` con `verify_jwt=true`.

No se desplegó esta función ni ningún cambio REP-002 en producción.

## Prueba de base de datos

Se verificó sobre staging, dentro de una transacción, que la RLS de `device_push_tokens` permite a A eliminar su token exacto sin convertir la operación en un borrado general de todos sus dispositivos.

Tras eliminar el token A1, A todavía veía A2. El token de B no era visible para A por RLS.

## Regresión automatizada añadida

`app/test/push_notification_security_test.dart` verifica por código que:

- existe `prepareForSignOut()`;
- el borrado backend está acotado por `token` + `user_id`;
- se invalida el token de Firebase;
- existe seguimiento del propietario inicializado;
- `AuthService.signOut()` llama al cleanup;
- el payload contiene `receiver_id`.

Esta prueba es una guardia estática. No sustituye la prueba de comportamiento en dispositivo.

## Pruebas obligatorias pendientes

REP-002 no puede cerrarse hasta ejecutar en Android real:

1. login A en teléfono T1;
2. confirmar token A/T1 en backend;
3. logout A;
4. confirmar que el token A/T1 desaparece del backend;
5. login B en T1;
6. confirmar token nuevo/correctamente asociado a B;
7. llamar a A desde otro dispositivo: T1 no debe recibir la llamada;
8. llamar a B: T1 debe recibirla;
9. A conectado simultáneamente en T1/T2 antes del logout: cerrar T1 no debe borrar el token T2;
10. rotación de token: el token anterior debe dejar de quedar activo/registrado para ese dispositivo.

También debe probarse background, app terminada y pantalla bloqueada.

## Criterio de cierre

`REP-002 — CERRADO` solo cuando:

- CI pasa format/analyze/tests;
- las pruebas anteriores pasan en dispositivo físico;
- ninguna cuenta recibe push en un dispositivo donde ya cerró sesión;
- otros dispositivos del mismo usuario siguen recibiendo normalmente.

## Riesgo residual

Firebase indica que los handlers de background pueden realizar IO/local storage y comunicarse con plugins, pero este uso de `FlutterSecureStorage` debe validarse específicamente en los dispositivos objetivo, especialmente con la aplicación terminada. Si el plugin no estuviera disponible en el isolate de un fabricante/versión concreta, el diseño falla cerrado (no muestra la llamada) en vez de exponer una llamada de otra cuenta.
