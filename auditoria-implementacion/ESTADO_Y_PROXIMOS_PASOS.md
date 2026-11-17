# Procol Auditoria — Estado vs. catálogo de wpp-extension-crm

Este documento compara lo que ya existe en Procol Auditoria (rama `auditoria` de este repo) contra el catálogo de funcionalidades del sistema viejo (`wpp_extension_crm_catalog.md`, mismo directorio — generado el 18 de octubre 2026 por una exploración de solo lectura de `/Users/camilocastillo/Proyectos/wpp-extension-crm/dashboard/backend`). El objetivo del catálogo original era identificar qué métricas/insights de IA ya estaban resueltos en el sistema anterior, para no reinventarlos al construir "Auditor IA" en Chatwoot.

**No está en git** (carpeta en `.gitignore`) — son notas de trabajo internas, no parte del producto.

> **Actualización 2026-10-20**: las prioridades #1 y #2 de la sección de abajo ya quedaron construidas (toggle "mismo día" en una sesión anterior; categorización por palabra clave/IA en la sesión de hoy). Detalle completo de lo que se construyó hoy en `SESION_2026-10-20.md`, mismo directorio. La sección "Prioridad por valor agregado" más abajo quedó obsoleta en sus dos primeros puntos — ver ese otro documento para la lista reordenada de lo que sigue pendiente.

---

## ✅ Ya implementado en Procol Auditoria (construido en esta fase)

| Punto del catálogo | Estado en Procol Auditoria |
|---|---|
| 3. Análisis de conversación con IA, 5 campos configurables | **Hecho y mejorado.** `Auditoria::AiFieldConfig` (título+instrucciones editables desde Settings > Integrations > OpenAI). A diferencia del sistema viejo (5 llamadas paralelas a OpenAI, una por campo), usamos **una sola llamada con salida estructurada** (`Auditoria::ConversationAnalyzerSchema`) — más barato y rápido. |
| 3. API key por cuenta → global | **Hecho.** Mismo patrón (`Captain::BaseTaskService`, hook de OpenAI de la cuenta → key global). |
| 3. Gate de plan/límite de uso antes de llamar a OpenAI | **Hecho y más completo.** `Auditoria::AiUsageLogger` con límite configurable por costo USD y por tokens mensuales, aplicado antes de cada llamada (análisis Y transcripción). |
| 8. Scheduling — no reanalizar si no hay mensajes nuevos | **Hecho, mismo mecanismo exacto.** `ConversationAnalyzerService#needs_analysis?` — solo corre si nunca se analizó o si hay un mensaje más nuevo que `analyzed_at`. Idéntico al `getConversationsToProcess` del sistema viejo. |
| (nuevo, no estaba en el catálogo) Transcripción de audio | **Hecho** — automática (toggle) y manual ("Analyze now" transcribe primero, luego analiza). El sistema viejo no tenía esto. |
| (nuevo, no estaba en el catálogo) Log de uso de IA por ejecución | **Hecho** — tabla `auditoria_ai_usage_logs`, tabla filtrable/ordenable en Usage & limits, con link directo a la conversación/mensaje. Más granular que el `checkAiUsageLimit` del sistema viejo. |
| Exclusión de conversaciones con múltiples asesores | **Hecho, pero menos genérico.** Label `auditoria-multiple-asesor` (automática, vía `Auditoria::MessageAnnotatorService#flag_multiple_advisors`) excluye del reporte por asesor. El sistema viejo usa una columna booleana `exclude_from_response_time_stats` por conversación, con cualquier motivo — más flexible, pero nuestro caso de uso (multi-asesor) ya está cubierto. |

---

## ❌ Brechas reales — ni en el sistema viejo ni en Procol Auditoria

Del catálogo original, sección "Resumen de brechas":

1. **Agregado de medios por dirección** (cuántos audios/imágenes/archivos entrantes vs. salientes, por conversación o por asesor) — no existe en ningún lado. El modelo de datos de Chatwoot (`attachments.file_type`) ya soporta construirlo.
2. **Catálogo de "fichas técnicas enviadas"** (qué archivo específico se mandó, buscar si ya se envió X) — no existe, solo el listado crudo de adjuntos.
3. **Rollup de IA diario por agente individual** — el sistema viejo lo tiene solo por INBOX completo (si el inbox tiene varios asesores, no los separa). Habría que construir la segmentación por `assignee_id` desde cero en cualquiera de los dos sistemas.
4. **Día de la semana pico** (vs. hora pico, que el sistema viejo sí tiene) — no se encontró en la porción revisada del catálogo original.

---

## 🔧 Existe en el sistema viejo, NO está en Procol Auditoria — pendiente de portar

1. ~~**Toggle "mismo día" para tiempo de respuesta**~~ — **HECHO** (sesión previa a la de hoy, ver commit `0c6f02969`).
2. ~~**Desglose 1ra/2da/3ra...Nésima respuesta**~~ — **HECHO** junto con el punto anterior.
3. ~~**Modal de desglose de respuesta**~~ — **HECHO** junto con los dos anteriores.
4. **Filtro de horario laboral** para el cálculo de tiempo de respuesta (`workingHoursOnly`) — no existe.
5. **Hora pico de mensajes** (entrantes/salientes, por hora del día, zona horaria Colombia) — no existe en Procol Auditoria.
6. ~~**Sistema de categorización por palabras clave, configurable por cuenta**~~ — **HECHO (2026-10-20)**, ver `SESION_2026-10-20.md`. Categorías padre/hijas, keyword o IA en la misma llamada estructurada (no un segundo sistema de regex, como recomendaba este documento), filtro de fecha en toda la página, pie chart de distribución, desglose por término.
7. **Timeline de conversación explícito** (`first_message_at`, `last_message_at`, `chat_duration_days`, `days_since_last_interaction` como campos de reporte) — verificar si ya están disponibles vía los campos nativos de Chatwoot antes de asumir que falta construirlos.

---

## Pendientes ya identificados antes de este documento (siguen vigentes)

- **First Response Time / Custom Waiting Time para contactos con múltiple asesor** — directamente relacionado con el punto 1 de arriba (toggle "mismo día"); al implementarlo, resolver ambos juntos tiene sentido.
- **Discrepancia 762 vs 675 en conteo de conversaciones en reportes** — sin confirmar, independiente de este catálogo.

---

## Prioridad por valor agregado (revisado y ordenado)

Verificación hecha contra el código real antes de ordenar: `conversation.first_reply_created_at` (`app/models/message.rb:226-401`) guarda **un solo timestamp**, la primera respuesta histórica, sin filtro de "mismo día" y sin desglose de 2da/3ra/Nésima respuesta. Confirma que el gap #1 es real, no un matiz — el nativo de Chatwoot es más tosco de lo que parece en el reporte.

### 1. Tiempo de respuesta justo (toggle "mismo día" + desglose 1ra/2da/3ra/Nésima) — PRIMERO — ✅ HECHO
**Por qué primero**: es lo único de esta lista que el cliente ya pidió explícitamente (quedó pendiente de la conversación anterior). Sin el filtro "mismo día", un asesor que responde consistente pero tarde un día (por ejemplo, el cliente escribe a las 11pm y responde a las 8am) sale con el promedio inflado injustamente — eso distorsiona la evaluación de desempeño, que es el propósito central de la herramienta. Dato base ya disponible (pares mensaje entrante→saliente), no requiere tablas nuevas. El modal de desglose por respuesta es un extra de UI sobre esto mismo, no una fase aparte con valor propio.

### 2. Categorización configurable por palabras clave/objeciones — SEGUNDO — ✅ HECHO (2026-10-20)
**Por qué segundo, no tercero**: es la pieza de insight cualitativo más grande que falta — responde "por qué se están perdiendo ventas" (precio, tiempo de decisión, comparación con competencia, desconfianza), algo que hoy Auditor IA no captura de forma estructurada ni filtrable. Tiene valor por sí sola desde la primera conversación etiquetada, no depende de que exista el rollup diario.

**Recomendación de diseño, no portar tal cual**: el sistema viejo usa dos generadores de SQL en paralelo (regex simple + regex generado por IA) porque se construyó antes de tener salida estructurada de LLM confiable. Nosotros ya tenemos ese mecanismo funcionando (`Auditoria::ConversationAnalyzerSchema`, salida estructurada en una sola llamada). Más simple y más robusto: agregar la clasificación de categorías como parte de esa MISMA llamada estructurada (el LLM devuelve qué categorías configuradas aplican), en vez de mantener un segundo sistema de matching por regex en Postgres. Evita duplicar infraestructura y maneja mejor variaciones de lenguaje natural que un regex por límites de palabra no captura.

### 3. Rollup diario de IA por agente individual — TERCERO — ✅ BACKEND HECHO (2026-10-22), falta frontend
**Por qué tercero**: extiende lo que Auditor IA ya hace (análisis por conversación) a un resumen diario por asesor — es la pregunta natural de un gerente ("¿cómo le fue hoy a Juan?"). Se puede construir con las señales actuales (resumen, tono, recomendación), pero es más valioso si se construye DESPUÉS del punto 2, porque entonces el resumen diario puede incluir "hoy manejó 5 objeciones de precio y cerró 2" en vez de solo texto genérico. Construirlo antes no está mal, solo entrega una versión más pobre en su primera versión.

**Ampliación de alcance (pedida 2026-10-22):** el análisis de IA por conversación hoy es 100% manual (botón "Analizar ahora"). Para que el rollup diario sea confiable, primero hace falta automatizar ESE análisis — un pipeline de dos etapas, no solo el rollup:

**Etapa 1 — job diario que recorre conversaciones y (re)corre el análisis de IA.**
Investigación de código confirmó que casi toda la pieza difícil ya existe, reusable sin tocarla:
- `Auditoria::ConversationAnalyzerService#perform` (`app/services/auditoria/conversation_analyzer_service.rb:15-16`) YA tiene el guard `return skipped_result unless needs_analysis?` adentro — comparar `MAX(messages.created_at)` contra `analysis.analyzed_at` (líneas 37-42). Esto significa que el job nuevo **no necesita pre-filtrar nada con cuidado**: puede encolar `Auditoria::ConversationAnalyzerJob.perform_later(conversation_id)` (ya existe, `app/jobs/auditoria/conversation_analyzer_job.rb`, recibe solo el id) para cualquier conversación candidata, y el propio servicio se auto-salta (sin llamar a OpenAI, sin gastar) si no hay mensajes nuevos desde el último análisis.
- Espera de transcripción de audio antes de analizar: ya resuelta inline (`transcribe_pending_audio!`, mismo archivo líneas 19, 66-77) — no hay carrera que resolver.
- Límite de gasto mensual (`Auditoria::AiUsageLogger.within_limit?`): ya se re-chequea en cada llamada individual (antes de analizar, antes de cada transcripción) — si el job nuevo procesa conversación por conversación de forma mayormente secuencial, el límite se respeta solo, sin código nuevo de throttling.
- **Construido y verificado (2026-10-22, commit `b966a32e7`):** `Auditoria::DailyConversationAnalysisSchedulerJob` (patrón `Internal::TriggerHourlyScheduledItemsJob`: cron dispara un job chico que encola el trabajo real), conversaciones con al menos un mensaje en los últimos 3 días — **sin el "O que nunca se hayan analizado" sin límite de tiempo** que se había propuesto: un backfill de TODO el historial jamás analizado podría agotar de un golpe el presupuesto mensual la primera noche; una conversación vieja sin actividad reciente tampoco aporta nada al rollup de "ayer". Un backfill real, si algún día hace falta, debería ser un rake task deliberado. Encolado escalonado (`.set(wait: i.seconds).perform_later(...)` -- `perform_in` no existe en jobs ActiveJob normales, es nativo de Sidekiq::Job puro) para la condición de carrera de abajo.
- **Riesgo a mitigar (nuevo, no existía con el trigger manual):** el log de uso se escribe DESPUÉS de la llamada a OpenAI (`conversation_analyzer_service.rb`, `log_usage` tras `make_api_call`) — si el job nuevo encola todo de golpe y Sidekiq los procesa en paralelo, varias conversaciones pueden pasar el chequeo de límite casi al mismo tiempo antes de que cualquiera persista su log (condición de carrera TOCTOU). Mitigación simple sin infraestructura nueva: escalonar el encolado (`.set(wait: i.seconds).perform_later(conversation_id)` con `i` incremental) en vez de `perform_later` puro sin retraso, para serializar aproximadamente el procesamiento.
- **Pendiente de decidir:** el enum `triggered_by: {manual: 0, batch: 1}` en `Auditoria::AiUsageLog` (`app/models/auditoria/ai_usage_log.rb:39`) existe pero nunca se usa — ambos servicios (`conversation_analyzer_service.rb:103`, `audio_transcription_service.rb:100`) mandan `:manual` siempre, hardcodeado. Vale la pena parametrizarlo (costo casi nulo) para poder distinguir gasto manual vs. gasto del job nocturno en el reporte de Usage & Limits.

**Etapa 2 — job diario (2-3h después) que agrega por asesor.**
- **No existe ningún campo "agente al momento" en `Auditoria::ConversationAnalysis`** (solo tiene `account_id`/`conversation_id`/`analyzed_at`/`results`) — y no hay que agregarlo ahí, porque el análisis es 1:1 con la conversación completa, no por día. La pieza correcta ya existe y ya la usa el reporte de asesor en vivo: `content_attributes['auditoria_source_user_id']` **por mensaje** (`Auditoria::MessageAnnotatorService`, resuelto del texto "Source: &lt;agente&gt;"), inmutable en el tiempo a diferencia de `conversation.assignee_id`. El rollup debe agrupar por este campo de los mensajes de cada día, excluyendo conversaciones con el label `auditoria-multiple-asesor` — mismo criterio exacto que `auditoria_advisor_summary_builder.rb:158-163` ya usa.
- Vincular categorías (palabra clave + IA): el matching de palabra clave ya corre en tiempo real e independiente del análisis (no necesita el job de la etapa 1 para nada); el matching de categorías AI SÍ depende 100% de que la etapa 1 corra (vive dentro de `sync_ai_categories!`, solo se ejecuta dentro de `persist_result` del analizador). Por eso el orden etapa 1 → etapa 2 (con margen de horas) es obligatorio, no solo prudente: sin etapa 1, las categorías AI de ese día nunca existirían para agregar.
- **Decidido (2026-10-22):** SÍ lleva una segunda llamada a OpenAI, una por asesor por día (no por conversación) -- el input es el agregado ya calculado (resúmenes/tonos/recomendaciones de sus conversaciones de ese día), no las transcripciones crudas, así que el costo incremental es bajo (escala con número de asesores, no de conversaciones) y el valor para gerencia es mucho mayor que una tabla de conteos sin interpretar.
- **Construido y verificado (2026-10-22, commits `05e1e18c6`/`bb636b1b8`/`66468b2e4`):** modelo `Auditoria::AdvisorDailySummary`, `Auditoria::AdvisorDailyRollupService` (hereda de `Captain::BaseTaskService`, override de `#conversation` → `nil` porque sintetiza sobre varias conversaciones, no una) + `Auditoria::AdvisorDailyRollupJob`/`SchedulerJob`, y el endpoint `auditoria_advisor_daily_rollup` (`SummaryReportsController` + `V2::Reports::AuditoriaAdvisorDailyRollupBuilder`), sumado a `AUDITORIA_INBOX_SCOPED_ACTIONS`. Para un admin restringido, el filtro de inbox acota a agentes miembros de ese inbox (no recalcula el agregado por conversación — el resumen se sintetiza una vez por agente/día a nivel de cuenta completa). Bug real encontrado y corregido durante la verificación: `account.messages.distinct.pluck(:conversation_id)` chocaba con el `default_scope` de `Message` (`ORDER BY created_at`) — mismo `.reorder(nil)` que ya resolvía esto en `pending_audio_messages`. **Falta:** la pantalla de frontend, decidido explícitamente dejarla para la siguiente ronda.

**Infraestructura de cron confirmada reusable, sin montar nada nuevo:** `sidekiq-cron` ya está instalado y en uso (`config/schedule.yml`, 8 jobs activos hoy). Agregar un job nuevo es solo una entrada YAML + una clase `ApplicationJob` normal — el archivo se recarga a Redis en cada deploy (`config/initializers/sidekiq.rb:74-89`), sin pasos manuales. **Ojo con la zona horaria: el cron corre en UTC, no America/Bogotá** (confirmado, sin excepciones en este repo) — Bogotá es UTC-5 fijo, sin horario de verano.

**Horarios decididos (2026-10-22):** etapa 1 (análisis) a las **2am Bogotá = `0 7 * * *` UTC**, etapa 2 (rollup) a las **5am Bogotá = `0 10 * * *` UTC** — más temprano que la primera propuesta (7am/10am) para que el reporte del día anterior ya esté listo ANTES de que arranque la jornada laboral, no a media mañana. "Ayer" ya está completamente cerrado a las 2am de hoy, así que no hay riesgo de cortar actividad tardía de la noche anterior.

### 4. Hora pico y día pico de mensajes — CUARTO
**Por qué más abajo**: es insight operativo (cuándo hay más tráfico, para planear turnos), no insight de desempeño del asesor — no ataca directamente el propósito de auditoría. Barato de construir (una sola query con GROUP BY, sin tablas nuevas) cuando se priorice, así que no es urgencia técnica, es urgencia de negocio la que falta.

### 5. Agregado de medios por dirección + catálogo de "fichas técnicas enviadas" — QUINTO, validar antes de construir
**Por qué último**: valor específico a ventas de automóviles (¿mandó la ficha técnica?), pero no confirmado como un dolor real del cliente todavía — a diferencia de los puntos 1-3, nadie lo ha pedido explícitamente esta fase. Antes de construirlo, vale la pena preguntarle al cliente si esto le importa, en vez de asumirlo porque existía en el sistema viejo.

### Tarea de verificación rápida, no de construcción
**Timeline de conversación** (`first_message_at`, `last_message_at`, `chat_duration_days`, `days_since_last_interaction`): antes de asumir que falta, verificar si ya están disponibles vía los campos/reportes nativos de Chatwoot — es muy probable que sí, dado que `created_at`/`last_activity_at` ya existen en el modelo `Conversation`.
