# Backup obligatorio antes de promover REP-001

La organización Supabase de InclusiChat está actualmente en plan **Free**.

Supabase no ofrece los backups diarios restaurables de Pro/Team/Enterprise para este plan. Antes de aplicar `009` y `010` a producción se debe crear un dump lógico manual y conservarlo fuera del repositorio.

> **Nunca subir estos dumps a GitHub.** Pueden contener cuentas y datos reales.

## Requisitos locales

- Supabase CLI actual.
- Docker Desktop activo (el CLI usa `pg_dump` en contenedor).
- Contraseña de la base de datos de producción.
- Cadena de conexión Session Pooler o Direct del panel **Connect** de Supabase.

## Carpeta recomendada

Crear una carpeta fuera del repositorio, por ejemplo:

`InclusiChat_Backup_Pre_REP001_2026-08-23`

## Comandos oficiales

Sustituir `[CONNECTION_STRING]` por la cadena de conexión de producción. No pegar la contraseña en chats, commits, capturas públicas ni archivos del repositorio.

```bash
supabase db dump --db-url "[CONNECTION_STRING]" -f roles.sql --role-only
```

```bash
supabase db dump --db-url "[CONNECTION_STRING]" -f schema.sql
```

```bash
supabase db dump --db-url "[CONNECTION_STRING]" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
```

## Validación mínima

Antes de promover REP-001:

1. los tres comandos deben terminar sin error;
2. `roles.sql`, `schema.sql` y `data.sql` deben existir y tener tamaño coherente;
3. guardar una segunda copia fuera de la carpeta de trabajo si es posible;
4. registrar fecha/hora del backup, sin registrar la contraseña;
5. no modificar ni borrar el backup hasta que REP-001 haya sido validado en producción.

## Qué contiene

El dump lógico cubre estructura y datos PostgreSQL según el modo usado, incluyendo los elementos necesarios para recuperar tablas de aplicación y Auth de acuerdo con las herramientas de Supabase.

Los bytes almacenados mediante Supabase Storage no forman parte de un dump de base de datos. REP-001 no elimina ni reemplaza objetos de Storage, por lo que no se necesita copiar los archivos para esta promoción concreta. REP-003, que sí borrará recursos de Storage, deberá tener un procedimiento de backup/prueba específico antes de tocar producción.

## Gate

No ejecutar en producción:

- `20260823_009_deployed_schema_reconciliation.sql`
- `20260823_010_private_helper_rebinding.sql`

hasta que este backup haya sido creado y confirmado.

## Después del backup

1. repetir snapshot de producción en modo lectura;
2. verificar que no existe drift nuevo;
3. solicitar/registrar autorización explícita;
4. aplicar `009` y `010` en ese orden;
5. repetir pruebas de seguridad y Advisors;
6. si ocurre una regresión grave, seguir `docs/repair/rollback/REP-001_ROLLBACK.md`.
