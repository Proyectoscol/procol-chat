# Salida estructurada para la sintesis diaria por asesor (ver
# Auditoria::AdvisorDailyRollupService) -- mas enfocado que el de analisis
# por conversacion (Auditoria::ConversationAnalyzerSchema, 5 campos
# configurables) porque este es un digest sobre analisis ya hechos, no un
# analisis nuevo desde cero. feedback_tags_positive/negative se extraen a
# su propia columna (ver persist_result) para poder filtrar/ordenar por
# ellas -- el resto queda dentro del jsonb `results`.
class Auditoria::AdvisorDailyRollupSchema < RubyLLM::Schema
  string :summary, description: 'Resumen narrativo MUY breve (maximo 2-3 frases) de como le fue al asesor en el dia.'
  string :tone_overview, description: 'Vision general del tono emocional predominante entre sus conversaciones del dia.'
  string :recommendation, description: 'Recomendacion principal para el asesor, basada en los patrones detectados ese dia.'
  string :short_feedback, description: 'Retroalimentacion breve y concreta para el asesor, en una frase corta.'
  string :short_feedback_reason,
         description: 'Explica brevemente en que parte(s) de las conversaciones del dia (ver "Conversacion N") se basa esa retroalimentacion.'
  array :feedback_tags_positive, of: :string,
                                 description: 'Lista corta (0 a 4) de etiquetas libres de algo POSITIVO que el asesor hizo bien ese dia ' \
                                              '(ej. "buena empatia").'
  array :feedback_tags_negative,
        description: 'Lista corta (0 a 4) de areas de mejora detectadas ese dia (ej. "manejo de objeciones"), cada una con su justificacion.' do
    object do
      string :tag, description: 'Nombre corto de la etiqueta de mejora (ej. "manejo de objeciones").'
      string :reason, description: 'Frase breve citando que paso en la(s) conversacion(es) que origino esta etiqueta.'
      array :conversation_numbers, of: :integer,
                                   description: 'Numero(s) de "Conversacion N" (ver el texto de analisis) de donde sale esta etiqueta.'
    end
  end
end
