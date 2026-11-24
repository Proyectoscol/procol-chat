Estoy continuando trabajo en el repo procol-chat (rama `calendario`). Antes de
hacer nada, lee completo
`data_imports/calendario_agendas_dr_corrales_2026/SESION_2026-11-24_POST_IMPORT_FIXES.md`
— documenta todo lo que se hizo en la última sesión (varios bugs reales
corregidos ya pusheados, limpieza manual por SQL en producción ya
confirmada, hallazgo sobre contactos solo-username que no se pueden
mensajear nunca por Twilio, y una feature nueva de "valor a cobrar" por
cita). Si necesitas más contexto de cómo se llegó hasta ahí, el documento
de la sesión anterior sigue disponible en
`SESION_2026-11-24_EXPORT_IMPORT_PRODUCCION.md`.

Los últimos commits relevantes en la rama (en orden): `7c66a7e9a`,
`be89c9359`, `a75ccfdb9`, `493216aac`, `284c849ca`. Todos ya están
pusheados a `origin/calendario`. Confirma con `git log --oneline -10` y
`git status` que no hay nada raro antes de asumir el estado del código.

Lo que necesito que hagas, en este orden:

1. **Pregúntame si ya desplegué en el VPS el commit `284c849ca`** (el más
   reciente). Si no, dame el comando de rebuild
   (`docker compose -f docker-compose.production.yaml up -d --build`).

2. **Pregúntame si ya corrí en producción**
   `data_imports/calendario_agendas_dr_corrales_2026/split_consulta_ginecologia.rb`
   (sección 4.3 del documento de sesión) -- separa "Consulta" en
   urología/ginecología para que los precios por especialidad funcionen
   bien. Ya está probado en local (funciona), solo falta correrlo en
   producción. Si ya corrió, pregúntame si ya configuré los precios reales
   en `Ajustes → Servicios` (particular/EPS/plan complementario/prepagada/
   póliza) para los dos servicios.

3. **Retoma el Paso 3 pendiente (sección 4.4)**: las 3 plantillas reales de
   Twilio para "Al crear la cita" (particular/copago/EPS), usando
   `{{ appointment.price }}` / `{{ appointment.amount_to_collect }}` como
   variable en vez de precio fijo. Hay precedente de redacción en
   `create_appointment_templates.rb` (`confirmacion_particular` tiene el
   precio hardcodeado, hay que reescribirla con variable antes de
   someterla a Meta; `confirmacion_eps` no necesita cambios). Confirma
   conmigo el texto final de las 3 ANTES de someter nada -- una vez
   aprobado por Meta no se puede editar.

4. **Solo si pregunto explícitamente por ello**, retoma los pendientes 4.1
   (bug de `content_attributes` doblemente codificado en el import) y 4.2
   (el import fabrica un `source_id` inválido para contactos
   solo-username) -- ninguno de los dos es bloqueante hoy.

No hagas commit ni push de nada sin que yo lo confirme explícitamente. Si
necesitas correr algo en el shell del VPS de producción, dame el comando
exacto para que yo lo corra y te pegue la salida -- no tienes acceso
directo a ese servidor.
