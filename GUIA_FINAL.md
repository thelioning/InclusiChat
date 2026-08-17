# InclusiChat: Manual Completo de Usuario y Puesta en Marcha

InclusiChat es una aplicación de mensajería privada, inclusiva y con arquitectura **Zero-Cost ($0/mes)**, eliminando costes por SMS OTP e incorporando funciones exclusivas de protección comunitaria, privacidad de identidad y modo camuflaje.

---

## 📱 Manual de Uso de la Aplicación

### 1. Identidad Segura por `@alias` (Sin Número de Teléfono)
* **Privacidad Absoluta:** Nunca compartes tu número telefónico con desconocidos.
* **Tu Identificador:** Tus contactos te encuentran usando tu alias único (ej: `@carlos`, `@mayo`).
* **Edición de Perfil:** Puedes actualizar tu nombre público, alias y biografía en **Ajustes > Mi perfil**.

### 2. Cómo Agregar Contactos y Conectar
* **Buscar Usuarios:** Ve a la pestaña **Contactos** y presiona el botón morado **`+`**.
* **Escribe el @alias:** Escribe el nombre o alias de la persona y presiona **Buscar**.
* **Consentimiento Mutuo:** Pulsa **Conectar**. Al otro usuario le llegará una solicitud que puede **Aceptar** o **Rechazar**. Nadie puede enviarte mensajes sin tu aprobación previa.
* **Invitar por WhatsApp:** Si tu amigo aún no tiene InclusiChat, pulsa el botón verde **«Invitar amigos por WhatsApp»** en la lista de contactos para enviarle el enlace directo y tu alias con un solo toque.

### 3. Modo Camuflaje y PIN Secreto Personalizable
* **Activación de Emergencia:** Toca el icono de camuflaje (ojo tachado) en la barra superior. La app se convertirá instantáneamente en una **Calculadora estándar 100% funcional**.
* **PIN Inicial de Fábrica:** Viene con el PIN de prueba **`1234`**. Para desbloquearla, digita `1234` en la calculadora y presiona la tecla **`=`**.
* **Personalización Obligatoria del PIN:**
  1. Ve a **Ajustes** -> **Privacidad y camuflaje**.
  2. Verás el aviso de seguridad recomendando cambiar el PIN por defecto.
  3. Pulsa **Personalizar mi PIN**.
  4. Digita tu nuevo PIN de 4 a 6 dígitos y confírmalo.
  5. El nuevo PIN se guardará permanentemente en tu teléfono para que solo tú sepas cómo desbloquearla.

### 4. Llamadas y Videollamadas Cifradas
* Dentro de cualquier conversación, pulsa el icono de **Teléfono** (Llamada de voz) o **Cámara** (Videollamada).
* Cuentas con controles en pantalla para silenciar micrófono, cambiar a altavoz, encender/apagar cámara y temporizador de llamada activa.

### 5. Adjuntos y Notas de Voz Seguras
* **Multimedia:** Pulsa el icono de clip para enviar fotos, documentos seguros o ubicación.
* **Notas de Audio:** Toca el icono de micrófono para abrir el grabador de notas de voz cifradas de extremo a extremo.

### 6. Eliminación Definitiva de Cuenta (Derecho al Olvido)
* Si decides no seguir utilizando la app, ve a **Ajustes** -> **Seguridad y blindaje** -> **`Eliminar mi cuenta y borrar mis datos`**.
* El sistema borrará de forma irreversible tu perfil, mensajes, contactos y registro de usuario de los servidores.

---

## 🛠️ Puesta en Marcha y Archivos del Proyecto

* **Instalable Oficial de Android:** [`InclusiChat-v1.0.apk`](file:///c:/Users/elmacho/Projects/InclusiChat/InclusiChat-v1.0.apk)
* **Web Oficial & Baremetal Academy:** [`web/index.html`](file:///c:/Users/elmacho/Projects/InclusiChat/web/index.html)
* **Esquema de Base de Datos Supabase:** [`supabase_schema.sql`](file:///c:/Users/elmacho/Projects/InclusiChat/supabase_schema.sql)

---

## 🚀 Cómo Ejecutar la App en Desarrollo

```powershell
cd app
flutter run --dart-define-from-file=config/dev.json
```
