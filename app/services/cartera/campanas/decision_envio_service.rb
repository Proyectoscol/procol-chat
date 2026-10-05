# Compuerta 9: solo para casos con una nota de contacto de menos de 7 dias
# (ver Cartera::Campanas::CorridaService#interaccion_reciente?) - le
# pregunta al LLM si, dado lo que el cliente ya dijo, tiene sentido enviar
# el mensaje de hoy. Puerto de Captain::Llm::ContactNotesService (mismo
# patron Llm::BaseAiService + RubyLLM + JSON) para un caso de uso distinto.
class Cartera::Campanas::DecisionEnvioService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  def initialize(caso:, mensaje_propuesto:)
    super(feature: 'assistant', account: caso.cliente.account)
    @caso = caso
    @cliente = caso.cliente
    @mensaje_propuesto = mensaje_propuesto
  end

  # { enviar: true/false, razon: "..." } - en caso de error del LLM,
  # enviar: false (decision explicita del usuario: un mensaje de menos no
  # molesta a nadie, uno de mas a quien ya pidio que lo dejen en paz si).
  def decidir
    response = instrument_llm_call(instrumentation_params) do
      chat.with_params(response_format: { type: 'json_object' }).with_instructions(system_prompt).ask(contenido)
    end
    parse_response(response.content)
  rescue StandardError => e
    # Deliberadamente StandardError, no solo RubyLLM::Error: errores de
    # configuracion (ej. RubyLLM::ConfigurationError por falta de API key)
    # heredan directo de StandardError, no de RubyLLM::Error, y deben
    # degradar igual a "no enviar" en vez de tumbar la corrida de la cuenta.
    ChatwootExceptionTracker.new(e, account: @cliente.account).capture_exception
    { enviar: false, razon: "No se pudo consultar el modelo: #{e.message}" }
  end

  private

  def contenido
    <<~TEXT
      # Notas recientes del cliente (ultimos 90 dias)
      #{notas_recientes}

      # Envios anteriores de esta campana (facturas y resultado de cada uno)
      #{envios_previos}

      # Mensaje que se enviaria hoy
      #{@mensaje_propuesto}
    TEXT
  end

  def notas_recientes
    contact = @cliente.contact
    return 'Sin notas registradas.' if contact.nil?

    notas = contact.notes.where(created_at: 90.days.ago..).order(created_at: :desc)
    return 'Sin notas registradas.' if notas.empty?

    notas.map { |n| "- #{n.created_at.to_date}: #{n.content}" }.join("\n")
  end

  def envios_previos
    scope = @cliente.account.cartera_envios.where(cliente_id: @cliente.id).where.not(estado: 'programado')
    envios = scope.order(created_at: :desc).limit(10)
    return 'Sin envios previos.' if envios.empty?

    envios.map { |e| resumen_envio_previo(e) }.join("\n")
  end

  def resumen_envio_previo(envio)
    "- #{envio.created_at.to_date}: facturas #{envio.factura_ids.join(', ')}, " \
      "estado=#{envio.estado}, resultado=#{envio.resultado || 'sin resultado'}"
  end

  def system_prompt
    <<~PROMPT
      Eres un asistente de cobranza. Evalua si, dado lo que el cliente ya
      dijo en sus notas recientes, tiene sentido enviarle HOY el mensaje
      de cobro propuesto, o si deberia omitirse por ahora.

      Omite el envio si el cliente ya esta en proceso de pago, pidio que
      lo contacten en otra fecha que aun no ha llegado, o si enviar seria
      redundante o inoportuno dado lo que ya se hablo.

      Las facturas de envios anteriores pueden ser DISTINTAS a las del
      mensaje de hoy: si el cliente prometio pagar una factura especifica
      y ya la pago, pero hoy hay una factura NUEVA y diferente vencida, SI
      tiene sentido enviar.

      Responde unicamente en JSON: {"enviar": true o false, "razon": "..."}
    PROMPT
  end

  def instrumentation_params
    {
      span_name: 'llm.cartera.decision_envio',
      model: @model,
      temperature: @temperature,
      account_id: @cliente.account_id,
      feature_name: 'cartera_decision_envio',
      messages: [{ role: 'system', content: system_prompt }, { role: 'user', content: contenido }],
      metadata: { caso_id: @caso.id, cliente_id: @cliente.id }
    }
  end

  def parse_response(response)
    return { enviar: false, razon: 'Respuesta vacia del modelo.' } if response.nil?

    data = JSON.parse(sanitize_json_response(response))
    { enviar: ActiveModel::Type::Boolean.new.cast(data['enviar']), razon: data['razon'].to_s }
  rescue JSON::ParserError => e
    Rails.logger.error("Cartera::Campanas::DecisionEnvioService: error parseando respuesta del LLM: #{e.message}")
    { enviar: false, razon: 'No se pudo interpretar la respuesta del modelo.' }
  end
end
