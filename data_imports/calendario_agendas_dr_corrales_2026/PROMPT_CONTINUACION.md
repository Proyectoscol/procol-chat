Estoy continuando trabajo en el repo procol-chat (rama `calendario`). Antes de
hacer nada, lee completo
`data_imports/calendario_agendas_dr_corrales_2026/SESION_2026-11-24_EXPORT_IMPORT_PRODUCCION.md`
— ahí está documentado todo lo que se construyó y encontró en la sesión
anterior (feature de export/import de datos entre instancias, bot de
bienvenida manual, y 2 bugs críticos reales que se corrigieron: pérdida de
remitente en mensajes exportados, y una transacción gigante que se dañaba
con un solo error real y tumbaba todo en cascada).

Los últimos commits relevantes en la rama (en orden): `ea009da40`,
`db0f3d8a1`, `e2ad02daa`, `9dfb05d98`, `b53dcac88`. El último (`b53dcac88`)
es el fix crítico de savepoint por fila, ya verificado localmente con una
corrida real de punta a punta (0 errores en los 17 modelos). Confirma con
`git log --oneline -10` que esos commits están presentes antes de asumir
nada sobre el estado del código.

Lo que necesito que hagas, en este orden:

1. **Confirma el estado del redeploy en producción.** Pregúntame si ya
   reconstruí los contenedores (`docker compose -f
   docker-compose.production.yaml up -d --build`) con el commit
   `b53dcac88`, y si ya reintenté el import ahí. Si no lo he hecho, dame el
   comando. Si ya lo hice, pídeme el resultado (`stats` del
   `Calendario::AccountDataImport.last`) y confírmalo línea por línea contra
   lo que se documentó como "éxito" en la sesión anterior (0 errores en los
   17 modelos).

2. **Si el import en producción ya salió limpio**, el siguiente paso lógico
   es conectar/activar el inbox real de WhatsApp si todavía no está
   recibiendo tráfico real (ver la sección "Punto abierto" referenciada en
   el documento de sesión), y correr una verificación visual rápida de unas
   cuantas conversaciones importadas en el navegador real de producción.

3. **Arregla el bug crítico pendiente 5.1 del documento**: el formulario
   "Nuevo contacto" no permite crear contactos porque el backend exige
   `identifier`+`document_type` pero el formulario no tiene esos campos.
   Agrega esos campos a
   `app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue`
   condicionados a creación nueva (`is-new-contact`), reusando el enum ya
   existente en el modelo `Contact` (`document_type`: cc/ti/ce/pa/rc/pep/ppt).
   Prueba en el navegador real creando un contacto antes de darlo por
   resuelto.

4. **Arregla el pendiente 5.2**: agrega la opción "No encuentro a 'xxx xxx'
   → crear contacto nuevo" al modal de "Nuevo contacto en lista de espera",
   replicando el mismo patrón que ya existe en el flujo de "Agregar cita".

5. **Revisa el pendiente 5.4** (las 9 plantillas de WhatsApp sometidas a
   Meta) solo si te pregunto por eso explícitamente -- no es bloqueante y
   depende de un tiempo de aprobación externo que no controlamos.

No hagas commit ni push de nada sin que yo lo confirme explícitamente, igual
que en toda la sesión anterior. Si necesitas correr algo en el shell del VPS
de producción, dame el comando exacto para que yo lo corra y te pegue la
salida -- no tienes acceso directo a ese servidor.
