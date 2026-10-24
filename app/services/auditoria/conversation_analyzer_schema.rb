# 5 campos fijos para esta fase (ver Auditoria::AiFieldConfig::DEFAULTS) -- un
# conteo/orden variable de campos queda para cuando construyamos la pantalla
# de configuracion. Las claves (field_1..field_5) son un detalle interno; los
# titulos que el usuario ve vienen de AiFieldConfig, no de aqui. sentiment es
# aparte de los 5 -- una clasificacion estructural fija (tendencia de
# sentimiento por asesor/equipo/bandeja), no un campo configurable por el
# cliente, por eso vive en su propia columna (ver persist_result) en vez de
# dentro de `results`.
class Auditoria::ConversationAnalyzerSchema < RubyLLM::Schema
  string :field_1, description: 'Respuesta a la tarea 1 solicitada en las instrucciones.'
  string :field_2, description: 'Respuesta a la tarea 2 solicitada en las instrucciones.'
  string :field_3, description: 'Respuesta a la tarea 3 solicitada en las instrucciones.'
  string :field_4, description: 'Respuesta a la tarea 4 solicitada en las instrucciones.'
  string :field_5, description: 'Respuesta a la tarea 5 solicitada en las instrucciones.'
  string :sentiment, enum: %w[positive neutral negative],
                     description: 'Sentimiento general del cliente a lo largo de toda la conversacion.'
end
