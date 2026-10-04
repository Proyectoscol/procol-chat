require 'rails_helper'

RSpec.describe Cartera::AlegraConnector do
  let(:api_client) { instance_double(Cartera::Alegra::ApiClient) }
  let(:connector) { described_class.new(email: 'cobranza@procol.co', token: 'token-de-prueba') }

  let(:contactos) do
    [
      { 'id' => 1, 'kindOfPerson' => 'PERSON_ENTITY', 'identification' => '123', 'name' => 'Juan Perez',
        'email' => 'juan@test.com', 'phonePrimary' => '3001234567', 'mobile' => nil, 'creditLimit' => 500_000,
        'address' => { 'department' => 'Bogotá' } },
      { 'id' => 2, 'kindOfPerson' => 'BUSINESS', 'identification' => '900999888', 'name' => 'Empresa SAS',
        'email' => nil, 'phonePrimary' => nil, 'mobile' => '3109876543', 'creditLimit' => 0, 'address' => {} }
    ]
  end

  let(:facturas_crudas) do
    [
      { 'id' => 10, 'status' => 'open', 'client' => { 'id' => 1 },
        'numberTemplate' => { 'fullNumber' => 'FV-10', 'prefix' => 'FV-', 'number' => 10 },
        'stamp' => { 'cufe' => 'CUFE-10' }, 'date' => '2026-01-01', 'dueDate' => '2026-01-31', 'total' => 500_000,
        'payments' => [{ 'id' => 100, 'date' => '2026-01-15', 'amount' => 200_000, 'paymentMethod' => 'CASH' }],
        'retentions' => [{ 'id' => 1, 'amount' => 5_000, 'name' => 'ReteFuente' }],
        'events' => [
          { 'type' => 'CLIENT_ACCEPTANCE', 'status' => 'ACCEPTED_DIAN', 'date' => '2026-01-05' },
          { 'type' => 'CLIENT_EMAILS', 'status' => 'SENT', 'date' => '2026-01-02' }
        ] },
      { 'id' => 11, 'status' => 'draft', 'client' => { 'id' => 2 }, 'numberTemplate' => {}, 'stamp' => {},
        'date' => '2026-02-01', 'dueDate' => nil, 'total' => 100_000, 'payments' => [], 'retentions' => [], 'events' => [] }
    ]
  end

  let(:notas_credito_crudas) do
    [
      { 'id' => 50, 'status' => 'open', 'invoices' => [{ 'id' => 10 }], 'total' => 30_000,
        'date' => '2026-01-20', 'type' => 'OTHER', 'observations' => nil },
      { 'id' => 51, 'status' => 'void', 'invoices' => [{ 'id' => 10 }], 'total' => 99_999, 'date' => '2026-01-21', 'type' => 'OTHER' }
    ]
  end

  before do
    allow(Cartera::Alegra::ApiClient).to receive(:new).and_return(api_client)
    allow(api_client).to receive(:paginar).with('/contacts', { type: 'client' }).and_return(contactos)
    allow(api_client).to receive(:paginar)
      .with('/invoices', { order_field: 'id', order_direction: 'ASC', fields: 'events,payments,retentions' })
      .and_return(facturas_crudas)
    allow(api_client).to receive(:paginar).with('/credit-notes').and_return(notas_credito_crudas)
  end

  describe '#fetch_clientes' do
    it 'mapea tipo_deudor y datos de contacto de cada contacto de Alegra' do
      clientes = connector.fetch_clientes

      expect(clientes).to contain_exactly(
        hash_including(external_id: '1', tipo_deudor: :persona_natural, identificacion: '123',
                       nombre: 'Juan Perez', email: 'juan@test.com', telefono: '3001234567', sucursal: 'Bogotá'),
        hash_including(external_id: '2', tipo_deudor: :empresa, nombre: 'Empresa SAS', telefono: '3109876543')
      )
    end
  end

  describe '#fetch_cupos' do
    it 'solo incluye contactos con creditLimit positivo' do
      expect(connector.fetch_cupos).to eq([{ cliente_external_id: '1', cupo_asignado: 500_000.0 }])
    end
  end

  describe '#fetch_facturas' do
    it 'excluye facturas en estado draft/void y mapea numero, cufe y fechas' do
      facturas = connector.fetch_facturas

      expect(facturas.size).to eq(1)
      expect(facturas.first).to include(
        external_id: '10', cliente_external_id: '1', numero: 'FV-10', cufe: 'CUFE-10', valor_total: 500_000.0
      )
    end
  end

  describe '#fetch_pagos' do
    it 'identifica la factura exacta de cada pago embebido' do
      pagos = connector.fetch_pagos

      expect(pagos).to eq([
                            { external_id: '100:10', cliente_external_id: '1', factura_external_id: '10',
                              fecha: Time.zone.parse('2026-01-15'), valor: 200_000.0, medio_pago: 'CASH' }
                          ])
    end
  end

  describe '#fetch_notas_credito' do
    it 'combina las notas credito reales con las retenciones sintetizadas' do
      notas = connector.fetch_notas_credito

      nota_real = notas.find { |n| n[:external_id] == '50' }
      retencion = notas.find { |n| n[:external_id] == 'retencion:10:1' }

      expect(notas.size).to eq(2) # excluye la nota 51 (void)
      expect(nota_real).to include(factura_external_id: '10', valor: 30_000.0, motivo: 'Otro')
      expect(retencion).to include(factura_external_id: '10', valor: 5_000.0, motivo: 'Retención ReteFuente')
    end
  end

  describe '#fetch_eventos_radian' do
    it 'solo mapea eventos CLIENT_ACCEPTANCE con un estado conocido' do
      eventos = connector.fetch_eventos_radian

      expect(eventos).to eq([
                              { factura_external_id: '10', tipo_evento: :evento_033,
                                fecha: Time.zone.parse('2026-01-05'), fuente: 'alegra' }
                            ])
    end
  end
end
