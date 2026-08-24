# AGENTS.md

## Sistema profesional de auditoría y saneamiento

Este repositorio utiliza dos modos de trabajo separados:

1. `AUDIT MODE — READ ONLY`
2. `REPAIR MODE — CONTROLLED WRITE`

Nunca mezcles ambos modos en una misma fase.

## 1. Modo auditoría

Cuando el usuario solicite auditoría, revisión técnica completa, revisión para producción,
evaluación de calidad, análisis de seguridad, arquitectura, escalabilidad o revisión integral,
activa:

`AUDIT MODE — READ ONLY`

Antes de comenzar, lee completamente:

1. `.codex/audit/AUDIT_STANDARD.md`
2. `.codex/audit/AUDIT_CHECKLIST.md`
3. `.codex/audit/REPORT_TEMPLATE.md`

### Reglas

- No modificar archivos fuente.
- No refactorizar.
- No corregir código.
- No cambiar configuraciones.
- No ejecutar migraciones destructivas.
- No modificar esquemas.
- No insertar, actualizar ni eliminar datos.
- No cambiar dependencias.
- No hacer commits ni push.
- No ocultar warnings.
- No desactivar pruebas.
- No conectarse a producción sin autorización explícita.

Puedes ejecutar acciones no destructivas como inspección, búsqueda, restauración de dependencias,
compilación, análisis estático, pruebas e inspección de migraciones.

Todo hallazgo debe basarse en evidencia e identificar, cuando sea posible, archivo, clase,
método, línea, tabla, vista, función, trigger, procedimiento, configuración, dependencia,
endpoint o servicio.

Estados de evidencia:

- `CONFIRMADO`
- `PROBABLE`
- `POTENCIAL`
- `NO VERIFICADO`

Severidad:

- `CRÍTICO`
- `ALTO`
- `MEDIO`
- `BAJO`
- `INFORMATIVO`

No declares terminada la auditoría mientras existan elementos obligatorios de
`AUDIT_CHECKLIST.md` sin revisar, justificar como `N/A` o marcar `UNVERIFIED`.

El informe final debe seguir `REPORT_TEMPLATE.md`.

## 2. Prohibición de reparación automática

Finalizar una auditoría NO autoriza modificar el proyecto.

Después del informe:

- detente;
- presenta el veredicto;
- presenta la ruta de saneamiento;
- espera autorización explícita.

No inicies `REPAIR MODE` por inferencia.

## 3. Modo reparación

Cuando exista un informe de auditoría y el usuario autorice explícitamente la corrección,
activa:

`REPAIR MODE — CONTROLLED WRITE`

Antes de modificar el proyecto, lee completamente:

1. `.codex/repair/REPAIR_STANDARD.md`
2. `.codex/repair/REPAIR_CHECKLIST.md`
3. `.codex/repair/REPAIR_REPORT_TEMPLATE.md`

La reparación debe basarse en hallazgos `AUD-XXX`.

No realizar refactorización masiva sin justificación técnica y autorización.

## 4. Protocolo por hallazgo

Para cada hallazgo:

1. Confirmar que sigue vigente.
2. Identificar causa raíz.
3. Identificar componentes afectados.
4. Analizar dependencias.
5. Evaluar riesgo.
6. Definir pruebas antes del cambio.
7. Aplicar el cambio mínimo necesario.
8. Compilar.
9. Ejecutar pruebas específicas.
10. Ejecutar regresión.
11. Revisar efectos secundarios.
12. Documentar evidencia de cierre.

No eliminar funcionalidad para hacer pasar pruebas.
No desactivar validaciones.
No silenciar warnings.
No hardcodear valores como solución.
No alterar contratos públicos sin análisis de impacto.
No cambiar esquemas sin plan de migración.
No actualizar paquetes indiscriminadamente.

## 5. Cierre de hallazgos

Un hallazgo solo puede marcarse `RESUELTO` cuando:

- la causa raíz fue corregida;
- el proyecto compila, cuando aplique;
- las pruebas relevantes pasan;
- las pruebas de regresión pasan;
- no se detectaron efectos secundarios conocidos;
- existe evidencia de cierre.

Si no puede comprobarse, usar:

`CORREGIDO — NO VERIFICADO`

## 6. Gate final

Al terminar la reparación:

1. Generar informe de reparación.
2. Re-auditar áreas afectadas.
3. Comprobar nuevamente P0 y P1.
4. Comprobar integridad de datos.
5. Comprobar seguridad.
6. Comprobar build y pruebas.
7. Identificar regresiones nuevas.

No declarar el proyecto listo para producción solo porque los archivos fueron modificados.
