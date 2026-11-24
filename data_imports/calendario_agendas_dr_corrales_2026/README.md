# Normalización de "AGENDAS DR CORRALES 2026.xlsx"

Fuente: `source/AGENDAS DR CORRALES 2026.xlsx` (dentro de esta misma carpeta
-- ahi tambien van los proximos documentos que se sumen a este import;
**no se sube a git**, contiene datos reales de pacientes). Procesado con
`normalize.py` (Python + openpyxl), con reglas escritas a mano a partir de
inspeccionar el contenido real del archivo -- no es un parser genérico.

## Resultado

- **2,275 filas normalizadas** en `agendas_normalizadas.csv`.
  - 1,935 **programadas** (tienen fecha confiable).
  - 340 **sin fecha → lista de espera** (`estado = lista_espera`).
- **1,188 filas marcadas para revisión humana** en `revision_requerida.csv`
  (mismo contenido + columna `motivo_revision` explicando por qué). La
  mayoría (855) son fechas de las hojas maestras que no traían año explícito
  en el Excel -- ver punto 1 de "Hallazgos" abajo.

| Hoja origen | Filas | Tipo |
|---|---|---|
| CONSULTAS UROLOGIA | 989 | `consulta_maestro` |
| PROCEDIMIENTOS UROLOGIA | 206 | `procedimiento_maestro` |
| DR CORRALES | 852 | `agenda_profesional` |
| DRA ESPAÑA | 149 | `agenda_profesional` |
| DR GAVIRIA | 53 | `agenda_profesional` |
| DR VELEZ | 20 | `agenda_profesional` |
| DR DEVIA | 6 | `agenda_profesional` |

## Columnas del CSV normalizado

`fuente_hoja, fuente_fila` -- trazabilidad: en qué hoja/fila del Excel original está cada registro, para poder verificar cualquier duda contra el archivo fuente.

`tipo_documento, numero_documento, nombre` -- documento y nombre del paciente, solo recortados de espacios.

`telefono_1, telefono_2, telefono_extra` -- el Excel traía "3000000001-3000000002" en una sola celda. Se separó en columna 1 (principal) y columna 2 (respaldo). Cuando había un tercer número o uno de largo inválido, se guarda en `telefono_extra` sin perderlo, pero **no se usó como teléfono 1 o 2** (ver "Revisión requerida").

`entidad_eps` -- texto de la EPS/aseguradora, limpio de espacios dobles y de los typos más comunes del archivo (ej. "COLSSANITAS"→"COLSANITAS", "PIJASO SALUD"→"PIJAO SALUD"). Cuando la celda traía la EPS + una nota pegada ("LOS ROSALES CONTROL CX 18"), se dejó solo la EPS.

`especialidad` -- "Urologia" para todo el archivo (coincide con el módulo Calendario ya creado en el sistema).

`profesional` -- a quién pertenece la cita. Para las hojas por-doctor, normalmente es la hoja misma (Dr. Corrales, Dr. Devia, Dr. Velez, Dr. Gaviria, Dra. España), **excepto** cuando el título del bloque menciona explícitamente a otro doctor -- ver "Hallazgo: Dr. Heredia" abajo. Para las hojas maestras, se resolvió buscando "DR X" / "DRA X" en la columna FECHA PROGRAMACION o en OBSERVACION (ej. "PROGRAMAR DRA ESPAÑA"); si ninguna de las dos lo menciona, queda vacío (558 filas, casi todas en lista de espera -- normal, todavía no se decide quién las atiende).

`servicio_normalizado, servicio_raw` -- `servicio_raw` es el texto literal del Excel; `servicio_normalizado` lo agrupa en: Consulta, Control, Cistoscopia, Urodinamia, Vasectomia, Urocultivo, Biopsia de prostata, Post quirurgico, Retiro de cateter, u "Otro" cuando no calzó con nada (solo 3 casos -- ver revisión).

`fecha_programada, fecha_confianza` -- fecha ISO (`YYYY-MM-DD`). `fecha_confianza` indica qué tan confiable es:
  - `confirmada`: viene del título de un bloque de agenda (ej. "CONSULTAS LUNES 16 DE ENERO") -- 1,080 filas, todas las de las hojas por-doctor.
  - `estimada_sin_anio`: la celda "FECHA PROGRAMACION" de las hojas maestras traía una fecha o un texto SIN año (ver "Hallazgo 1" abajo) -- se asumió 2026 (año del título del archivo). **855 filas**, por eso están TODAS en `revision_requerida.csv`: antes de cargarlas conviene que alguien de la clínica confirme que el año es realmente 2026 y no, por ejemplo, 2025 en los meses de enero/febrero (el libro mezcla datos de distintos años).
  - `sin_fecha`: no hay fecha → `estado = lista_espera`. 340 filas.

`hora_programada` -- solo en hojas por-doctor. El Excel guarda horas sin AM/PM (ej. "1:00" puede ser 1pm). Se resolvió con una regla fija, verificada contra los bloques que SÍ traen el sub-encabezado explícito "MAÑANA"/"TARDE": bajo "MAÑANA" solo aparecen horas 7-11 (nunca 1-6), bajo "TARDE" solo aparecen horas 1-5 (nunca 7-11) -- es decir, este consultorio nunca atiende antes de las 7am ni después de las 6pm. Por eso la regla se aplica sin importar la posición dentro del bloque: **hora 1-6 → siempre tarde (+12h)**, **hora 7-11 → siempre mañana**, **hora 12 → mediodía**. (La versión anterior de este script intentaba adivinarlo seguiendo la secuencia fila a fila, y fallaba en bloques que arrancan directo en la tarde sin pasar antes por la mañana -- esta regla fija es más simple y mucho más confiable).

`estado` -- `programada` o `lista_espera` (sin fecha confiable = lista de espera, tal como se pidió).

`consultorio` -- número de consultorio cuando el título del bloque lo menciona.

`observacion, notas_adicionales` -- texto libre tal cual, solo recortado de espacios. No se intentó re-interpretar más allá de lo descrito arriba (ej. "OK LA PC" significa "confirmado con el/la paciente", pero se dejó tal cual porque es información útil para el personal, no un dato a transformar).

`bloque_titulo_raw` -- el título completo del bloque de agenda (hojas por-doctor) o el contenido crudo de FECHA PROGRAMACION (hojas maestras), para que cualquier duda sobre cómo se interpretó una fecha se pueda verificar a simple vista.

## Hallazgos importantes (para decisión del administrador, no se resolvieron solos)

### 1. Columna "FECHA PROGRAMACION" de las hojas maestras está muy contaminada
No es una fecha confiable en la mayoría de los casos. Se encontraron:
- Fechas tipo Excel con **años sin sentido** (2005, 2009, 2019, 2002, 2016, 1930, 2023, 2027...) -- son un artefacto de Excel autocompletando un año cuando alguien escribió solo "26 ene" sin año. Se descartó siempre el año de estas celdas y se reemplazó por 2026.
- Texto libre en vez de fecha, en dos órdenes distintos: "DRA ESPAÑA MARZO 25" (mes antes del día) o "16 DE ENERO" (día antes del mes, como en los títulos de bloque). El script reconoce ambos órdenes. Ejemplos: "PROGRAMAR DRA ESPAÑA", "SANIDAD MILITAR JEFE MAYRA", "OK CITA COSMITET" (sin fecha reconocible → lista de espera); "ABRIL 15 DR CORRALES", "ENERO 26 DRA ESPAÑA" (fecha reconocida, año asumido 2026).
- **Ninguna de estas 855 fechas trae año explícito en el Excel** -- se asumió 2026 por ser el año del título del archivo, pero esto es una suposición, no un dato confirmado. Por eso TODAS quedaron en `revision_requerida.csv`.

### 2. "Profesional cruzado": el Dr. Heredia aparece en la hoja "DR CORRALES"
El bloque "CONSULTORIO 2" de varios lunes en la hoja DR CORRALES en realidad
es agenda del **Dr. Heredia** (mencionado en una celda vecina al título del
bloque), no del Dr. Corrales. **17 filas** quedaron asignadas a "Dr. Heredia".
Dr. Heredia **no existe hoy como profesional en el sistema** -- hay que
decidir si se crea como profesional nuevo o si esas 17 citas se reasignan a
otro doctor antes de cargarlas.

También hay casos puntuales donde el campo PROCEDIMIENTO menciona a otro
doctor (ej. "POST QCO JUNIO 12 DRA ESPAÑA" dentro de la hoja DR CORRALES) --
esas SÍ se reasignaron automáticamente a la doctora mencionada, porque ahí
la mención es claramente "a quién le toca este control", no una referencia
externa.

**Importante:** menciones de doctor dentro de las notas/observaciones (ej.
"DR ECHEVERRY-AUT DRA CANO") **NO se usaron para reasignar** -- esos son
médicos que autorizan/remiten al paciente, no quien lo atiende. Quedan
marcadas en `revision_requerida.csv` por si acaso, pero el profesional de la
fila no cambió.

### 3. Filas con dato clave faltante (14 filas)
Documento, teléfono o fecha vacíos tras la normalización -- no se inventó
ningún valor, quedaron vacíos y marcados para completar a mano antes de
cargar.

### 4. 2 filas con procedimiento irreconocible
La celda de PROCEDIMIENTO en realidad tenía una EPS pegada por error de
digitación en el Excel original (ej. "COLSANITAS" en vez de un procedimiento).
Visibles en `revision_requerida.csv` como "procedimiento no reconocido".

## Qué NO se hizo (a propósito)

- No se intentó adivinar el profesional de las 558 filas de las hojas
  maestras que no mencionan ningún doctor -- es información que no está en
  el archivo, inventarla sería peor que dejarla en blanco. **No se
  importaron** (quedan en `pendientes_sin_profesional.csv`).
- No se tocó el archivo Excel original en ningún momento (solo lectura).

## Segunda fase: preparación e importe local (`prepare_import.py` + `import_to_local.rb`)

`prepare_import.py` toma `agendas_normalizadas.csv` y arma los 4 archivos
que el importador de Rails consume:

- `contacts.csv` -- **879 pacientes únicos** (deduplicados por número de
  documento; cuando el mismo paciente aparece en varias hojas, se queda con
  el dato más frecuente de nombre/teléfono/EPS entre todas sus apariciones).
- `appointments.csv` -- **1,139 citas reales**. Fusiona los duplicados entre
  hojas maestras y hojas por-doctor (cuando el mismo documento+fecha aparece
  en ambas, la observación de la hoja maestra se agrega como nota a la cita
  de la hoja por-doctor en vez de crear un registro repetido).
- `waitlist.csv` -- **41 entradas de lista de espera** (sin fecha, pero con
  profesional resuelto).
- `pendientes_sin_profesional.csv` -- **564 filas que NO se importan**: sin
  profesional resuelto en ninguna columna del Excel original.

`import_to_local.rb` carga esos 4 CSV a la base de datos local:

```
bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/import_to_local.rb
```

- Primero **borra** (solo de esta cuenta): citas, lista de espera, días
  abiertos y contactos. No toca usuarios, profesionales/servicios/EPS ya
  configurados, ni ninguna otra cuenta.
- Crea los contactos, luego las citas (usando `historical_import: true` en
  `Calendario::Appointment` para que no dispare triggers/webhooks reales
  sobre citas de hace meses, y para que un "Control" sin consulta previa
  registrada en el sistema no sea rechazado -- ver `app/models/calendario/appointment.rb`),
  luego la lista de espera, y por cada cita abre el día correspondiente
  (`Calendario::OpenDayCoverage`) para que aparezca en la pestaña Agendas.
- Variables de entorno: `DRY_RUN=1` corre todo dentro de una transacción y
  hace rollback al final (para probar sin arriesgar nada); `SKIP_WIPE=1`
  no borra, solo agrega; `ACCOUNT_ID=N` para otra cuenta.
- Al terminar escribe `import_report.txt` con el resumen y la lista
  completa de errores.

**Resultado de la carga en este ambiente local:** 879 contactos, 1,139
citas, 41 en lista de espera, 0 errores de citas (33 "errores" de contacto
son solo teléfonos duplicados entre dos pacientes distintos del Excel
original -- el contacto se creó igual, sin ese teléfono principal). Se
verificó visualmente en Agendas, Vista calendario y Lista de espera que los
datos se ven correctos (horarios dentro de 7am-5pm, nombre/documento/
teléfono/servicio/EPS visibles).

**Para repetir la carga con un Excel actualizado** (ej. antes de migrar a
producción): reemplazar `source/AGENDAS DR CORRALES 2026.xlsx` dentro de
esta carpeta y correr en orden `python3 normalize.py`, `python3
prepare_import.py`, luego el importador de Rails.

## Archivos

- `agendas_normalizadas.csv` -- las 2,275 filas normalizadas (fase 1).
- `revision_requerida.csv` -- subconjunto (1,188 filas) con columna
  `motivo_revision` explicando qué revisar en cada una.
- `contacts.csv`, `appointments.csv`, `waitlist.csv`,
  `pendientes_sin_profesional.csv` -- los 4 archivos listos para cargar
  (fase 2, generados por `prepare_import.py`).
- `import_report.txt` -- reporte de la última carga a la base de datos
  (generado por `import_to_local.rb`).
- `normalize.py`, `prepare_import.py`, `import_to_local.rb` -- los 3 scripts
  del pipeline completo, en orden.

## Fase 2 (2026-11-16/17)

Ver `CONTEXTO_NEGOCIO_FASE2.md` para todo el contexto de negocio y las
decisiones del usuario que motivan lo de abajo. `normalize.py` v2
reemplaza por completo al de fase 1 (mismas reglas, 3 fuentes en vez de 1):

- `source/AGENDAS DR CORRALES 2026 actualizado.xlsx` -- reemplaza al
  archivo de fase 1. Mismas hojas por-profesional + hoja nueva `CONS
  ROSALES` (pacientes de Los Rosales del mismo Dr. Corrales, NO agenda
  aparte).
- `source/URODINAMIAS 2026 (1).xlsx` -- SOLO la hoja `LISTADO PC
  URODINAMIAS`. El resto del archivo (~75 hojas, igual a "AGENDAS DRA
  CANO 2026.xlsx") se descarta: fechas internas de 2014, confirmado
  basura por el usuario.
- `source/PARTICULARES 2026.xlsx` -- SOLO `AGENDA DRA CANO` y `AGENDA
  DR. CORRALES ` (agendas particulares reales). El resto (PENDIENTES,
  TERAPIAS, SEGIMIENTO TECART, MEDPLUS/SURA, RELACION CITOLOGIAS,
  TELEFONOS, Hoja1) queda fuera de esta ronda -- son modulos nuevos
  (cartera de Mayra, conciliacion de facturacion) o dominios distintos
  (laboratorio), no agenda de citas.

Profesionales nuevos: **María** (Urodinamia + Uroflujometría) y **Dra.
Cano** (= "Lida", ginecología, agenda particular). Dr. Heredia se
mantiene igual que en fase 1 (17 citas reales, confirmado por el usuario
que NO se reasignan). Dr. Piedrahita y Dr. Federico (solo menciones en
`HORAS MEDICO APOYO`) **no** se crean como profesionales.

Hallazgo nuevo de `prepare_import.py` v2: 90 colisiones reales de
(documento, fecha) **entre dos hojas "por profesional"** (ej. el mismo
paciente en `AGENDAS` y en `CONS ROSALES`, o en `AGENDAS` y en `AGENDA
DR. CORRALES` particular) -- la fase 1 solo dedupeaba maestra-vs-
profesional, no profesional-vs-profesional. Se generalizó el dedup para
cubrir este caso: se fusionan como nota en la cita que sí se queda, nunca
se duplica.

**Resultado de la última corrida (dry-run, 2026-11-17):** 1,701
contactos, 2,172 citas, 150 en lista de espera (113 de ellas Urodinamia
de María), 0 errores de citas/lista de espera, 64 "errores" de contacto
benignos (mismo patrón que fase 1: teléfono principal duplicado entre dos
pacientes distintos, el contacto se crea igual sin ese teléfono). 681
filas quedaron sin importar por falta de profesional resuelto en el
Excel original (`pendientes_sin_profesional.csv`).

## Fase 3 -- resincronización con Excel actualizado (2026-11-21)

El usuario señaló que los archivos directamente en `source/` (los mismos
de Fase 2, sin tocar desde el 16/17 de noviembre) ya estaban desactualizados
frente a la agenda real -- confirmado comparando byte a byte
`agendas_normalizadas.csv` recién generado contra el de Fase 2: **0
diferencias**. Los archivos vigentes de verdad estaban en
`source/chats_batch_2/citas/` (un dump más reciente, sin los sufijos
"actualizado"/"(1)"), con mtime del 2026-11-20 y contenido que sí llega
hasta el 27 de noviembre (confirmado buscando "24 DE NOVIEMBRE" en la hoja
`AGENDAS ` de ese archivo).

Se copiaron esos 3 archivos a `source/` con el nombre exacto que
`normalize.py` espera (sobrescribiendo los viejos, que quedaron respaldados
fuera del repo antes de sobrescribir):
- `chats_batch_2/citas/AGENDAS DR CORRALES 2026.xlsx` -> `source/AGENDAS DR CORRALES 2026 actualizado.xlsx`
- `chats_batch_2/citas/URODINAMIAS 2026.xlsx` -> `source/URODINAMIAS 2026 (1).xlsx`
- `chats_batch_2/citas/PARTICULARES 2026.xlsx` -> `source/PARTICULARES 2026.xlsx`

**Auditoría del cambio real** (diff de `appointments.csv` por clave
documento+fecha+profesional+servicio, antes/despues, sin exponer datos de
pacientes): 49 citas nuevas (sobre todo Dr. Corrales 23-27 nov y
María/Urodinamia 19-26 nov), 4 citas de Dr. Corrales del 20 de noviembre
que ya no aparecen, 4 cambios de estado de asistencia en citas de María
(18-20 nov, quedaron marcadas `revisar_color` -- el color de la fila
cambió). **Hallazgo pendiente:** la agenda particular de la Dra. Cano
("Lida", hoja `AGENDA DRA CANO` dentro de `PARTICULARES 2026.xlsx`) quedó
**exactamente igual** (375 citas antes y después) -- la cancelación/
reprogramación que el usuario mencionó (comunicada verbalmente, no
confirmada en ningún Excel disponible) no está reflejada todavía en
ningún archivo fuente. El archivo suelto `AGENDAS DRA CANO 2026.xlsx` no
ayuda: mismas ~75 hojas basura (2014-2018) que `URODINAMIAS 2026.xlsx`,
más dos hojas de ginecología (`CONSULTAS GINECOLOGIA`, `PROCEDIMIENTOS
GINECOLOGIA`) sin estructura de agenda por día (parecen lista de
pendientes, no agenda con asistencia). El usuario decidió seguir adelante
sin resolver este punto ("deja así") -- queda pendiente para la próxima
actualización de Excel que sí lo incluya.

**Resultado de la carga real** (no dry-run, 2026-11-21): **2,182
contactos, 2,845 citas, 141 en lista de espera pendiente + 149 cumplida**.
0 errores de citas, 78 errores benignos de contacto/lista de espera
(mismo patrón de siempre: teléfono principal duplicado entre dos
pacientes distintos). 669 filas sin importar por falta de profesional
resuelto (`pendientes_sin_profesional.csv`). Se corrió primero con
`DRY_RUN=1` para confirmar que no hubiera sorpresas antes de la carga
real -- mismo resultado en ambas corridas.

**Nota operativa importante:** desde la carga de Fase 2 (17 de
noviembre), el personal había marcado manualmente 12 citas reales en la
app (confirmada/atendida/no-asistió) el 18 de noviembre. El usuario
confirmó explícitamente que esos clics fueron solo de prueba y que **el
Excel es la única fuente de verdad** -- por eso esta carga de Fase 3 hizo
el mismo wipe-and-reload completo de siempre (nunca un merge selectivo),
y esos 12 cambios manuales se perdieron a propósito, no por error.

## Fase 4 -- reintento del import de chats de WhatsApp + contactos de Google (2026-11-22/23)

Continuación directa del incidente documentado en
`docs/incidents/2026-11-21-whatsapp-import-sent-real-messages.md`. Con el
guard `historical_import` ya en su lugar, se resolvieron los 76 batches
de `Import::WhatsappChatBatch` que habían quedado en `needs_review` tras
la primera corrida, y se reforzó la seguridad del import antes de volver
a correrlo.

**Capa de seguridad adicional:** todo mensaje que crea
`Import::WhatsappChatImportService` ahora lleva también `private: true`
(antes solo tenía `source_id` + `historical_import`).
`Base::SendOnChannelService#invalid_message?` se niega a enviar un
mensaje privado sin importar el canal -- es una barrera independiente de
`historical_import`, pedida explícitamente para que ningún guard sea la
única defensa antes de pasar al número real en producción. Se corrió un
script retroactivo sobre los 3171 mensajes ya importados (de la corrida
del incidente, que nunca habían recibido `historical_import` ni
`private` porque se crearon antes de ese fix) para marcarlos igual.

**Bug real encontrado y corregido:** `normalized_wa_id` le pasaba `'CO'`
como región por defecto a `TelephoneNumber.parse` incluso cuando el
número ya traía su propio código de país (`+506`, `+1`) -- la librería
lo validaba como si fuera colombiano e ignoraba el código real,
rechazando números internacionales legítimos (Costa Rica, EEUU). Ahora
solo se usa `'CO'` como respaldo cuando el número no trae `+`.

**Soporte para contactos sin teléfono (usuario de WhatsApp):** desde que
WhatsApp permite identificar contactos por un nombre de usuario en vez
del número, algunos exports de chat no traen ningún teléfono (ej.
"Chat de WhatsApp con @yoli.areiza.zip"). Se investigó cómo lo resuelve
Chatwoot mismo para la API de Meta
(`Whatsapp::IdentifierSyncService`/`Whatsapp::IncomingMessageIdentifierHelper`,
que usan un "LID" de Meta en vez de teléfono) y se replicó el mismo
patrón para el import histórico:
- El contacto se crea sin `phone_number`, con el usuario guardado en
  `additional_attributes.social_profiles.whatsapp` /
  `social_whatsapp_user_name` -- el mismo lugar que ya lee el resto de
  la UI.
- `ContactInbox.source_id` usa un identificador sintético
  (`whatsapp:@usuario`, ver `WHATSAPP_IMPORT_USERNAME_PATTERN` en
  `lib/regex_helper.rb`) que un webhook real de Twilio o Meta nunca
  puede producir, así que no hay forma de que choque con un contacto
  real ni de que dispare un envío.
- Estas conversaciones quedan como historial de solo lectura hasta que
  se conozca el teléfono real de la persona -- hoy ni Twilio ni la API
  de Meta permiten enrutar mensajes nuevos solo por este username.

**Resolución de los needs_review por nombre:** varios exports solo traen
el nombre guardado en el celular que exportó, sin número. Se cruzaron
contra `chatsexport/contactsfromgoogletochatwootdb/contacts.csv` (export
de Google Contacts, 841 filas) y, para los que no aparecían ahí, contra
la tabla `contacts` ya poblada por la Fase 3 (base real de pacientes).
**Importante:** un cruce automático inicial le asignó a "Paula Andrea
Ramos Ramos" un número sin darse cuenta de que el CSV tiene 2 contactos
distintos con ese nombre exacto y números distintos -- se detectó,
se revirtió lo ya creado (conversación + contacto) y se dejó el batch en
`needs_review` con una nota explicando la ambigüedad. Ningún otro nombre
cruzado tenía este problema (se verificó uno por uno).

**Resultado final:** 59 batches adicionales completados (6 por el fix de
teléfono internacional, 11 por cruce de nombre, 51 por el soporte de
usuario sin teléfono -- incluyendo "@Marce93S" y "@Marce93S 2", que
resultaron ser el mismo chat exportado dos veces y se fusionaron en el
mismo contacto), **783 mensajes nuevos**, todos verificados con las 3
marcas de seguridad. Quedan 7 en `needs_review`: 3 por un problema
distinto y anterior ("el remitente 'nosotros' nunca aparece en ese
chat"), 2 nombres sin ningún match posible (Heliomathi, Hector
Velásquez Duque), y la ambigüedad de Paula Andrea Ramos Ramos pendiente
de que el usuario confirme el número correcto.

También se subieron los 841 contactos del CSV de Google como `Contact`
nuevos (sin `ContactInbox` ni conversación -- cero riesgo de disparar el
bot, que solo reacciona a `message_created`): 644 creados, 147 ya
existían (mismo teléfono), 50 con teléfono inválido en el CSV mismo.

La página de carga (antes construida pero nunca conectada a ningún
menú) ahora vive en Ajustes → Importar WhatsApp
(`accounts/:accountId/settings/import-whatsapp`), con selector de
bandeja destino incluido.

## Fase 5 -- chats_batch_5 (51 exports) + hallazgo: `import_to_local.rb` choca con los chats de WhatsApp (2026-11-23)

Mismo proceso que Fase 4 sobre `chatsexport/chats_batch_5/`: 50/51
completados (789 mensajes nuevos verificados), 1 (Valentina Arana) sin
teléfono encontrable. Fix adicional en el importador: un chat donde el
paciente escribió pero el staff *todavía no ha contestado* tiene un solo
remitente -- eso no es ambiguo (nunca se podría confundir con "nosotros"),
así que `validate_senders!` ya no lo manda a `needs_review`, lo importa
igual con todo como entrante.

**Hallazgo importante, encontrado de la forma difícil:** al correr
`import_to_local.rb` para traer una actualización de las agendas (Excel),
el paso de wipe (`account.contacts.find_each(&:destroy!)`, pensado para
borrar SOLO datos de Calendario antes de que existiera el importador de
WhatsApp) borra **TODOS** los contactos de la cuenta -- y
`Contact#conversations`/`#contact_inboxes`/`#messages` usan
`dependent: :destroy_async`, así que el borrado en cascada de
conversaciones/mensajes de WhatsApp corre en segundo plano vía Sidekiq,
no al instante, lo cual lo hizo fácil de pasar por alto en el momento (el
conteo de mensajes parecía normal justo después de correr el script, y
solo bajó a casi cero un par de minutos después, cuando los jobs en cola
terminaron). Se perdieron las ~285 conversaciones/mensajes de WhatsApp
completados hasta ese momento.

**Recuperado sin pérdida real:** los 293 registros de
`Import::WhatsappChatBatch` (con sus `.zip` adjuntos) no se tocan en este
wipe -- se reiniciaron a `pending` y se reimportaron los 285 que estaban
`completed`, 0 errores, mismas 3 marcas de seguridad verificadas en los
~3900 mensajes resultantes. También se volvió a correr el import de
contactos del CSV de Google.

**Para la próxima vez que se actualicen las agendas de Excel:** antes de
correr `import_to_local.rb`, respaldar/anotar cuántas conversaciones de
WhatsApp existen, y después de correrlo, esperar a que los jobs
`DestroyAssociationAsyncJob` de Sidekiq terminen (o revisar la cola) antes
de asumir que el conteo de mensajes es el final -- y si bajó a casi cero,
reimportar los batches `completed` de `Import::WhatsappChatBatch` de
inmediato. Una solución más permanente (pendiente, no implementada):
separar el wipe de "contactos de Calendario" (los que vienen del Excel)
de "contactos con WhatsApp real" para que este script deje de tocarlos.

## Fase 6 -- chats_batch_6 (2 exports) + los últimos needs_review resueltos a mano (2026-11-23)

El usuario dio directamente el teléfono correcto para los 5 casos que
ningún cruce automático pudo resolver (Valentina Arana, Paula Andrea
Ramos Ramos -- resolviendo la ambigüedad del CSV de Google a favor de
320 2977480 --, Heliomathi, Hector Velásquez Duque, Azucena De María
Alzate Ospina). De paso se reintentaron los 3 "el remitente 'nosotros'
nunca aparece en este chat" que quedaban pendientes del fix de chat
unilateral (Fase 5) -- los 3 eran justamente eso, el paciente escribió y
el staff nunca contestó; los 3 se importaron limpio.

`chats_batch_6/` (2 exports, ambos de "nombre de usuario" sin teléfono)
se procesó igual que las rondas anteriores.

**Resultado: 0 batches en `needs_review`** -- primera vez que la cola
queda completamente limpia. 65 mensajes nuevos, 100% verificados con las
3 marcas de seguridad.
