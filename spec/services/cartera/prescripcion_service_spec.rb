require 'rails_helper'

RSpec.describe Cartera::PrescripcionService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }
  let(:cliente) do
    Cartera::Cliente.create!(
      account: account, external_id: SecureRandom.hex(4), identificacion: '900123456',
      nombre: 'Cliente de prueba', tipo_deudor: :empresa
    )
  end

  def crear_factura(fecha_vencimiento:, saldo_pendiente: 500_000)
    Cartera::Factura.create!(
      account: account, cliente: cliente, external_id: SecureRandom.hex(4), numero: "FV-#{SecureRandom.hex(2)}",
      fecha_emision: fecha_vencimiento - 30.days, fecha_vencimiento: fecha_vencimiento,
      valor_total: saldo_pendiente, saldo_pendiente: saldo_pendiente
    )
  end

  describe '#recalcular' do
    it 'crea una alerta "vencida" cuando el limite legal (vencimiento + 3 anos) ya paso' do
      crear_factura(fecha_vencimiento: 3.years.ago - 10.days)

      service.recalcular

      alerta = account.cartera_alertas.sole
      expect(alerta.fecha_limite).to be < Date.current
    end

    it 'crea una alerta "3_meses" cuando el limite legal cae dentro de los proximos 90 dias' do
      crear_factura(fecha_vencimiento: 3.years.ago.to_date + 60.days)

      resultado = service.recalcular

      expect(resultado[:alertas_vigentes]).to eq(1)
    end

    it 'no crea alerta cuando el limite legal esta a mas de 12 meses' do
      crear_factura(fecha_vencimiento: 1.year.ago)

      resultado = service.recalcular

      expect(resultado[:alertas_vigentes]).to eq(0)
      expect(account.cartera_alertas.count).to eq(0)
    end

    it 'nunca pisa el campo leida en una alerta existente' do
      crear_factura(fecha_vencimiento: 3.years.ago - 10.days)
      service.recalcular
      alerta = account.cartera_alertas.sole
      service.marcar_leida(alerta.id, true)

      service.recalcular

      expect(alerta.reload.leida).to be true
    end

    it 'elimina la alerta cuando la factura deja de calificar (se paga)' do
      factura = crear_factura(fecha_vencimiento: 3.years.ago - 10.days)
      service.recalcular
      expect(account.cartera_alertas.count).to eq(1)

      factura.update!(saldo_pendiente: 0)
      resultado = service.recalcular

      expect(resultado[:alertas_eliminadas]).to eq(1)
      expect(account.cartera_alertas.count).to eq(0)
    end
  end
end
