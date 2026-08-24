# Arquitectura propuesta de cifrado de extremo a extremo

## Estado actual

InclusiChat protege el transporte con TLS, restringe filas con RLS y guarda los
adjuntos en un bucket privado. El servidor todavía recibe contenido legible;
por tanto, la versión actual **no tiene cifrado de extremo a extremo (E2EE)**.

## Decisión de arquitectura

No se implementará criptografía propia. La fase E2EE debe integrar una
implementación mantenida y auditada de un protocolo estándar:

- chats directos y multidispositivo: gestión de sesiones equivalente a Sesame,
  acuerdo inicial PQXDH y Double Ratchet;
- grupos: evaluar MLS (RFC 9420) frente a sesiones por dispositivo;
- llamadas: conservar DTLS-SRTP/WebRTC y agregar verificación de identidad antes
  de afirmar seguridad equivalente a mensajeros maduros.

Referencias primarias:

- https://signal.org/docs/
- https://signal.org/docs/specifications/sesame/
- https://www.rfc-editor.org/rfc/rfc9420.html

## Modelo de claves

1. Cada instalación genera localmente su identidad y preclaves.
2. Las claves privadas permanecen en Android Keystore/iOS Keychain y nunca se
   guardan en Supabase.
3. Supabase publica solo material público firmado, sobres cifrados, estados de
   entrega y metadatos mínimos.
4. Cada mensaje usa una clave derivada desechable; los adjuntos se cifran con
   una clave aleatoria independiente antes de subirse.
5. La clave y el hash del adjunto viajan dentro del mensaje E2EE.
6. Nuevos dispositivos requieren vinculación autenticada y alertan al contacto.

## Cambios de datos previstos

- `user_devices`: clave pública, estado y revocación por dispositivo.
- `device_prekeys`: preclaves públicas de un solo uso y firmadas.
- `encrypted_envelopes`: destinatario por dispositivo, ciphertext, versión y
  contador; sin contenido legible.
- `conversation_security`: versión, época de grupo y verificación.
- Los nombres de archivo, captions y miniaturas también deben cifrarse.

## Requisitos de entrega

- migración explícita entre `legacy_transport` y `e2ee_v1`;
- verificación por código/QR y aviso de cambio de clave;
- protección contra replay, desorden y claves agotadas;
- copia de seguridad opcional cifrada con secreto ajeno al servidor;
- pruebas multidispositivo, reinstalación, revocación, uso sin conexión, grupos
  y recuperación ante pérdida;
- auditoría criptográfica externa antes de producción.

## Criterio de cierre

Este diseño impide una solución criptográfica improvisada, pero no implementa
E2EE. El hallazgo sigue **PARCIALMENTE RESUELTO** hasta completar implementación,
migración, pruebas y auditoría externa.
