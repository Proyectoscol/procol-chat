# Salida estructurada para la sintesis diaria por asesor (ver
# Auditoria::AdvisorDailyRollupService) -- 3 campos fijos, mas enfocado que
# el de analisis por conversacion (Auditoria::ConversationAnalyzerSchema,
# 5 campos configurables) porque este es un digest sobre analisis ya
# hechos, no un analisis nuevo desde cero.
class Auditoria::AdvisorDailyRollupSchema < RubyLLM::Schema
  string :summary, description: 'Resumen narrativo de como le fue al asesor en el dia, basado en los analisis de sus conversaciones.'
  string :tone_overview, description: 'Vision general del tono emocional predominante entre sus conversaciones del dia.'
  string :recommendation, description: 'Recomendacion principal para el asesor, basada en los patrones detectados ese dia.'
end
