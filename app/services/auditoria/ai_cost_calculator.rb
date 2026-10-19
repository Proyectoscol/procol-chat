# Calcula el costo en USD de una llamada a OpenAI a partir de los tokens
# reales y la tabla de precios que RubyLLM ya trae integrada (ni esta clase
# ni nada en Auditoria mantiene una tabla de precios a mano) - ver
# RubyLLM::Model::Info#pricing. Si el modelo no esta registrado o no tiene
# precio publicado, devuelve nil en vez de adivinar.
class Auditoria::AiCostCalculator
  def self.calculate(model:, prompt_tokens:, completion_tokens:)
    pricing = text_token_pricing(model)
    return nil unless priced?(pricing)

    input_cost = prompt_tokens.to_i * pricing.input_per_million
    output_cost = completion_tokens.to_i * pricing.output_per_million
    ((input_cost + output_cost) / 1_000_000.0).round(6)
  end

  def self.text_token_pricing(model)
    RubyLLM.models.find(model)&.pricing&.text_tokens&.standard
  rescue RubyLLM::ModelNotFoundError
    nil
  end
  private_class_method :text_token_pricing

  def self.priced?(pricing)
    pricing.present? && pricing.input_per_million && pricing.output_per_million
  end
  private_class_method :priced?
end
