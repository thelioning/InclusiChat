# InclusiChat

Aplicación de mensajería privada e inclusiva construida con Flutter y
Supabase.

## Ejecutar en desarrollo

1. Copia `config/example.json` como `config/dev.json`.
2. Completa la URL y la clave pública de Supabase.
3. Ejecuta:

```powershell
flutter run --dart-define-from-file=config/dev.json
```

`config/dev.json` está excluido de Git. Nunca agregues una clave `service_role`
o `sb_secret_` a una aplicación cliente.

## Identidad visual

- Logo oficial HD: `assets/branding/inclusichat-logo-hd.png`.
- Todas las páginas principales deben usar `BrandLogo`.
- Las páginas internas deben usar `BrandAppBar` para mantener la identidad de
  InclusiChat de forma consistente.
- No se debe recrear, recolorear ni sustituir el logo dentro de una pantalla.

## Requisitos permanentes de producto

### Descubrimiento mediante teléfono y contactos

InclusiChat debe permitir encontrar contactos por número telefónico de forma
similar a WhatsApp. Este requisito incluye:

- registro y verificación del teléfono mediante OTP;
- normalización internacional E.164;
- permiso opcional y explicado para leer la agenda del dispositivo;
- coincidencia privada de contactos, evitando almacenar o exponer la agenda
  completa en texto legible;
- opción para impedir que una cuenta sea encontrada por su teléfono;
- bloqueo, reporte y revocación de contactos;
- nunca mostrar el teléfono a otros usuarios sin consentimiento explícito.

Durante la etapa inicial se usarán contactos de prueba. La verificación
telefónica y la sincronización de agenda se implementarán antes de considerar
la aplicación lista para uso público.

### Estados de mensajes

- Un visto gris: mensaje guardado en Supabase y enviado al servicio.
- Dos vistos fucsia: mensaje entregado al dispositivo o sesión del destinatario.
- Dos vistos morado claro: mensaje abierto y leído por el destinatario.

No se debe describir el visto gris solamente como «enviado»: siempre significa
«guardado y enviado». Los colores forman parte de la identidad de InclusiChat.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
