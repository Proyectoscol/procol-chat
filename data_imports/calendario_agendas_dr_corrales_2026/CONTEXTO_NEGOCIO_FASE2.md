# Contexto de negocio -- Fase 2 (post primera carga)

Capturado el 2026-11-16, a partir de una explicación extensa del usuario sobre
cómo opera hoy la asistente con los Excel reales, justo después de subir 5
archivos nuevos a `source/`. Este documento es la bitácora de requisitos
para que nada de lo dictado se pierda antes de construir la siguiente
versión del parser (`normalize.py` v2) y las features de producto que
dependen de él. No es un diseño aprobado -- es la materia prima para uno.

## Archivos nuevos en `source/` (inspeccionados, no parseados todavía)

- `AGENDAS DR CORRALES 2026 actualizado.xlsx` -- versión más reciente del
  archivo ya importado en fase 1. Mismas hojas (`CONSULTAS/PROCEDIMIENTOS
  UROLOGIA`, `DR DEVIA/VELEZ/GAVIRIA/DRA ESPAÑA`) más 4 hojas nuevas:
  `AGENDAS` (reemplaza/extiende a `DR CORRALES`), `HORAS MEDICO APOYO`,
  `CLAVES` (**contiene credenciales reales, ver advertencia de seguridad
  abajo -- no leer su contenido en ningún proceso automático**), `CONS
  ROSALES`.
- `AGENDAS DRA CANO 2026.xlsx` y `URODINAMIAS 2026 (1).xlsx` -- **el mismo
  archivo** (contenido idéntico en las ~75 hojas que se revisaron), un
  histórico mucho más grande: bloques de agenda diarios desde septiembre
  2025 hasta enero 2026+ para urodinamia/uroflujometría, consultas de
  ginecología (Dra. Cano, Dr. Espitia), procedimientos, más hojas maestras
  de pendientes (`PENDIENTES DEL DR CORRALES`, `CONS PENDIENTES CAFE
  SALUD`, `PENDIENTES MEDIMAS`, `LISTADO PC URODINAMIAS`) y una hoja de
  preparación (`PREPARACION URODINAMIA`, `PREPARACION BX`). Mucho más
  irregular que el archivo de fase 1 -- nombres de hoja con typos/fechas de
  año incorrecto (ej. "03 DE ENERO 2015"), tamaños de hoja muy dispares.
- `PARTICULARES 2026.xlsx` -- la cartera/facturación de pacientes
  particulares y de paquetes de terapias: `PENDIENTES`, `AGENDA DRA CANO`,
  `AGENDA DR. CORRALES`, `TERAPIAS`, `TELEFONOS`, `RELACION CITOLOGIAS
  2026`, splits por pagador (`DRA CANO MEDPLUS`, `DR CORRALES MEDPLUS`,
  `DRA CANO SURA`, `DR CORRALES SURA`), `FECHAS TERCARTERAPIA`,
  `SEGUIMIENTO TECART`.
- `PARTICULARES 2026 (Autoguardado).xlsx` -- autoguardado del anterior, muy
  probablemente descartable (confirmar con el usuario antes de borrar).

Confirmado con datos reales (hoja `LISTADO PC URODINAMIAS`): sí hay
**relleno de color por celda** en estas hojas (verde `92D050`, amarillo
`FFFF00`, rojo `FF0000`, blanco/banda alterna de lectura `F6F8F9`/blanco
puro) -- el color-coding que describe el usuario es real y vive en el
`fill.fgColor` de cada celda, no en el texto. Falta confirmar en qué hoja(s)
exactas aparece el "morado" que menciona para "ya agendado" (no apareció en
la muestra revisada de `LISTADO PC URODINAMIAS`) y el verde/amarillo/blanco
de cartera en `TERAPIAS`/`FECHAS TERCARTERAPIA` -- pendiente de inspección
fila por fila antes de escribir las reglas del parser v2.

## Reglas de negocio para el parser v2 / modelo de datos

Estas son las reglas que SÍ hay que construir (parser y/o schema) para que
la carga real sea correcta, no solo "legible":

1. **Profesionales nuevos a crear**, con un matiz importante: no son
   doctores, son personal técnico/agente que ejecuta un procedimiento
   específico.
   - **María**: hace **Urodinamia** y **Uroflujometría** (especialidad
     Urología). Hay que crearla como `Calendario::Professional` con esos
     dos servicios asignados (`Calendario::ServiceProfessional`), para que
     se le pueda abrir agenda y agendarle esas citas igual que a un doctor.
     El modelo actual no distingue "doctor" vs "agente técnico" -- no hace
     falta un campo nuevo, basta con no mezclar su agenda con la de
     consulta médica; confirmar si esto es suficiente o si el usuario
     quiere un filtro visual distinto en la UI para diferenciarla.
   - **Lida**: hace **Colposcopía** (y parece llevar consultas de
     ginecología en general -- confirmar alcance exacto contra la hoja
     `AGENDAS DRA CANO`/`CONSULTAS GINECOLOGIA`). Mismo tratamiento que
     María.
2. **Hora de llegada vs. hora real del procedimiento (solo Urodinamia)**:
   a la paciente se le pide llegar más temprano (ej. 9:00) de lo que
   realmente empieza el procedimiento, porque normalmente llega tarde. Los
   turnos reales no son cada hora exacta, son escalonados:
   **9:30, 10:30, 11:15, 12:00, 1:00, 1:45**. Hoy no existe en el modelo un
   concepto de "hora de llegada" distinto de `starts_at` -- es una decisión
   de diseño pendiente (¿un campo `arrival_time` en el Appointment, o solo
   una nota/plantilla de WhatsApp que le dice una hora distinta a la real?
   Más simple y menos riesgoso: que sea una regla a nivel de mensaje/plantilla, no de dato.
3. **Campo "quién confirmó la cita" como dato estructurado, no nota
   libre**: la columna L del Excel ("OK LA PC" = confirmó el propio
   paciente; "OK {nombre}" = se habló con otra persona -- familiar, etc.)
   hoy se guardaba como texto libre en observaciones. Se pidió
   explícitamente una **columna nueva** en `calendario_appointments`
   (ej. `confirmed_by_name`), que por defecto es el nombre del propio
   contacto pero admite texto libre para cuando se confirmó con otra
   persona (y en ese caso guardar también idealmente el teléfono de esa
   persona -- ya existe `secondary_phone_number` en `Contact` para esto,
   reusar en vez de duplicar).
4. **Lista de espera, orden y filtro**:
   - El orden de llamada es estrictamente de más antiguo a más reciente
     (en el Excel, de arriba hacia abajo en los bloques "en blanco" =
     pendientes de llamar; los que ya tienen color ya están agendados).
     Esto ya es el comportamiento natural si se ordena por fecha de
     solicitud ascendente -- confirmar que `Calendario::WaitlistEntry` usa
     ese orden por defecto en la UI.
   - Falta **filtrar la lista de espera por servicio/procedimiento**
     (hoy existe `for_professional`, falta `for_service` o un filtro
     combinado) -- el flujo real es "hoy voy a agendar Urodinamia", abre
     el panel y quiere ver solo los pendientes de ese procedimiento para
     ese profesional.
   - Registrar **tres marcas de tiempo** distintas para poder sacar
     estadística real de atención: (a) cuándo se originó la solicitud
     (puede ser anterior a cuando se registra en el sistema, si se está
     cargando historia), (b) cuándo se le agendó/confirmó una fecha, (c)
     cuándo efectivamente fue la cita. Hoy `WaitlistEntry` tiene
     `created_at` + `fulfilled_by_appointment_id`, que cubre (b)/(c)
     indirectamente vía la cita enlazada, pero falta una fecha de
     solicitud explícita y distinta de `created_at` para cargas históricas
     retroactivas.
   - Antes de agendar, a veces se necesita verificar/pedir el **urocultivo
     negativo** (paciente con infección no se puede atender hasta que
     repita el examen y salga negativo) -- esto hoy vive solo como texto
     en observaciones del Excel ("PC SIN UROCULTIVO..."). No se pide
     construir una validación dura todavía, pero es un estado real del
     flujo a tener en cuenta si se modela un "motivo de no poder agendar
     aún" en el futuro.
5. **Cartera / Terapias para pacientes particulares** (hoja `TERAPIAS` /
   `FECHAS TERCARTERAPIA` de `PARTICULARES 2026.xlsx`): es un concepto
   **distinto** del `Calendario::ContactSessionCredit` ya construido (que
   es para sesiones *incluidas gratis* en un procedimiento). Esto es un
   **paquete de terapias pagado** por el paciente particular, de cantidad
   variable (no siempre 6 -- algunos compran más), y hoy se audita contando
   cuántas veces aparece el nombre del paciente en la hoja de fechas. El
   color de cada celda indica estado de pago/facturación:
   - **verde** = ya pagada.
   - **amarillo** = es Sura y a Sura no se le puede cobrar directo al
     paciente (va por la aseguradora, no por caja).
   - **blanco** = ya se pagó pero aún no se ha facturado (pendiente de
     enviar la cuenta de cobro de fin de mes).
   Es importante separar bien Medplus de Sura porque al cierre de mes se
   concilian **dos cuentas de cobro independientes** (una por cada
   pagador) y los totales deben coincidir contra lo que aparece en la
   hoja. Esto es trabajo de un **módulo de cartera nuevo** (no builder
   existente) -- queda como backlog explícito, no para el parser de citas.
6. **Xenco (sistema externo, no Chatwoot)**: cuando se agenda una cita
   real, la asistente hoy además da de alta al paciente en otro software
   llamado Xenco, pidiendo: cédula, apellidos/nombres por separado, sexo,
   estado civil, zona de residencia (urbana/rural), si pertenece a
   población vulnerable, fecha de nacimiento (con la que Xenco calcula la
   edad automáticamente), tipo de documento (con cuidado de no confundir
   permiso temporal con permiso especial), ciudad, país, dirección
   completa, teléfono, y si ese teléfono tiene WhatsApp. **No se pide
   replicar Xenco ni sincronizar con él todavía** -- se documenta para que,
   si en algún momento se decide integrar o reemplazar ese paso manual,
   ya esté mapeado qué campos haría falta agregar a `Contact` (hoy no
   existen: sexo, estado civil, zona de residencia, población vulnerable,
   fecha de nacimiento, ciudad/país estructurados, bandera de WhatsApp en
   el teléfono).

## Roadmap de producto (explícitamente backlog, no parser)

Todo esto se pidió documentar para no perderlo, **no para construir ya**:

1. **Click-to-call desde el computador, llamada real en el celular de la
   asistente.** Ella opera desde el computador pero no tiene ningún
   celular conectado a él; tiene un celular propio con plan y auriculares
   bluetooth. La idea es un botón "Llamar" en el contacto/cita que dispare
   la llamada real en SU celular sin que ella tenga que digitar el número.
   Esto requiere una app puente en el celular (compañera de esta app web) o
   un proveedor de telefonía (ej. Twilio Voice / click-to-call) que inicie
   la llamada en ese número -- es una pieza de infraestructura nueva,
   pendiente de decidir el mecanismo exacto.
2. **Transcripción de llamadas → registrar/crear el contacto
   automáticamente**, pensado para pacientes que *solo* tienen teléfono
   (sin WhatsApp/internet) -- hoy esas conversaciones no dejan ningún
   rastro en el sistema.
3. **Mensaje de confirmación de cita con audio de indicaciones + botón "Leí
   las indicaciones"**: la población objetivo tiene en promedio 56+ años,
   así que se prioriza que las instrucciones (qué traer, cómo prepararse)
   queden claras incluso por voz, no solo texto, y que quede registrado
   que la persona efectivamente las leyó/escuchó (un botón explícito, no
   asumir que "entregado" = "leído").
4. **Plantillas de WhatsApp basadas en el historial real de chats** -- el
   usuario compartirá más adelante la exportación completa de
   conversaciones para identificar los textos/patrones que más se repiten
   y convertirlos en plantillas para: confirmación de cita, seguimiento a
   quien no asistió, cancelación/reagendamiento, entrada a lista de
   espera, indicaciones pre-cita. El motor para disparar estas plantillas
   ya existe (`Calendario::AppointmentEventTrigger`, eventos
   `on_create`/`on_status_change`/`before_start`) -- lo que falta es
   **redactar el contenido**, no construir el disparador.
5. **Mensaje de reprogramación** con dos botones: "Confirmar nueva fecha y
   hora" / "Volver a lista de espera".
6. **Bot inicial de triage** que redirija al paciente lo más posible antes
   de que la asistente tenga que intervenir en temas puntuales -- alcance
   todavía sin definir, fase posterior.

## Seguridad

La hoja `CLAVES` de `AGENDAS DR CORRALES 2026 actualizado.xlsx` contiene
credenciales reales en texto plano (logins de portales de EPS/Xenco,
contraseña de router/wifi) mezcladas con datos operativos del consultorio.
No se leyó su contenido más allá de confirmar que son credenciales, y
**ningún script de este pipeline debe parsear esa hoja**. Recomendación
para el usuario: mover esas credenciales a un gestor de contraseñas y
confirmar que esta hoja no se comparta fuera del consultorio (el archivo ya
está en `.gitignore`, pero eso no protege contra compartirlo por fuera de
git).

## Decisiones del usuario (2026-11-16, segunda ronda)

Confirmadas explícitamente, ya no son preguntas abiertas:

- **`AGENDAS DRA CANO 2026.xlsx` / `URODINAMIAS 2026 (1).xlsx` (mismo
  archivo) -- es basura.** Las fechas internas de cada fila son de 2014
  (plantilla vieja reutilizada bajo nombres de hoja de 2025/2026, ver
  hallazgo de la ronda anterior). **No se carga nada de este archivo.**
  Las hojas que sí hace falta mirar en algún momento (`CONS PENDIENTES
  CAFE SALUD`, `PENDIENTES MEDIMAS`, `CONSULTAS GINECOLOGIA`, `DRA CANO
  FOMAG`, `DR ESPITIA`, etc.) quedan fuera de alcance mientras no haya un
  archivo fuente confiable para esos datos -- si el usuario consigue una
  versión real, se vuelve a evaluar.
- **Lida también es ginecóloga** -- no solo colposcopías, también
  consultas y otros procedimientos de ginecología. Hay otra ginecóloga
  distinta: **Dr. Espitia** (vive en el archivo descartado arriba, así
  que por ahora solo queda anotado el nombre, sin datos reales que
  cargar).
- **Hora de llegada de Urodinamia: decisión final, no placeholder.** Se
  deja **solo la hora real del turno** (9:30, 10:30, 11:15, 12:00, 1:00,
  1:45) como `starts_at` de la cita. La hora de llegada (9:00 para todos)
  es un dato operativo de cara al paciente (se le dice que llegue antes
  porque suele llegar tarde), **no se modela como campo nuevo** -- queda
  como algo a resolver después vía plantilla de mensaje, nunca en el
  schema. Cada vez que se abra una agenda nueva de Urodinamia, debe
  nacer ya con esos 6 turnos fijos.
- **Cartera de terapias es un producto nuevo, con una profesional nueva:
  Mayra.** Hay que crear a Mayra como `Calendario::Professional` (igual
  que María/Lida, agente técnica, no doctora) para el servicio de
  Terapias. A diferencia de María/Lida, las terapias **no tienen un
  número de sesiones fijo** (paquetes variables comprados por el
  paciente particular) -- por ahora **basta con guardarlo como
  observación/nota**, no se pide modelar un contador de sesiones
  restantes todavía. Separación Medplus/Sura para conciliación mensual
  sigue siendo un requisito real (ver sección de reglas arriba).
- **Xenco**: queda documentado tal cual arriba, explícitamente **sin
  construir nada** por ahora -- solo por si se decide integrar después.
- **Click-to-call / telefonía celular: en standby.** No se investiga ni
  se diseña todavía -- se retoma cuando el usuario lo pida explícitamente.

## Archivo descartado

**`AGENDAS DRA CANO 2026.xlsx` / `URODINAMIAS 2026 (1).xlsx`** (mismo
archivo, ~75 hojas) -- confirmado por el usuario 2026-11-16: las fechas de
2014 encontradas en cada fila son basura de una plantilla vieja reciclada,
no historial real. **No se parsea ni se carga nada de este archivo.** Las
hojas de ginecología/pendientes que vivían ahí (`CONSULTAS GINECOLOGIA`,
`DRA CANO FOMAG`, `DR ESPITIA`, `PENDIENTES MEDIMAS`, `CONS PENDIENTES
CAFE SALUD`) quedan sin fuente de datos confiable mientras no aparezca un
archivo real -- si el usuario encuentra/genera uno, se retoma como tarea
nueva, no como continuación de esto.

## Inventario completo de colores (resuelto 2026-11-16)

**`LISTADO PC URODINAMIAS`** (654 filas, dentro de `URODINAMIAS 2026
(1).xlsx` -- esta hoja puntual SÍ tiene fechas 2025 sanas, a diferencia de
las hojas de agenda diaria del mismo archivo que se descartaron arriba).
Regla de color confirmada fila por fila, no por muestra:

- **Morado** = tema de Excel "Accent4" (`#8064A2`, `theme=7`) -- **527
  filas (80%)**. Confirma exactamente lo dicho por el usuario: ya pasó a
  la tabla de agendas, ya no está en lista de espera.
- **Blanco / sin relleno** -- ~100 filas (15%). Sigue pendiente de
  llamar.
- **Azul claro** (`#00B0F0`) -- 10 filas. El grupo de FOMAG/neurología
  con convenio terminado.
- Verde/amarillo/naranja/rojo -- 13 filas sueltas (2%), sin patrón
  masivo. No se les asigna regla automática -- quedan para revisión
  manual fila por fila si hace falta.

**`TERAPIAS` / `FECHAS TERCARTERAPIA`** (`PARTICULARES 2026.xlsx`) -- el
color NO dio un patrón limpio (amarillo/naranja dominan sin corresponder
obviamente a verde=pagado/amarillo=Sura/blanco=pagado-sin-facturar). Dado
que es dinero real, se prefiere lo no ambiguo: la hoja `TERAPIAS` ya trae
columnas de texto explícitas **`ASISTIO`** y **`ENTREGA EFECTIVO`** --
esas son la fuente de verdad, el color queda solo como señal secundaria a
confirmar con el usuario si algo no cuadra, nunca como regla automática
de dinero.

## Inventario completo de `PARTICULARES 2026.xlsx` (resuelto 2026-11-16)

14 hojas, dos familias de datos distintas en el mismo archivo:

- **Agendas reales de particulares** -- `AGENDA DRA CANO` (73 bloques,
  enero-noviembre 2026, fechas sanas) y `AGENDA  DR. CORRALES ` (106
  bloques, mismo rango). Mismo layout que las agendas de fase 1
  (título de bloque + HORA/CEDULA/NOMBRE/TELEFONO/EPS/PROCEDIMIENTO) más
  una columna `VALOR` (precio cobrado real) que no existía antes --
  billing y agenda mezclados en la misma fila.
- **Conciliación de facturación por pagador** -- `DRA CANO MEDPLUS`,
  `DR CORRALES MEDPLUS `, `DRA CANO SURA `, `DR CORRALES SURA ` (columnas
  FECHA/DOCUMENTO/NOMBRE/TELEFONO/ENTIDAD/PLAN/COPAGO/AUTORIZACION, sin
  hora ni procedimiento) -- son el mismo paciente que ya aparece en las
  agendas de arriba, repetido aquí solo para el reporte mensual que se le
  manda a contaduría. **No se cargan como citas nuevas** -- son el
  insumo del futuro módulo de conciliación, no agenda.
- `AGENDAS PARTICULARES DR ESPITIA` -- solo encabezado, cero filas de
  datos. Confirma lo ya sabido: Espitia no tiene ningún dato real
  disponible todavía (su archivo fuente es el descartado por fechas de
  2014).
- `RELACION CITOLOGIAS 2026` -- registro de toma de muestras de
  citología enviadas a laboratorio (resultado, fecha de recibido,
  laboratorio). Es un dominio distinto (seguimiento de laboratorio, no
  agenda de citas) -- queda fuera de alcance de esta carga, anotado como
  posible feature futura si se pide.
- `SEGIMIENTO TECART` -- seguimiento clínico de terapias (diagnóstico +
  hasta 6 sesiones marcadas con X + nota de evolución), **distinto** de
  `TERAPIAS` (que es el registro de pago/cobro). Son dos caras del mismo
  paciente de terapias: una es plata, la otra es clínica. Ambas quedan
  documentadas para el futuro módulo de cartera de terapias de Mayra,
  ninguna se carga todavía.
- `TELEFONOS ` y `Hoja1` -- **contienen números de cuenta bancaria
  reales** de los médicos (ahorros/corriente Bancolombia, Davivienda) y
  claves de acceso a portales (ej. "LLAVE @lyda..."). Igual que la hoja
  `CLAVES` descartada en la ronda anterior: no se lee ni se repite ese
  contenido en ningún script ni documento, y se recomienda al usuario
  sacarlo de ahí también.

**`PARTICULARES 2026 (Autoguardado).xlsx` -- descartado.** Comparación
documento por documento contra el archivo principal (hoja `PENDIENTES`,
la que tenía más filas): **0 registros únicos** que no estén ya en
`PARTICULARES 2026.xlsx`. Es un autoguardado viejo y estrictamente
menor en todas las hojas compartidas. No se usa para nada.

## Pendiente antes de escribir `normalize.py` v2

Ninguno -- todo lo necesario para empezar a escribir el parser quedó
confirmado arriba.

## Ronda 3 -- auditoría de asistencia y bugs de UI (2026-11-17)

El usuario reportó que la estadística de asistencia estaba en 0% (sin
sentido con datos reales ya cargados) y pidió una auditoría general.
Hallazgos y fixes:

1. **Asistencia real nunca se parseaba.** Confirmado fila por fila contra
   el Excel real (igual criterio que el morado/blanco de la lista de
   espera de Urodinamia, pero es una regla DISTINTA, propia de las hojas
   de agenda): en una fila de fecha PASADA, blanco/sin relleno = asistió,
   **verde (`#92D050`)** = no asistió. `normalize.py` ahora calcula esto
   por fila (`attendance_from_fill`) para `agenda_profesional` y
   `agenda_particular`, lo lleva como columna `asistencia` hasta
   `appointments.csv`, y `import_to_local.rb` lo fija como `status` en el
   **create** de la cita (nunca con `mark_attended!`/`mark_no_show!`
   después, porque esos callbacks de cambio de estado no tienen guarda de
   `historical_import` y dispararían triggers reales sobre citas de hace
   meses). Resultado real tras recargar: 1858 atendidas, 219 no asistió,
   95 pendientes (fechas futuras) -- antes: 2172 "pending", 0% de
   asistencia en toda la cuenta.
2. **Bug real en `WaitlistPanel`**: el drawer normal (el botón "Lista de
   espera" que siempre está visible) no pasaba `professional-id`, así que
   mostraba la lista de espera de TODOS los profesionales sin filtrar
   -- por eso al abrirla desde María aparecían pacientes de otros
   servicios. Solo el modo "inline" (Agendas expandida) sí filtraba.
   Corregido en `CalendarioSchedulesPage.vue`.
3. **Corte de fecha en `LISTADO PC URODINAMIAS`**: confirmado por el
   usuario que solicitudes de 2025 ya deberían estar resueltas -- se
   agregó `WAITLIST_CUTOFF = 2026-01-01`, descartando solicitudes
   anteriores. Antes: 113 filas blancas importadas a lista de espera de
   María; después: 41 (luego 38 tras el fix de contactos duplicados) --
   coincide con "unas cuantas" que describió el usuario.
4. ~~No hay agenda real de Urodinamia para cargar~~ -- **corregido
   2026-11-17**: el usuario señaló que dentro de `URODINAMIAS 2026
   (1).xlsx` SI existe una hoja real de agenda, `AGENDA URODINAMIAS ` --
   un bloque consolidado distinto de las ~75 hojas de agenda diaria
   descartadas en la Ronda 2 (esas SI tienen fechas de 2014 basura; esta
   hoja puntual tiene 102 bloques, TODOS con fechas 2026 reales, 06 de
   enero a 20 de noviembre). Se agregó `process_urodinamia_agenda` a
   `normalize.py` con la misma regla de color (blanco=asistió,
   verde=no_show). Resultado: 565 citas reales nuevas de María
   (Urodinamia/Uroflujometría), 91.7% de asistencia real.

## Ronda 4 -- auditoría general: EPS, profesionales, especialidades (2026-11-17)

El usuario pidió auditar el resto del sistema. Hallazgos:

1. **Bug real: Dr. Devia y Dra. España estaban archivados
   (`active: false`)** desde una sesión de desarrollo anterior a esta
   importación (2026-11-12), con citas reales ya asociadas (6 y 143).
   Un profesional archivado no aparece como pestaña en Agendas ni en los
   filtros -- sus agendas quedaban invisibles aunque los datos existían.
   `import_to_local.rb` ahora reactiva explícitamente a los 8
   profesionales de este Excel en cada carga (todos están en operación
   real, nunca deberían quedar archivados por esto).
2. **77 citas reales se perdían por servicios no reconocidos** (caían en
   "Otro" → nunca se importaban, ver `prepare_import.py`). Se agregaron a
   `SERVICE_MAP`: Colposcopia, Litotricia, Pesario, Sexología,
   Cauterización, Conización, y se corrigieron typos reales que rompían
   el match (CISTOSSCOPIA, RET CATETER sin "IR[O]", CONS+CIT/CONSUL+CIT
   -> Consulta, COSULTA, UROFLUJOIMETRIA). Quedan 24 filas genuinamente
   ambiguas o basura de columna (ej. "PARTICULAR"/"COLSANITAS" pegado en
   la celda de procedimiento) sin mapear -- no se adivinaron.
3. **~30 EPS duplicadas por typo** (de 62 a 41 registros reales). Se
   amplió `EPS_FIXES` con todos los casos reales encontrados (Asmet
   Salud/Asmed Salud/Asmet Saludd, Previser/Previseer, Sos
   Bienestar/Binestar, Particular/Particcular/Particu/Particulaar/
   Particulares/Particulra/Particukar, Sentir Humano/variantes, Seguros
   Bolivar/Seg Bolivar, Sura Poliza/Pliza/Polioza, Casalud/Casaslud,
   Fundacion La Liga/Fund La Liga, etc.) y se borraron las filas
   duplicadas que quedaron en 0 contactos tras la recarga. De paso se
   corrigió que "Particular" y sus typos estaban creados con `kind: eps`
   en vez de `kind: particular` (afecta la lógica de facturación/pricing
   que distingue EPS de pago particular).
   **Quedan sin fusionar, a propósito, por ser ambiguos** (no hay
   suficiente certeza para adivinar): "Sura"/"Sura Eps" (no se sabe si es
   Sura Para Dos o Sura Poliza), "Bive", "Cont Medico", "Dr Leonardo",
   "Lcc", "Reg Aseguramiento Een Salun No.3", "Retiro Mirena", "Santa
   Monica" -- varios de estos parecen texto de otra columna que se corrió
   hacia la celda de EPS (columna rota en el Excel original), no EPS
   reales. Pendiente de que el usuario confirme caso por caso si quiere
   que se revisen a mano.
4. **Bug real encontrado al verificar**: `attendance_from_fill` marcaba
   "no_show" (verde) sin importar si la fecha era futura -- el chequeo de
   "fecha pasada" solo protegía el caso "asistió". Una cita real del 20
   de noviembre (futuro) aparecía como "No asistió" antes de corregirlo.
   Ahora ninguna fecha futura recibe desenlace, sin importar el color de
   la celda.
5. **Especialidades y Profesionales**: revisados, sin hallazgos nuevos
   más allá de lo de arriba -- 2 especialidades (Urología con 7
   profesionales, Ginecología con 1), 8 profesionales todos con su
   especialidad y servicios correctos.

**Resultado final tras toda la Ronda 3+4**: 2068 contactos, 2784 citas
(2403 asistidas, 270 no asistió, 111 pendientes futuras), 79 en lista de
espera, 41 EPS (sin duplicados), los 8 profesionales activos.

## Ronda 5 -- fecha real de solicitud en lista de espera (2026-11-17)

El usuario explicó que la **columna A** de `LISTADO PC URODINAMIAS` y de
`CONSULTAS UROLOGIA` (la primera columna, antes de documento/nombre) NO es
la fecha de la cita -- es la fecha en que el paciente se registró pidiendo
cupo. Hasta ahora esa fecha solo se guardaba como nota de texto (Urodinamia)
o ni siquiera se leía (`CONSULTAS UROLOGIA`) -- por eso las 79 entradas de
lista de espera quedaban con `created_at` = el instante de la carga, y
"días esperando"/"más antiguas primero" no tenían ningún sentido real.

Fix: `parse_registration_date()` nuevo en `normalize.py`, columna
`fecha_solicitud` llevada hasta `waitlist.csv`, `import_to_local.rb` la usa
como `created_at` explícito de cada `Calendario::WaitlistEntry` (si no hay
fecha en el Excel, se deja el default de Rails = ahora).

**Bug encontrado al implementarlo**: en la hoja `CONSULTAS UROLOGIA`, el
encabezado de la columna A es literalmente el número `22` (basura real del
Excel), no el texto "FECHA" -- buscar la columna por nombre de encabezado
nunca la encontraba. Se corrigió usando la posición fija (columna 1,
siempre es la fecha de solicitud en ambas hojas maestras) en vez de buscar
por nombre.

**Resultado**: las 79 entradas de lista de espera ya tienen `created_at`
real (la más antigua: 2025-10-20). Verificado en el navegador: María
muestra "313 días en espera" / "234 días en espera" en vez de "0 días".

## Ronda 6 -- Dra. Cano en 0, burbuja de conteo, hoja PENDIENTES (2026-11-17)

El usuario señaló que Dra. Cano debería tener muchos pacientes
particulares en lista de espera -- verificado: tenía **0**. La hoja
`PENDIENTES` de `PARTICULARES 2026.xlsx` (1304 filas, lista de espera de
ginecología mezclando EPS y particulares) se había dejado fuera de
alcance en la Ronda 2 por ser "más desordenada" -- resultó ser el mismo
tipo de caos que `CONSULTAS UROLOGIA` (columna "FECHA" sin fecha
confiable, doctor mencionado ahí mismo), solo que con encabezados
distintos ("CONTACTO"/"ENTIDAD" en vez de "TELEFONOS"/"EPS") y sin columna
de procedimiento confiable.

Se generalizó `process_master_sheet` con `column_aliases`,
`default_especialidad`, `default_profesional` y `default_servicio` en vez
de duplicar la función, y se llamó para `PENDIENTES` con profesional por
defecto "Dra. Cano" (su hoja) y servicio por defecto "Consulta" (no hay
columna de procedimiento confiable, pero casi todas las filas son
consulta). Resultado: **266 filas nuevas** (245 a lista de espera, 21 ya
tenían fecha y se fusionaron como citas) -- Dra. Cano pasó de **0 a 214**
en lista de espera.

**Bug encontrado al cargar**: una fila basura al final de la hoja (un
título de bloque mal pegado, documento irreconocible "112025" sin ningún
nombre en ninguna de sus apariciones) rompía `import_to_local.rb` con
`NoMethodError` al intentar `.strip` sobre un nombre `nil`. Se agregó un
filtro en `build_contacts()` de `prepare_import.py`: un documento sin
nombre en NINGUNA fila se descarta, no se crea un contacto vacío.

Se agregaron 2 typos de EPS más de esta misma hoja (Particulat->Particular,
Seg. Bolivar->Seguros Bolivar) -- total de EPS real: 44.

**Feature nueva**: burbuja con el conteo de lista de espera de la
profesional activa, en el botón "Lista de espera" de Agendas (antes solo
se veía abriendo el panel). Verificado en el navegador: muestra "214" en
Dra. Cano.

**Estado final de lista de espera por profesional**: Dr. Corrales 36,
Dr. Gaviria 2, Dr. Velez 4, Dra. Cano 214, Dra. España 2, María 38 (Dr.
Devia y Dr. Heredia en 0 -- no hay evidencia de lista de espera propia
para ellos en ningún Excel revisado hasta ahora).

## Ronda 7 -- lista de espera "cumplida" + estadística real de espera (2026-11-17)

El usuario pidió explícitamente: (1) verificar que "las personas en lista
de espera estén realmente ya agendadas o no lo estén", y (2) que esas
personas "tengan la estadística de cuándo se registraron para luego
compararlo con la fecha de la cita efectiva a la que asistieron".

Hallazgo real: de las 297 entradas que la Ronda 6 había cargado como lista
de espera "pendiente", **161 correspondían a personas que YA tenían una
cita real** con ese mismo profesional en otra hoja del Excel -- la lista
de espera de origen nunca se había actualizado para quitarlas. El
`WaitlistEntry` del sistema ya tenía todo lo necesario para esto
(`status: fulfilled`, `fulfilled_by_appointment_id`) pero nunca se usaba
en la carga.

Se agregó a `prepare_import.py` un cruce: para cada fila de lista de
espera, si existe una cita real (de cualquier hoja) con ese mismo
`(documento, profesional)` **en o después** de la fecha de solicitud, se
marca como cumplida (`waitlist_fulfilled.csv`) con la cita real más
cercana en vez de pendiente. `import_to_local.rb` la crea con
`status: :fulfilled`, `created_at` = fecha real de solicitud, y
`fulfilled_by_appointment_id` enlazado -- así queda la estadística real
de "cuánto tiempo pasó desde que se registró hasta la cita efectiva".

**3 bugs reales encontrados al verificar los números** (ninguno obvio a
simple vista, solo auditando los días de espera calculados):

1. Un primer intento contaba CUALQUIER cita real como "la que cumplió la
   espera", incluyendo citas **anteriores** a la fecha de solicitud --
   eso daba "días de espera" negativos (ej. -292) porque eran visitas
   viejas sin relación con esa solicitud puntual. Corregido: solo cuentan
   fechas reales en o después de la fecha de solicitud.
2. Sin fecha de solicitud en el Excel (5 filas), el mismo criterio
   aceptaba cualquier fecha real como válida pero `created_at` quedaba en
   el default de Rails (el instante de la carga) -- comparado contra una
   cita de hace meses, de nuevo días negativos. Corregido: sin fecha de
   solicitud, se usa la fecha de la cita real como `created_at` (0 días
   conocidos, no un número inventado).
3. La tabla de fechas reales usada para el cruce no aplicaba el mismo
   filtro de "servicio reconocido" que la lista real de citas
   (`appointments.csv`) -- contaba fechas de filas con servicio "Otro"
   (nunca se crean como `Calendario::Appointment`), así que 5 entradas
   quedaban marcadas "cumplida" sin ninguna cita real para enlazar
   (`fulfilled_by_appointment_id` nil). Corregido: mismo filtro en ambos
   lados.

**Resultado final verificado**: 146 pendientes reales / 150 cumplidas, 0
sin cita enlazada, 0 días negativos, promedio real de espera 33.3 días
(mínimo 0, máximo 368). Dra. Cano: 106 pendientes reales (antes se veían
214, inflado por las 108 ya cumplidas).

## Ronda 7b -- burbuja de conteo en Agendas (2026-11-17)

Pedido explícito del usuario: ver de un vistazo cuántas personas hay en
lista de espera sin abrir el panel. Se agregó una burbuja numérica sobre
el botón "Lista de espera" de `CalendarioSchedulesPage.vue`, con el conteo
de la profesional activa (reusa `pendingWaitlistCount`, ya filtrado por
`status: pending` en el backend -- las "cumplidas" no inflan el número).
Verificado en el navegador: muestra "106" en Dra. Cano.
- ~~Confirmar si Dr. Piedrahita / Dr. Federico necesitan agenda propia~~
  -- **resuelto 2026-11-16**: son solo menciones de apoyo puntual en
  `HORAS MEDICO APOYO` (cubren un turno, sin pacientes/citas propias
  asociadas). **No se crean como profesionales ni se les abre agenda.**
  Quedan como nota de contexto, nada más.
- ~~Decidir qué hacer con Dr. Heredia~~ -- **resuelto 2026-11-16**: a
  diferencia de Piedrahita/Federico, Heredia SÍ tiene 17 citas reales de
  pacientes concretos (bloque "CONSULTORIO 2" de los lunes, hoja de Dr.
  Corrales, fase 1). El usuario confirmó explícitamente mantenerlo como
  profesional real con sus 17 citas tal como están -- no se reasigna
  nada a Dr. Corrales.
