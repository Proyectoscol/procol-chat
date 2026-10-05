require 'rails_helper'

RSpec.describe Cartera::PriorizacionService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  def crear_cliente(**attrs)
    Cartera::Cliente.create!(
      account: account, external_id: SecureRandom.hex(4), identificacion: '900123456',
      nombre: 'Cliente de prueba', tipo_deudor: :empresa, **attrs
    )
  end

  def crear_factura(cliente, fecha_vencimiento:, saldo_pendiente:, valor_total: saldo_pendiente)
    Cartera::Factura.create!(
      account: account, cliente: cliente, external_id: SecureRandom.hex(4), numero: "FV-#{SecureRandom.hex(2)}",
      fecha_emision: fecha_vencimiento - 30.days, fecha_vencimiento: fecha_vencimiento,
      valor_total: valor_total, saldo_pendiente: saldo_pendiente
    )
  end

  describe '#recalcular' do
    it 'no crea un caso para un cliente sin saldo abierto y sin caso previo' do
      cliente = crear_cliente
      crear_factura(cliente, fecha_vencimiento: 10.days.ago, saldo_pendiente: 0)

      service.recalcular

      expect(cliente.reload.caso).to be_nil
    end

    it 'marca no_cobrar para un cliente estrategico aunque tenga saldo abierto' do
      cliente = crear_cliente(es_estrategico: true)
      crear_factura(cliente, fecha_vencimiento: 10.days.ago, saldo_pendiente: 100_000)

      service.recalcular

      caso = cliente.reload.caso
      expect(caso.no_cobrar).to be true
      expect(caso.razon_no_cobrar).to eq('Cliente marcado como estrategico.')
      expect(caso.puntaje_riesgo).to eq(0)
    end

    it 'calcula el nivel de escalamiento prejuridico para mora entre 61 y 180 dias' do
      cliente = crear_cliente
      crear_factura(cliente, fecha_vencimiento: 100.days.ago, saldo_pendiente: 500_000)

      service.recalcular

      expect(cliente.reload.caso.nivel_escalamiento).to eq('prejuridico')
    end

    it 'calcula el nivel de escalamiento juridico para mora mayor a 180 dias' do
      cliente = crear_cliente
      crear_factura(cliente, fecha_vencimiento: 200.days.ago, saldo_pendiente: 500_000)

      service.recalcular

      expect(cliente.reload.caso.nivel_escalamiento).to eq('juridico')
    end

    it 'es idempotente: correrlo dos veces no duplica el caso ni cambia el resultado' do
      cliente = crear_cliente
      crear_factura(cliente, fecha_vencimiento: 40.days.ago, saldo_pendiente: 300_000)

      service.recalcular
      primer_score = cliente.reload.caso.puntaje_riesgo
      service.recalcular

      expect(Cartera::Caso.where(cliente: cliente).count).to eq(1)
      expect(cliente.reload.caso.puntaje_riesgo).to eq(primer_score)
    end
  end

  describe '#listar_paginado' do
    it 'excluye los casos no_cobrar por defecto' do
      cobrable = crear_cliente
      crear_factura(cobrable, fecha_vencimiento: 10.days.ago, saldo_pendiente: 100_000)
      no_cobrable = crear_cliente(es_estrategico: true)
      crear_factura(no_cobrable, fecha_vencimiento: 10.days.ago, saldo_pendiente: 100_000)
      service.recalcular

      resultado = service.listar_paginado

      ids = resultado[:items].map { |item| item[:cliente_id] }
      expect(ids).to include(cobrable.id)
      expect(ids).not_to include(no_cobrable.id)
    end
  end
end
