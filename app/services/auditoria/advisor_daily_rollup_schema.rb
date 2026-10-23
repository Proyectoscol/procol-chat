# Salida estructurada para la sintesis diaria por asesor (ver
# Auditoria::AdvisorDailyRollupService) -- 5 campos fijos, mas enfocado que
# el de analisis por conversacion (Auditoria::ConversationAnalyzerSchema,
# 5 campos configurables) porque este es un digest sobre analisis ya
# hechos, no un analisis nuevo desde cero. feedback_tags se extrae a su
# propia columna (ver persist_result) para poder filtrar/ordenar por el --
# el resto queda dentro del jsonb `results`.
class Auditoria::AdvisorDailyRollupSchema < RubyLLM::Schema
  string :summary, description: 'Resumen narrativo MUY breve (maximo 2-3 frases) de como le fue al asesor en el dia.'
  string :tone_overview, description: 'Vision general del tono emocional predominante entre sus conversaciones del dia.'
  string :recommendation, description: 'Recomendacion principal para el asesor, basada en los patrones detectados ese dia.'
  string :short_feedback, description: 'Retroalimentacion breve y concreta para el asesor, en una frase corta.'
  array :feedback_tags, of: :string,
                        description: 'Lista corta (1 a 4) de categorias libres de retroalimentacion detectadas ese dia (ej. "manejo de objeciones").'
end
