# Catálogo: wpp-extension-crm (backend, análisis read-only)

Repo: `/Users/camilocastillo/Proyectos/wpp-extension-crm/dashboard/backend` (Node.js/Express) + `dashboard/frontend` (React/JSX).
**Stack confirmado (punto 9)**: Node.js + Express, PostgreSQL (vía `pg` directo, cliente `@supabase/supabase-js` para auth/storage), **no hay BigQuery en ningún lado del repo**. El esquema de `conversations`/`messages`/`attachments` es prácticamente idéntico al de Chatwoot (`message_type` 0/1, `private`, `file_type`, `external_url`, `fallback_title`) — probablemente porque este backend ya replicaba datos con esa forma desde el inicio. Frontend: React (`.jsx`), Chart.js para gráficas (`chart.js`, `chartjs-node-canvas` también en backend para PDFs).

El ejemplo SQL que diste (`REGEXP_CONTAINS`, sintaxis BigQuery) **no existe en este repo** — es de otra herramienta/análisis externo que el usuario hizo antes. El sistema de categorías por palabra clave de este repo (punto 7) es distinto pero cubre la misma necesidad, vía Postgres `~` (regex) generado dinámicamente.

---

## 1. Cálculo de tiempo de respuesta (1ra, 2da, 3ra... Nésima + toggle "mismo día")

**Archivo clave**: `src/services/metrics.js` (`calculateResponseTimes`) y el bloque de documentación en `src/routes/analytics.js:90-186`.

- Un "response pair" es un mensaje entrante seguido del siguiente mensaje saliente en la misma conversación (`JOIN LATERAL` por `created_at ASC LIMIT 1`).
- **Toggle de "mismo día" confirmado**: hay una columna `same_day` calculada así (de `analytics.js:137`):
  ```sql
  DATE(ts_col) = DATE(LEAD(ts_col) OVER (PARTITION BY conversation_id ORDER BY ts_col)) AS same_day
  ```
  El promedio global (`avg_response_time`) SOLO cuenta pares donde `same_day = true` — exactamente lo que pediste (no suma 15h si responden al día siguiente). Pero el detalle por respuesta (ver punto 5) SÍ expone cada respuesta individual con su flag `same_day`, para poder verlas "igual así" si se quiere.
- **Orden 1ra/2da/3ra... Nésima** (`analytics.js:147-150`, implementado con `ROW_NUMBER()` en varios archivos: `routes/conversations.js:2219,2265,2568,2615,2810`, `routes/analytics.js:1466,2196`, `routes/platform/index.js:293`):
  ```sql
  ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY inbound.created_at) AS orden_respuesta
  ```
  Con eso: `first_response_time` = fila con `orden_respuesta = 1`, `second_response_time` = `orden_respuesta = 2`, etc. Genérico para cualquier N.
- **Exclusión por conversación**: columna `conversations.exclude_from_response_time_stats` (booleana, default `false`) — permite excluir UNA conversación puntual del cálculo de tiempos de respuesta (pero NO de los conteos de mensajes). Servicio: `src/services/conversationExcludeStats.js`. Esto es conceptualmente igual a nuestra label `auditoria-multiple-asesor` en Chatwoot, pero más genérico (cualquier razón, no solo múltiple-asesor).
- **Working hours filter** (opcional, vía `workingHoursOnly` param): `src/services/workingHoursService.js` — filtra ambos lados del par (entrante y saliente) a que caigan dentro de un horario laboral configurado, independiente del filtro "mismo día".

## 2. Conteo de mensajes y medios por conversación (audio/imagen/archivo, entrante/saliente)

- **Conteo básico entrante/saliente**: confirmado en múltiples queries, ej. `routes/analytics.js` con `COUNT(CASE WHEN message_type = 0 THEN 1 END) as inbound_messages` / `message_type = 1` para outbound. Expuesto por conversación (`conversations.js:5249-5250`: `inbound_messages`, `outbound_messages`).
- **Tabla `attachments`**: mismo esquema que Chatwoot — `file_type` (0=image, 1=audio, 2=video, 3=file, 4=location), `external_url`, `storage_path`, `fallback_title`, `extension`, `mime_type`, `file_size`. Query de listado en `routes/conversations.js:245-259` (para UNA conversación, trae todos sus adjuntos vía `message_id = ANY(...)`).
- **Lo que NO encontré**: un agregado tipo "cuántos audios entrantes vs salientes, cuántas imágenes, cuántos archivos, por conversación o por asesor" como métrica de reporte. Busqué en `analytics.js`, `conversations.js`, `messageTrackers.js` (que resultó ser otra cosa, ver abajo) y no hay un `GROUP BY file_type, message_type` en ningún lado. Lo más cercano es `routes/habeasData.js:66` y `routes/diagnostics.js:281`, que solo cuentan "mensajes CON adjunto" (no desglosado por tipo ni dirección).
- **"Fichas técnicas" (identificar qué archivo específico se envió)**: el campo `fallback_title` + extracción de filename desde `external_url` (`conversations.js:272-285`) permite identificar el nombre del archivo. No vi un catálogo/búsqueda dedicada de "¿se ha enviado la ficha técnica X?" — solo el listado crudo de adjuntos por conversación.
- **`messageTrackers.js`/`messageTrackersTable.js`**: NO es sobre tipos de medio. Es sobre tracking de entrega/lectura de mensajes individuales (confirmado por el nombre de las rutas/columnas, no por conteo de adjuntos).
- **Conclusión para este punto**: el dato base (tabla `attachments`, idéntica a Chatwoot) está listo para construir el agregado, pero el agregado en sí **no existe todavía** en este sistema — habría que construirlo igual en Chatwoot, no hay nada que "copiar" aquí más allá del modelo de datos.

## 3. Análisis de conversación con IA (resumen, tono, recomendación, objeciones, opinión experto)

**Archivos clave**: `src/services/aiService.js`, `src/routes/ai.js`.

- **Campos configurables, no hardcodeados**: tabla `ai_field_configs` (`account_id`, `analysis_type` ['conversation'|'advisor'], `field_order` 1-5, `title`, `subtitle`, `is_active`), con fallback a `settings` (`ai_title_1`..`ai_title_5`) y defaults en código (`aiService.js:13-27`):
  - **Default "conversation"**: 1=Resumen, 2=Score, 3=Tono Emocional, 4=Recomendación de Experto, 5=Objeciones.
  - **Default "advisor"** (ver punto 8): 1=Desempeño general del asesor, 2=Fortalezas del asesor, 3=Áreas de mejora del asesor, 4=Recomendaciones, 5=Plan de acción.
- **Dónde se guarda**: directamente en la tabla `conversations`, columnas `artificial_intelligence_1` .. `artificial_intelligence_5` (texto libre, una por field_order) + `ai_analysis_updated_at` (timestamp, clave para el punto 8). Separado: `sentiment_analysis` + `sentiment_analysis_reason` (análisis de sentimiento aparte del campo "Tono Emocional" — hay redundancia entre los dos).
- **Prompt exacto por campo** (`aiService.js:687-697`, función `analyzeConversation`):
  ```
  Eres un asistente experto en análisis de conversaciones.

  TAREA: ${prompt}            ← literalmente el "title" del campo, ej. "Resumen" o "Objeciones"

  INSTRUCCIONES ADICIONALES:
  ${additionalContext}        ← texto libre configurable por cuenta (getAdditionalContext())

  CONTEXTO DE LA CONVERSACIÓN:
  ${conversationContext}      ← últimos 200 mensajes, con timestamps unix, truncado a 100k tokens

  Por favor, realiza la tarea solicitada basándote en el contexto de la conversación proporcionado. Sigue las instrucciones adicionales indicadas.
  ```
  System message fijo: *"Eres un asistente experto en análisis de conversaciones de WhatsApp. Analizas conversaciones y proporcionas insights valiosos basados en el contexto proporcionado."*
  Modelo: `gpt-4o-mini`, `temperature: 0.7`, `max_tokens: 2000`.
  **Nota de diseño**: cada uno de los 5 campos dispara su PROPIA llamada a OpenAI en paralelo (`Promise.all` sobre 5 prompts casi idénticos, solo cambia el `TAREA:`), no una sola llamada con salida estructurada JSON. El propio usuario lo describió bien: "un agente de muy poquitos parámetros".
- **API key por cuenta**: `aiService.getApiKey(accountId)` / `setApiKey` — resuelve en orden: key de la cuenta → key global → variable de entorno. Exactamente el patrón que quieres para Captain/Auditor IA en Chatwoot.
- **Gate de plan**: todo el endpoint de análisis (`POST /api/ai/conversations/:id/analyze`, `ai.js:1234`) exige `tier === 'paid'` y pasa por `checkAiUsageLimit` (límite de uso configurable) antes de llamar a OpenAI.
- **Frontend (panel "draggable")**: no llegué a inspeccionar el componente exacto del sidebar de contacto (quedó fuera del tiempo de esta pasada) — el backend confirma que el panel simplemente lee las 5 columnas `artificial_intelligence_1..5` + `sentiment_analysis` de la conversación vía API; el resto es presentación en React.

## 4. Duración y timeline de conversación

Confirmado directamente en el payload de `routes/analytics.js:5235-5255` (parte del mismo query que trae todo lo demás):
- `first_message_at`, `last_message_at` — timestamps exactos.
- `chat_duration_days` — días entre el primer y último mensaje.
- `days_since_last_interaction` — días desde la última interacción hasta ahora.
- `last_activity_at`, `created_at` — también presentes.

Todo calculado en SQL directamente contra la tabla `messages`/`conversations`, no hay una tabla de "eventos de timeline" separada.

## 5. Modal de desglose de respuesta (click en el promedio)

**Frontend**: `dashboard/frontend/src/components/modals/ResponseTimeDetailModal.jsx`, que llama a `conversationsApi.getResponseTimesDetail(conversationId, params)`.

Confirmado en el componente: cada fila de respuesta muestra timestamp formateado (`toLocaleString('es-CO', {dateStyle:'short', timeStyle:'medium'})`), preview del mensaje truncado a 120 caracteres, y las filas que NO son `same_day` llevan una marca visual distinta (línea 106 y 131 del componente) — exactamente el comportamiento de "ver todas, pero distinguir las que no cuentan para el promedio". El endpoint real que arma estos datos vive en el backend (`routes/conversations.js`, probablemente cerca de las queries con `orden_respuesta`/`mismo_dia` ya citadas en el punto 1) pero no profundicé en el controlador exacto — el contrato de datos ya quedó claro desde el frontend.

## 6. Hora pico / día pico / promedio por día

**Archivo**: `src/routes/analytics.js:5160-5319` (dentro del mismo endpoint de listado de conversaciones, como un bloque opcional `hourlyDistribution`).

- Agrupa TODOS los mensajes (entrantes y salientes, excluyendo alertas internas y fallidos) por hora del día en zona horaria `America/Bogota`:
  ```sql
  EXTRACT(HOUR FROM created_at_colombia)::integer as hora,
  COUNT(CASE WHEN message_type = 0 THEN 1 END)::integer as entrantes,
  COUNT(CASE WHEN message_type = 1 THEN 1 END)::integer as salientes
  ...GROUP BY EXTRACT(HOUR FROM created_at_colombia)
  ```
- Rellena las 24 horas (las que no tienen datos quedan en 0), calcula `hora_pico` y `hora_baja` (máximo/mínimo por volumen TOTAL, no separado por dirección) y `promedio_por_hora`.
- **Filtros disponibles en el mismo query**: por `inbox_id`, por asesor (vía `ghl_agent_id`/`clientify_agent_id`, estos sistemas externos — ver integraciones GHL/Clientify), por rango de fechas (`start_date`/`end_date`).
- **Día pico**: no encontré un agregado equivalente por DÍA DE LA SEMANA (solo por hora del día) en esta pasada — puede existir en otra parte de `analytics.js` (es un archivo de 231KB, no lo cubrí completo) pero no until donde busqué.

## 7. Categorización por palabras clave (configurable)

**Tabla**: `keyword_configurations` (`src/services/schema/keywordsTable.js`) — **máximo 10 categorías por cuenta** (`id INT CHECK (id >= 1 AND id <= 10)`), columnas: `title`, `original_description`, `expanded_description`, `sql_query`, `search_terms`, `is_active`, `message_direction` ('inbound'|'outbound'|'both'), `order_position`.

**API completa** (`src/routes/keywords.js`): `GET /` (listar), `GET /stats`, `GET /:id`, `POST /:id/expand` (IA expande la descripción del usuario a términos de búsqueda más completos), `POST /:id/generate-query` (IA genera el `sql_query`), `POST /:id/preview` (probar antes de guardar), `GET /:id/conversations` (ver qué conversaciones matchean), `POST /:id` (crear/editar), `DELETE /:id`.

**Dos generadores de SQL coexisten**:
1. **Actual/simple** (`src/services/keywordQueryBuilder.js`): a partir de `search_terms` (texto separado por coma o salto de línea, con soporte de grupos `"Grupo: term1, term2"`), genera un `CASE WHEN ... ~ E'\\yterm\\y' THEN 'Grupo' ELSE NULL END` — regex Postgres con límites de palabra, case-insensitive, sin IA.
2. **Asistido por IA** (`aiService.expandKeywordDescription` / `generateKeywordSQLQuery`, invocado desde `/expand` y `/generate-query`): el usuario describe la categoría en lenguaje natural, la IA expande y genera el `sql_query` completo, validado después por `services/keywordSqlAdapter.js` (`validateKeywordCaseSqlSafety`) antes de guardarse — para que el usuario no tenga que escribir SQL a mano.

**Confirma que SÍ es configurable por el usuario** (no hardcodeado por categoría) — el ejemplo de "objeciones" que diste (Precio, Tiempo de Decisión, Comparación, Necesidad, Confianza, Autorización) encaja perfectamente como UNA fila de esta tabla con `message_direction='inbound'`, aunque la sintaxis real aquí sería Postgres `~` con límites de palabra, no `REGEXP_CONTAINS` de BigQuery.

**Uso en reportes**: `buildKeywordFilterCTE` (`analytics.js:188-246`) permite filtrar CUALQUIER reporte por una o varias keyword_configurations activas (ej. "mostrar solo conversaciones donde se mencionó precio").

## 8. Rollup diario / agregado por agente (IA)

**Confirmado, pero scopeado por INBOX, no por usuario/agente individual** — importante distinción frente a lo que pediste.

- **Endpoint**: `POST /api/ai/inboxes/:id/analyze` (`routes/ai.js:1826`).
- **Guardado en**: tabla `inboxes` (mismas columnas `artificial_intelligence_1..5` + `ai_analysis_updated_at`, reutilizando el patrón de conversations).
- **Dataset**: "Loads last 10 inbox conversations with messages for aggregated AI analysis" (`loadInboxAnalysisDataset`, comentario en `ai.js:1725`) — exactamente el "promediar las últimas 10 del día" que recordabas.
- **3 modos de análisis** (`buildInboxAnalysisPrompt`, `ai.js:1615-1654`):
  1. Solo los análisis de IA ya generados por conversación (resumen ejecutivo, barato).
  2. Solo el contenido crudo de las conversaciones (detallado, caro).
  3. Híbrido (ambos) — modo default.
- **Prompt** (`ai.js:1616-1619`): *"Eres un experto en análisis de desempeño de asesores de atención al cliente. TAREA: ${fieldTitle}. Tienes acceso a las últimas ${N} conversaciones de un asesor. Analiza estas conversaciones y genera un análisis agregado..."* — el texto dice "asesor" pero el scope real de agrupación es el INBOX completo, no un filtro por `sender_id`/agente dentro de esas conversaciones. Si el inbox tiene varios asesores, el análisis los mezcla a todos.
- **Scheduling / ahorro de tokens (punto clave que pediste)**: confirmado en `src/services/aiScheduleService.js:getConversationsToProcess` (línea 156) — un cron (`cronService.js`, `cronRunner.js`) solo re-analiza una conversación si:
  1. Nunca ha sido analizada (los 5 campos + sentiment están vacíos), **o**
  2. Ya tiene análisis previo pero existe un mensaje con `created_at > ai_analysis_updated_at` (hay mensajes nuevos desde la última vez).
  Con límite diario configurable (`dailyLimit`) y prioridad (sin-análisis primero, luego por fecha de último mensaje). Esto es exactamente el mecanismo de "no repetir conversaciones sin mensajes nuevos" que pediste — ya resuelto y queda igual de aplicable para el rollup por inbox si se le agrega la misma lógica de "solo si cambió algo desde la última corrida".

**Vacío real**: no hay un rollup diario POR AGENTE/USUARIO individual (solo por inbox). Si varios asesores comparten un inbox, no hay cómo separar "el reporte de Juan" de "el reporte de María" con lo que existe hoy — habría que construir esa segmentación desde cero (filtrando conversaciones por `assignee_id`/`sender_id` antes de armar el dataset, reusando el mismo prompt/mecanismo).

## 9. Stack e infraestructura

- **Backend**: Node.js + Express (`"type": "module"`, ESM). Vitest para tests, ESLint.
- **Base de datos**: PostgreSQL vía `pg` directo (queries SQL crudas en todos los servicios, no hay ORM) + `@supabase/supabase-js` (probablemente para auth/storage/realtime, no como motor analítico). **No hay BigQuery.**
- **Cron/jobs**: `node-cron`, orquestado por `src/scripts/cronRunner.js` y `src/services/cronService.js` (55KB — el archivo más grande de services, maneja AI scheduling, habeas data, alertas, etc.).
- **PDFs/reportes exportables**: `exceljs` + `pdfService.js` + `chartjs-node-canvas` (gráficas renderizadas server-side para incluir en PDFs).
- **Integraciones externas**: GoHighLevel (`routes/ghl/`, `services/ghl/`) y Clientify (`routes/clientify/`, `services/clientify/`) — sincronización de agentes/CRM externo, relevante solo si el usuario también usa esas plataformas en paralelo.
- **Cómo llegaban los mensajes**: fuera de alcance de esta revisión (mecanismo de extensión/QR, explícitamente ignorado por instrucción) — pero una vez dentro, aterrizan en las tablas `conversations`/`messages`/`attachments` con la MISMA forma que usa Chatwoot.
- **Frontend**: React (`.jsx`), Chart.js para visualización, Radix/shadcn-style UI components (`components/ui/dialog` etc.).

---

## Resumen de brechas (lo que NO existe todavía, aunque el usuario lo recuerde/quiera)
- Agregado de medios (audio/imagen/archivo, entrante/saliente) por conversación o por asesor — **no existe**, solo el listado crudo de adjuntos.
- Catálogo/búsqueda de "¿se envió la ficha técnica X?" — **no existe**, solo nombre de archivo visible en el listado.
- Rollup de IA diario **por agente individual** — existe por INBOX, no por agente; si el inbox es compartido, no separa resultados por persona.
- Día de la semana pico (vs. hora pico, que sí existe) — no encontrado en la porción revisada de `analytics.js` (archivo de 231KB, no cubierto al 100%).
