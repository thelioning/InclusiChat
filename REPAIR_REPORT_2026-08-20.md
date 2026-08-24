# Informe de saneamiento y reparación del software

## 1. Identificación
**Proyecto:** InclusiChat  
**Fecha:** 2026-08-20  
**Auditoría de origen:** auditoría técnica completa previa, hallazgos AUD-001 a AUD-013  
**Commit/revisión inicial:** `b6251f902a70bf6319ba5096844fabcfdd0b6d13`  
**Commit/revisión final:** árbol de trabajo sin commit sobre la revisión inicial  
**Rama de saneamiento:** `repair/audit-2026-08-20`

## 2. Alcance autorizado
Se trataron los trece hallazgos autorizados. No se ejecutaron migraciones ni cambios contra
Supabase remoto o producción, no se generó una clave de firma en nombre del propietario y no
se intentó convertir la vista previa de llamadas en un sistema WebRTC real. El `AGENTS.md`
preexistente y no versionado se preservó.

## 3. Resumen ejecutivo
Se trataron 13 hallazgos: 5 quedan `RESUELTO`, 5 `CORREGIDO — NO VERIFICADO` y 3
`PARCIALMENTE RESUELTO`. No quedan hallazgos sin estado. El código analiza sin incidencias,
las 14 pruebas aprueban y el APK debug compila. El gate de producción sigue cerrado porque
las migraciones no se han ensayado/aplicado en staging, falta una clave release custodiada y
la mensajería aún no ofrece cifrado de extremo a extremo.

## 4. Estado por hallazgo

### AUD-001 — Políticas RLS universales
**Severidad original:** Crítica  
**Prioridad:** P0  
**Estado final:** CORREGIDO — NO VERIFICADO  
**Causa raíz:** políticas permisivas no ligadas al usuario ni a la conversación.  
**Archivos/componentes modificados:** `supabase/migrations/20260820_001_security_baseline.sql`.  
**Cambio aplicado:** políticas por membresía, remitente y propietario; función auxiliar con
`security definer`, `search_path` vacío y permisos mínimos.  
**Motivo de la solución:** aplicar autorización en la frontera de datos.  
**Riesgo de la modificación:** las políticas pueden revelar incompatibilidades con datos
históricos.  
**Pruebas ejecutadas:** inspección estática automatizada y build Flutter.  
**Resultado:** reglas presentes; ejecución SQL no realizada.  
**Evidencia de cierre:** `security_schema_test.dart`.  
**Regresiones detectadas:** ninguna en cliente.  
**Riesgo residual:** requiere pruebas multicuenta en staging.  
**Observaciones:** producción permaneció intacta.

### AUD-002 — Medios públicos y ausencia de E2EE
**Severidad original:** Crítica  
**Prioridad:** P0  
**Estado final:** PARCIALMENTE RESUELTO  
**Causa raíz:** carga a Catbox y afirmación de seguridad superior a la implementación.  
**Archivos/componentes modificados:** migración `20260820_002_private_chat_media.sql`,
`chat_service.dart`, `conversation_page.dart` y textos públicos.  
**Cambio aplicado:** bucket privado, rutas por conversación/usuario y URL firmada temporal;
se eliminaron afirmaciones de E2EE.  
**Motivo de la solución:** impedir nuevas publicaciones anónimas y describir el producto con
precisión.  
**Riesgo de la modificación:** medios históricos conservan URL externa.  
**Pruebas ejecutadas:** pruebas estáticas, análisis y build.  
**Resultado:** el flujo nuevo no contiene Catbox y compila.  
**Evidencia de cierre:** `security_schema_test.dart`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** sin E2EE; inventariar/migrar medios históricos.  
**Observaciones:** TLS y RLS no equivalen a E2EE.

### AUD-003 — SQL divergente y sin migraciones
**Severidad original:** Alta  
**Prioridad:** P0  
**Estado final:** CORREGIDO — NO VERIFICADO  
**Causa raíz:** snapshots SQL duplicados como fuente operativa.  
**Archivos/componentes modificados:** `supabase/README.md`, tres migraciones versionadas.  
**Cambio aplicado:** se declaró `supabase/migrations` como fuente autoritativa y se documentó
el carácter forense de los snapshots heredados.  
**Motivo de la solución:** obtener una secuencia reproducible y revisable.  
**Riesgo de la modificación:** esquema remoto desconocido hasta ensayarlo.  
**Pruebas ejecutadas:** validaciones estáticas.  
**Resultado:** secuencia local coherente; no aplicada.  
**Evidencia de cierre:** migraciones `001` a `003`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** comparar staging contra snapshots antes de promover.  
**Observaciones:** no hubo DDL remoto.

### AUD-004 — Firma release con clave debug
**Severidad original:** Alta  
**Prioridad:** P0  
**Estado final:** CORREGIDO — NO VERIFICADO  
**Causa raíz:** fallback release a `signingConfigs.debug`.  
**Archivos/componentes modificados:** `android/app/build.gradle.kts`,
`android/key.properties.example`, README.  
**Cambio aplicado:** cierre seguro si falta material release; nunca usa clave debug.  
**Motivo de la solución:** evitar artefactos publicables con firma de desarrollo.  
**Riesgo de la modificación:** release bloqueado hasta configurar la clave.  
**Pruebas ejecutadas:** prueba estática, build debug y fallo controlado de release sin clave.  
**Resultado:** comportamiento esperado.  
**Evidencia de cierre:** `release_configuration_test.dart`.  
**Regresiones detectadas:** ninguna en debug.  
**Riesgo residual:** generación, custodia y backup de clave a cargo del propietario.  
**Observaciones:** no se incluyeron secretos.

### AUD-005 — PIN de camuflaje en texto claro y valor por defecto
**Severidad original:** Alta  
**Prioridad:** P1  
**Estado final:** RESUELTO  
**Causa raíz:** SharedPreferences y PIN `1234`.  
**Archivos/componentes modificados:** servicio y pantallas de camuflaje, `pubspec`.  
**Cambio aplicado:** `flutter_secure_storage`, sin PIN predeterminado, migración segura de PIN
personalizado, validación y bloqueo temporal tras cinco fallos.  
**Motivo de la solución:** eliminar secreto predecible y almacenamiento plano.  
**Riesgo de la modificación:** usuarios con el antiguo `1234` deben configurar uno nuevo.  
**Pruebas ejecutadas:** prueba específica, análisis y build.  
**Resultado:** aprobado.  
**Evidencia de cierre:** `camouflage_security_test.dart`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** seguridad depende del almacén seguro del dispositivo.  
**Observaciones:** dependencia directa justificada.

### AUD-006 — Broadcast público predecible para llamadas
**Severidad original:** Alta  
**Prioridad:** P1  
**Estado final:** RESUELTO  
**Causa raíz:** canal Realtime redundante derivado de identificadores públicos.  
**Archivos/componentes modificados:** `chat_home_page.dart`, `call_screen.dart` y textos.  
**Cambio aplicado:** la ruta activa dejó de unirse/publicar en broadcast y conserva la
señalización experimental mediante mensajes sometidos a RLS.  
**Motivo de la solución:** reducir superficie de ataque sin simular una llamada real.  
**Riesgo de la modificación:** polling temporal hasta implementar transporte de llamadas.  
**Pruebas ejecutadas:** prueba específica, análisis y build.  
**Resultado:** aprobado.  
**Evidencia de cierre:** `call_security_test.dart`.  
**Regresiones detectadas:** ninguna en compilación.  
**Riesgo residual:** no existe audio/video WebRTC.  
**Observaciones:** la UI lo identifica como vista previa experimental.

### AUD-007 — Cobertura y operación insuficientes
**Severidad original:** Alta  
**Prioridad:** P1  
**Estado final:** PARCIALMENTE RESUELTO  
**Causa raíz:** dos pruebas de widgets y ausencia de CI.  
**Archivos/componentes modificados:** seis archivos de prueba y `.github/workflows/flutter-ci.yml`.  
**Cambio aplicado:** 14 pruebas totales y gate de formato/análisis/test/build.  
**Motivo de la solución:** hacer repetible la validación.  
**Riesgo de la modificación:** bajo.  
**Pruebas ejecutadas:** suite completa local.  
**Resultado:** 14/14 aprobadas.  
**Evidencia de cierre:** salida `flutter test`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** faltan pruebas de integración con staging y dispositivos reales.  
**Observaciones:** CI no se ejecutó en GitHub durante esta sesión.

### AUD-008 — Consultas y streams no acotados
**Severidad original:** Media  
**Prioridad:** P2  
**Estado final:** RESUELTO  
**Causa raíz:** carga histórica completa por conversación.  
**Archivos/componentes modificados:** `chat_service.dart`.  
**Cambio aplicado:** ventana de 200 mensajes recientes y límite de 1000 recibos.  
**Motivo de la solución:** limitar memoria, red y render inicial.  
**Riesgo de la modificación:** historial anterior requiere futura paginación hacia atrás.  
**Pruebas ejecutadas:** prueba estática, análisis y build.  
**Resultado:** aprobado.  
**Evidencia de cierre:** `scalability_and_permissions_test.dart`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** añadir paginación UX al superar 200 mensajes.  
**Observaciones:** se preservó orden cronológico visible.

### AUD-009 — Borrado y conversación directa no atómicos
**Severidad original:** Media  
**Prioridad:** P2  
**Estado final:** CORREGIDO — NO VERIFICADO  
**Causa raíz:** operaciones cliente en varios pasos y carrera de creación.  
**Archivos/componentes modificados:** migraciones `001` y `003`, `chat_service.dart`.  
**Cambio aplicado:** RPC de borrado por usuario, índice único, bloqueo transaccional asesor y
RPC única para crear/recuperar conversación.  
**Motivo de la solución:** atomicidad e idempotencia en base de datos.  
**Riesgo de la modificación:** compatibilidad con datos duplicados heredados.  
**Pruebas ejecutadas:** validación estática y cliente compilado.  
**Resultado:** correcto localmente; SQL no ejecutado.  
**Evidencia de cierre:** migraciones y prueba de escalabilidad/atomicidad.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** ensayo concurrente en staging obligatorio.  
**Observaciones:** la migración aborta si detecta duplicados.

### AUD-010 — Errores silenciados y observabilidad
**Severidad original:** Media  
**Prioridad:** P2  
**Estado final:** PARCIALMENTE RESUELTO  
**Causa raíz:** capturas tolerantes sin telemetría central.  
**Archivos/componentes modificados:** `main.dart`, prueba de observabilidad.  
**Cambio aplicado:** manejadores globales Flutter, plataforma y zona asíncrona con log
estructurado local.  
**Motivo de la solución:** capturar fallos no controlados sin añadir un proveedor/secretos.  
**Riesgo de la modificación:** bajo.  
**Pruebas ejecutadas:** prueba específica, análisis y build.  
**Resultado:** aprobado.  
**Evidencia de cierre:** `observability_test.dart`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** varios fallos opcionales siguen degradando silenciosamente; no hay backend
de crash reporting ni alertas.  
**Observaciones:** su eliminación masiva se descartó por alcance y riesgo.

### AUD-011 — Afirmaciones falsas de seguridad/producto
**Severidad original:** Media  
**Prioridad:** P2  
**Estado final:** RESUELTO  
**Causa raíz:** textos prometían E2EE, efímero y llamadas reales.  
**Archivos/componentes modificados:** web, guía y pantallas de seguridad/llamadas.  
**Cambio aplicado:** lenguaje alineado con TLS, RLS, persistencia y estado experimental.  
**Motivo de la solución:** consentimiento y expectativas correctas.  
**Riesgo de la modificación:** ninguno técnico.  
**Pruebas ejecutadas:** búsqueda y build.  
**Resultado:** aprobado.  
**Evidencia de cierre:** textos actualizados.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** revisar marketing futuro.  
**Observaciones:** no se afirma paridad criptográfica con WhatsApp.

### AUD-012 — Permisos Android excesivos
**Severidad original:** Media  
**Prioridad:** P2  
**Estado final:** RESUELTO  
**Causa raíz:** permisos heredados de almacenamiento global.  
**Archivos/componentes modificados:** `AndroidManifest.xml`.  
**Cambio aplicado:** retirada de `READ_EXTERNAL_STORAGE` y `WRITE_EXTERNAL_STORAGE`.  
**Motivo de la solución:** picker moderno y mínimo privilegio.  
**Riesgo de la modificación:** bajo en Android soportado.  
**Pruebas ejecutadas:** prueba de manifiesto y build APK.  
**Resultado:** aprobado.  
**Evidencia de cierre:** `scalability_and_permissions_test.dart`.  
**Regresiones detectadas:** ninguna en build.  
**Riesgo residual:** validar cámara/audio en dispositivo por versión.  
**Observaciones:** permisos funcionales se conservaron.

### AUD-013 — Warnings y configuración de herramientas
**Severidad original:** Baja  
**Prioridad:** P3  
**Estado final:** CORREGIDO — NO VERIFICADO  
**Causa raíz:** imports/flujo sin limpiar y advertencias de plugins Windows del entorno.  
**Archivos/componentes modificados:** código señalado por analyzer y lock generado.  
**Cambio aplicado:** cero incidencias de `flutter analyze`; formato normalizado.  
**Motivo de la solución:** gate reproducible sin deuda estática.  
**Riesgo de la modificación:** bajo.  
**Pruebas ejecutadas:** `flutter analyze`, test y build.  
**Resultado:** analyzer sin incidencias.  
**Evidencia de cierre:** salida final `No issues found!`.  
**Regresiones detectadas:** ninguna.  
**Riesgo residual:** Flutter emite avisos de metadatos de plugins Windows antes de ejecutar;
Android compila y esos avisos requieren validar la toolchain Windows separadamente.  
**Observaciones:** estado no verificado para Windows desktop.

## 5. Cambios de base de datos
Se añadieron tres migraciones: baseline RLS/índices/RPC de borrado; bucket privado y políticas
de objetos; RPC atómica de conversación directa. Son transaccionales cuando corresponde y
no destructivas. La primera aborta ante `direct_pair_key` duplicado. Rollback operativo:
restaurar políticas/funciones desde snapshot verificado y retirar índices/bucket solo tras
comprobar dependencias. No se verificó integridad posterior porque no se tocó ninguna BD.

## 6. Cambios de seguridad
Autorización por membresía en RLS, medios privados con URLs firmadas, PIN en almacén seguro,
release sin firma debug, permisos Android mínimos y eliminación del broadcast público activo.
No hay secretos nuevos en archivos rastreables; el barrido solo encontró ejemplos preventivos.
Persisten ausencia de E2EE, medios históricos externos y falta de validación RLS en staging.

## 7. Cambios arquitectónicos
- La base de datos asume atomicidad de operaciones multiusuario mediante RPC.
- Storage privado sustituye hosting anónimo para medios nuevos; el cliente resuelve URLs firmadas.
- Señalización experimental usa mensajes protegidos por conversación, no broadcast público.
- El gate CI convierte análisis, pruebas y build debug en condición repetible.
- El manejador global de errores registra fallos no controlados sin servicio externo.

## 8. Pruebas ejecutadas
### Build
**Comando:** `flutter build apk --debug`  
**Resultado:** aprobado; APK de 185,567,887 bytes.

### Unitarias
**Resultado:** `flutter test`, 14/14 aprobadas.

### Integración
**Resultado:** no ejecutadas contra Supabase; bloqueadas por protección de producción y falta de staging.

### Base de datos
**Resultado:** validación estática aprobada; migraciones no aplicadas.

### Regresión
**Resultado:** login y registro widget tests aprobados; build Android aprobado.

### Seguridad
**Resultado:** seis grupos de aserciones estáticas aprobados; barrido sin secretos reales rastreables.

### Rendimiento
**Resultado:** límites verificados estáticamente; no se realizó benchmark de red/dispositivo.

## 9. Regresiones
No se detectaron regresiones en análisis, pruebas o compilación. El release sin clave falla por
diseño. No se realizaron pruebas funcionales remotas ni en dispositivo físico.

## 10. Hallazgos nuevos
**AUD-NEW-001:** la toolchain reporta implementaciones Windows ausentes para `path_provider`,
`shared_preferences` y `url_launcher`; no afecta el APK Android verificado, pero impide declarar
Windows desktop saneado.

## 11. Riesgos residuales
- **RISK-RES-001:** migraciones RLS/RPC/Storage no probadas con datos reales en staging.
- **RISK-RES-002:** no existe cifrado de extremo a extremo.
- **RISK-RES-003:** medios históricos pueden permanecer en Catbox.
- **RISK-RES-004:** llamadas son señalización/UI experimental, sin transporte WebRTC.
- **RISK-RES-005:** historial anterior a 200 mensajes no tiene paginación hacia atrás.
- **RISK-RES-006:** observabilidad no se envía a un servicio remoto y persisten catches tolerantes.
- **RISK-RES-007:** falta validación física por versión Android y una suite E2E.

## 12. Bloqueos
- **BLOCK-001:** falta un proyecto Supabase de staging autorizado para aplicar/verificar migraciones.
- **BLOCK-002:** falta crear y custodiar la clave de firma release fuera del repositorio.
- **BLOCK-003:** no se dispuso de inventario/credenciales para retirar medios históricos externos.

## 13. Resultado de re-auditoría
Arquitectura: mejor separación cliente/autoridad DB. Código: analyzer limpio. BD: migraciones
coherentes pero no ejecutadas. Seguridad: superficie crítica reducida, sin E2EE. Integridad y
transacciones: diseños atómicos pendientes de staging. Errores: captura global presente, deuda
local parcial. Pruebas: 14 aprobadas y CI definido. Rendimiento/escalabilidad: lecturas acotadas,
sin benchmark. Configuración: Android debug listo; release/Windows bloqueados. Producción: no lista.

## 14. Comparación antes/después
**Críticos antes:** 2  
**Críticos después:** 0 confirmados en código; 2 riesgos no cerrables hasta staging/E2EE  
**Altos antes:** 5  
**Altos después:** 0 confirmados; 3 cierres requieren validación operativa  
**Puntuación inicial:** no consta como artefacto versionado; no se inventa.  
**Puntuación posterior:** no se asigna sin la escala/puntuación original y validación remota.

## 15. Gate final de producción

**¿RECOMIENDAS DESPLEGAR ESTE PROYECTO EN PRODUCCIÓN DESPUÉS DEL SANEAMIENTO?**

Respuesta: `NO`

**Justificación técnica:** las correcciones más sensibles dependen de migraciones aún no
ensayadas, no existe clave release, falta E2EE para una promesa de mensajería de alta seguridad
y no hay prueba E2E multicuenta/dispositivo.

## 16. Condiciones pendientes
Crear staging; respaldar y comparar esquema/datos; resolver duplicados si existen; aplicar las
tres migraciones; probar RLS con dos usuarios y uno no participante; verificar Storage y RPC bajo
concurrencia; crear clave release; ejecutar pruebas Android reales; decidir e implementar el
modelo E2EE; migrar/eliminar medios históricos; configurar crash reporting respetuoso de privacidad.

## 17. Próximos pasos
1. Preparar staging desde un backup anonimizado y ejecutar la prevalidación de migraciones.
2. Aplicar migraciones en staging y probar autorización, atomicidad y rollback con cuentas reales.
3. Añadir paginación hacia atrás y pruebas de carga antes de conversaciones extensas.
4. Definir protocolo E2EE y modelo de claves antes de afirmar paridad con WhatsApp.
5. Crear/custodiar la clave release y producir un artefacto firmado de prueba interna.
6. Ejecutar E2E en dos dispositivos, incluida cámara, audio, suspensión y reconexión.
7. Inventariar medios Catbox y establecer una migración/borrado verificable.
