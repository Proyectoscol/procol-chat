# Un formulario de WhatsApp Flow llega a Twilio como MessageType=interactive
# con Body vacio -- las respuestas estructuradas van en InteractiveData
# (items con label/value) y/o FlowData (campo => valor crudo, mas
# flow_token). Esta clase reconstruye un texto legible "Label: Valor" por
# linea para el agente, y preserva el JSON crudo completo via
# #content_attributes para que n8n/integraciones lo procesen.
class Twilio::InteractiveMessageParser
  pattr_initialize [:params!]

  def body
    lines_from_items.presence || lines_from_flow_data
  end

  def content_attributes
    { flow_data: flow_data, interactive_data: interactive_data }
  end

  private

  def interactive_data
    @interactive_data ||= parse_json_safely(params[:InteractiveData])
  end

  def flow_data
    @flow_data ||= parse_json_safely(params[:FlowData])
  end

  def lines_from_items
    pages = interactive_data['pages'] || []
    pages.flat_map { |page| format_page_items(page) }.join("\n")
  end

  def format_page_items(page)
    (page['items'] || []).filter_map { |item| format_item(item) }
  end

  def format_item(item)
    value = item['value']
    return nil if value.nil?

    formatted_value = value.is_a?(Array) ? value.join(' / ') : value.to_s
    return nil if formatted_value.blank?

    "#{item['label']}: #{formatted_value}"
  end

  def lines_from_flow_data
    return '' if flow_data.blank?

    flow_data.except('flow_token').map { |k, v| "#{k}: #{v}" }.join("\n")
  end

  def parse_json_safely(json_str)
    return {} if json_str.blank?

    JSON.parse(json_str)
  rescue JSON::ParserError
    {}
  end
end
