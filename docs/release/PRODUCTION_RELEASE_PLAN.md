# InclusiChat — Plan para llegar a Production Release

**Documento de continuidad del proyecto**  
**Base:** commit `196d5356c7df93d74e061622cd81d1c280b4d32c`  
**Ruta de reparación obligatoria:** `docs/repair/REPAIR_ROADMAP.md`  
**Objetivo de primera versión production-capable:** `v1.6.0` con `buildNumber > 44`.

Este documento define qué significa terminar InclusiChat hasta un punto publicable, funcional y mantenible. `DONE` no significa que no quede ninguna función futura; significa que el conjunto de funciones incluido en la release funciona, está probado, tiene controles de seguridad coherentes y puede operarse sin depender de la máquina del desarrollador.

## 1. Alcance de la primera Production Release

La primera release debe concentrarse en un núcleo pequeño que pueda sostenerse correctamente.

### Funciones obligatorias

1. Registro, autenticación, recuperación y cierre de sesión.
2. Perfil de usuario y alias.
3. Búsqueda controlada de usuarios y consentimiento de contacto.
4. Conversaciones directas autorizadas por servidor.
5. Mensajes de texto.
6. Imágenes, notas de voz y documentos mediante Storage privado.
7. Estados básicos de entrega/lectura consistentes.
8. Eliminación de mensaje para mí y, cuando corresponda, para todos.
9. Eliminación de conversación solo para el usuario sin borrar datos compartidos del otro participante.
10. Eliminación real de cuenta, incluyendo recursos de Storage y tokens push.
11. Notificaciones útiles cuando la aplicación está en background o terminada para los eventos que se declaren soportados.
12. Actualización/versionado coherente y APK release firmado con clave de producción.
13. CI reproducible desde checkout limpio.
14. Política de privacidad y textos de producto alineados con el comportamiento real.

### Llamadas: condición especial

La primera producción puede salir de una de dos maneras:

**Opción A — llamadas habilitadas:**
- audio real bidireccional;
- para videollamada, video real si el botón está visible;
- señalización, aceptación, rechazo, cancelación y finalización coherentes;
- manejo foreground/background/terminated;
- STUN/TURN y reconexión definidos si se utiliza WebRTC;
- micrófono, altavoz y cámara controlan recursos reales;
- pruebas de dos dispositivos físicos.

**Opción B — llamadas deshabilitadas en producción:**
- UI de llamadas oculta o feature flag en `false` para el build release;
- ningún texto sugiere que existe voz/video cuando solo existe señalización;
- el código experimental puede permanecer para desarrollo si está aislado y no afecta producción.

Para `v1.6.0`, la Opción B es aceptable y permite un release funcional de mensajería sin esperar a completar VoIP.

### E2EE: condición de alcance

E2EE no es un requisito para declarar `v1.6.0` production-capable **si y solo si**:
- no se afirma que exista E2EE;
- la documentación explica que hay TLS, Auth, RLS y Storage privado;
- la información sensible no se comercializa como inaccesible al servidor.

La implementación E2EE queda como una etapa mayor posterior y debe seguir `docs/security/E2EE_ARCHITECTURE.md` o una revisión posterior auditada. Si el posicionamiento comercial exige E2EE, entonces pasa automáticamente a ser blocker de release.

## 2. Fases de continuidad

### Fase 0 — Congelar línea base

**Objetivo:** evitar reparar sobre estados diferentes.

- Integrar formalmente el commit de saneamiento que se decida conservar.
- Crear rama de integración/release desde una revisión conocida.
- Registrar versión del cliente, esquema staging y hashes relevantes.
- No agregar funciones nuevas mientras existan P0 abiertos.

**Salida:** baseline identificable y reproducible.

---

### Fase 1 — Seguridad y consistencia de datos

Ejecutar `REP-001` a `REP-005` de la ruta de reparación.

**Entregables:**
- staging operativo;
- RLS validada con múltiples cuentas;
- tokens FCM ligados correctamente a sesión/dispositivo;
- borrado real de cuenta y Storage;
- consentimiento de contactos impuesto por servidor;
- firma production y estrategia de transición desde APK antiguos.

**Gate:** cero P0 abiertos.

---

### Fase 2 — Eventos en background y llamadas

Ejecutar `REP-006` a `REP-010`.

**Además validar notificaciones de mensajería:** una aplicación de chat production-capable debe informar mensajes entrantes con la app en background/terminada si esa función forma parte de la experiencia prometida. Si aún no existe push de mensajes, implementarlo o documentar explícitamente el comportamiento antes de RC.

**Gate de llamadas:** seleccionar formalmente `CALLS_ENABLED_AND_REAL` o `CALLS_DISABLED_IN_PRODUCTION`.

**Gate:** cero P1 abiertos para funciones que estarán habilitadas en producción.

---

### Fase 3 — Rendimiento y coherencia de UX

Ejecutar `REP-011` a `REP-015`.

Agregar dos controles de madurez:

1. **Paginación de historial:** el límite de 200 mensajes no puede convertirse en pérdida aparente de historial. Debe existir carga hacia atrás o una decisión visible/documentada de retención.
2. **Conectividad:** pérdida y recuperación de red no deben duplicar mensajes, estados de recibo ni conversaciones.

**Métricas mínimas a observar en staging:**
- consultas periódicas por usuario;
- tiempo inicial de carga de conversaciones;
- tiempo de apertura de conversación;
- memoria aproximada con conversación extensa;
- tasa de error en upload/download de adjuntos;
- entrega de push en escenarios probados.

No se requiere una escala masiva para `v1.6.0`, pero no debe existir un patrón conocido que multiplique consultas innecesariamente cada pocos cientos de milisegundos.

---

### Fase 4 — Calidad del repositorio y comunicación del producto

Ejecutar `REP-016` y `REP-017`.

- retirar dumps, assets sin uso y código legado confirmado;
- revisar README, web, guía y About;
- cambiar `Release Estable` por el estado real durante desarrollo;
- solo usar `Production` tras pasar el gate final.

**Gate:** repositorio y producto describen la misma realidad.

---

### Fase 5 — Release Candidate

Cuando P0/P1 estén cerrados, crear una versión `v1.6.0-rc.1` o equivalente interna. No publicarla todavía como estable.

#### Matriz mínima de escenarios

**Cuenta y sesión**
- registro nuevo;
- confirmación y login;
- recuperación;
- logout/login mismo usuario;
- usuario A → logout → usuario B en mismo dispositivo;
- eliminación de cuenta con adjuntos y tokens.

**Contactos**
- solicitud;
- rechazo;
- aceptación;
- cancelación por emisor si se soporta;
- intento de chat antes de aceptación bloqueado por servidor;
- intento de modificar solicitud ajena bloqueado.

**Chat**
- texto;
- imagen;
- audio;
- documento;
- entregado/leído;
- eliminar para mí;
- eliminar para todos según regla definida;
- borrar chat para mí;
- historial >200 con paginación;
- reconexión después de pérdida de red.

**Privacidad**
- tercer usuario no puede leer conversación;
- tercer usuario no obtiene URL firmada útil del adjunto;
- URL firmada expira;
- token FCM de sesión anterior deja de recibir eventos;
- cuenta eliminada no conserva objetos privados atribuibles al usuario.

**Notificaciones**
- app abierta;
- background;
- pantalla bloqueada;
- app terminada normalmente;
- toque de notificación abre el destino correcto;
- notificación vieja no abre estado obsoleto.

**Llamadas, solo si se habilitan**
- llamar/aceptar/rechazar;
- cancelar antes de respuesta;
- llamada perdida;
- colgar desde ambos lados;
- background/locked/terminated;
- audio real de ambos lados;
- cambio mic/altavoz real;
- video real si se ofrece;
- red degradada y reconexión razonable.

**Distribución**
- instalación limpia de APK release;
- verificación de firma;
- actualización desde una instalación compatible;
- comportamiento documentado desde builds antiguos incompatibles por firma;
- UpdateService detecta correctamente una versión superior.

## 3. Definition of Done — Production Release

Una revisión se marca `DONE — PRODUCTION RELEASE` únicamente cuando **todas** las condiciones siguientes sean verdaderas.

### Gate A — Seguridad

- [ ] Todos los P0 están `RESUELTO` y verificados en staging.
- [ ] No existen políticas RLS universales para mensajes/participantes/recibos.
- [ ] Prueba multicuenta confirma aislamiento de conversaciones.
- [ ] Storage privado rechaza usuarios no participantes.
- [ ] Tokens FCM no sobreviven asociados a una sesión cerrada en ese dispositivo.
- [ ] Eliminación de cuenta elimina también recursos y tokens definidos por la política del producto.
- [ ] No hay secretos reales rastreados por Git.
- [ ] Cero vulnerabilidades conocidas clasificadas `CRÍTICO` o `ALTO` sin mitigación.

### Gate B — Funcionalidad

- [ ] Login, contactos, chat, multimedia y borrado funcionan de extremo a extremo.
- [ ] No existe una ruta de UI que eluda el consentimiento impuesto por servidor.
- [ ] Historial largo puede recuperarse sin hacer desaparecer mensajes antiguos.
- [ ] App se recupera de pérdida de red sin corrupción visible.
- [ ] Funciones experimentales están ocultas/deshabilitadas en production o están completamente implementadas.
- [ ] Si llamadas están habilitadas, transmiten medios reales y pasan matriz física.

### Gate C — Pruebas

- [ ] `dart format --output=none --set-exit-if-changed lib test` pasa.
- [ ] `flutter analyze` pasa sin errores.
- [ ] `flutter test` pasa.
- [ ] Pruebas de integración contra staging pasan.
- [ ] RLS se prueba por comportamiento con cuentas distintas.
- [ ] Prueba E2E en al menos dos dispositivos Android físicos pasa para los flujos críticos.
- [ ] No hay regresiones abiertas de severidad alta.

### Gate D — Build y CI

- [ ] GitHub Actions construye desde checkout limpio.
- [ ] Configuración Firebase se inyecta por secrets y no se versiona.
- [ ] Tres ejecuciones consecutivas del pipeline de la revisión release están verdes.
- [ ] APK release se genera sin clave debug.
- [ ] El APK está firmado con la clave de producción custodiada.
- [ ] Se registra SHA-256 del artefacto publicado.

### Gate E — Versionado y actualización

- [ ] `pubspec.yaml`, `AppConfig`, web y release tag expresan la misma versión.
- [ ] Versión objetivo inicial: `1.6.0` y build >44.
- [ ] Existe estrategia para usuarios de APK previos firmados con certificado incompatible.
- [ ] UpdateService distingue correctamente versión instalada vs. publicada.
- [ ] Release notes describen cambios, incompatibilidades y migraciones requeridas.

### Gate F — Base de datos y operación

- [ ] Migraciones están versionadas y aplicadas primero en staging.
- [ ] Backup verificado previo a promoción.
- [ ] Plan de rollback probado/documentado.
- [ ] Integridad básica posterior a migración verificada.
- [ ] Supabase production no recibe cambios manuales no registrados en migraciones.

### Gate G — Producto y privacidad

- [ ] No se afirma E2EE si no existe.
- [ ] No se denomina llamada/videollamada funcional a señalización sin medios.
- [ ] Política de privacidad describe almacenamiento, borrado y terceros reales utilizados.
- [ ] `Release Estable`/`Production` solo aparece después del gate.
- [ ] Ningún texto promete borrado total si quedan datos que el sistema conserva.

### Gate H — Revisión final

- [ ] Reauditoría final completada sobre el commit exacto que se publicará.
- [ ] Todos los `REP-001` a `REP-017` están `RESUELTO`, `N/A` justificado o sustituidos por una solución equivalente verificada.
- [ ] No existen P0/P1 abiertos.
- [ ] Riesgos residuales aceptados están documentados y ninguno invalida privacidad, integridad o función principal.
- [ ] El commit release es inmutable y corresponde al artefacto probado.

**Solo después de completar A–H se cambia el estado a:**

```text
DONE — PRODUCTION RELEASE
```

## 4. Release objetivo alcanzable

Para mantener un objetivo realista, se fija como primera meta:

```text
InclusiChat v1.6.0 — Production Baseline
```

### Debe incluir

- mensajería directa estable;
- privacidad mediante Auth + RLS + Storage privado;
- consentimiento de contacto;
- multimedia privada;
- eliminación de cuenta completa conforme a lo prometido;
- ciclo correcto de sesión y push;
- notificaciones coherentes;
- APK firmado y CI reproducible;
- pruebas reales multicuenta y en dispositivos.

### Puede diferirse sin bloquear v1.6.0

- E2EE, siempre que no se prometa;
- grupos avanzados;
- llamadas de voz/video, **solo si están deshabilitadas en el build production**;
- Windows desktop;
- funciones sociales no esenciales.

Esta definición evita que la release dependa de completar todo el producto imaginado, pero impide publicar funciones simuladas o riesgos de privacidad conocidos.

## 5. Después de v1.6.0

Una vez estabilizada la Production Baseline, la evolución recomendada es:

1. `v1.7.x`: eficiencia, notificaciones, observabilidad y UX.
2. `v1.8.x` o una rama específica: VoIP/WebRTC si no entró en 1.6.0.
3. `v2.0.0`: considerar E2EE como cambio mayor cuando protocolo, multidispositivo, migración y auditoría estén completos.

No fijar estas versiones como promesas de calendario; son límites de alcance técnico.

## 6. Formato de control de cada Release Candidate

Crear un archivo o informe de cierre con:

```text
Release Candidate:
Commit:
Tag:
Build:
Esquema/migración aplicada:
CI run:
APK SHA-256:
Dispositivos probados:
P0 abiertos: 0
P1 abiertos: 0
P2/P3 residuales:
Calls mode: ENABLED_AND_REAL | DISABLED_IN_PRODUCTION
E2EE: IMPLEMENTED_VERIFIED | NOT_CLAIMED
Resultado gate A-H:
Veredicto: GO | NO-GO
```

Un `NO-GO` vuelve a la ruta `docs/repair/REPAIR_ROADMAP.md`; no se corrige directamente en el artefacto release sin nueva revisión, build y pruebas.
