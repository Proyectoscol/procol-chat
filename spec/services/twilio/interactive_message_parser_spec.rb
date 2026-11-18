require 'rails_helper'

describe Twilio::InteractiveMessageParser do
  describe '#body' do
    it 'formats InteractiveData items into "Label: Valor" lines' do
      interactive_data = {
        pages: [{ items: [{ label: 'Nombre', value: 'Maria' }, { label: 'Servicios', value: %w[Urodinamia Cistoscopia] }] }]
      }.to_json

      parser = described_class.new(params: { InteractiveData: interactive_data })
      expect(parser.body).to eq("Nombre: Maria\nServicios: Urodinamia / Cistoscopia")
    end

    it 'skips items with a blank value' do
      interactive_data = { pages: [{ items: [{ label: 'Nombre', value: 'Maria' }, { label: 'Vacio', value: '' }] }] }.to_json

      parser = described_class.new(params: { InteractiveData: interactive_data })
      expect(parser.body).to eq('Nombre: Maria')
    end

    it 'falls back to FlowData (excluding flow_token) when InteractiveData has no items' do
      flow_data = { flow_token: 'tok123', cedula: '123456789', eps: 'Sura' }.to_json

      parser = described_class.new(params: { FlowData: flow_data })
      expect(parser.body).to eq("cedula: 123456789\neps: Sura")
    end

    it 'returns an empty string when there is no usable data' do
      parser = described_class.new(params: {})
      expect(parser.body).to eq('')
    end

    it 'does not raise on malformed JSON' do
      parser = described_class.new(params: { InteractiveData: 'not json', FlowData: 'also not json' })
      expect(parser.body).to eq('')
    end
  end

  describe '#content_attributes' do
    it 'preserves the raw parsed JSON under flow_data and interactive_data' do
      interactive_data = { pages: [] }.to_json
      flow_data = { flow_token: 'tok123' }.to_json

      parser = described_class.new(params: { InteractiveData: interactive_data, FlowData: flow_data })
      expect(parser.content_attributes).to eq(
        flow_data: { 'flow_token' => 'tok123' },
        interactive_data: { 'pages' => [] }
      )
    end
  end
end
