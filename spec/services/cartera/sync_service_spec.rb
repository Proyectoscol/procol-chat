require 'rails_helper'

RSpec.describe Cartera::SyncService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  let(:datos) do
    {
      clientes: [{ external_id: 'c1', tipo_deudor: :empresa, identificacion: '900111222',
                   nombre: 'Cliente Uno', email: nil, telefono: nil, sucursal: 'Bogotá' }],
      cupos: [{ cliente_external_id: 'c1', cupo_asignado: 1_000_000 }],
      facturas: [{ external_id: 'f1', cliente_external_id: 'c1', numero: 'FV-1', cufe: 'CUFE-1',
                   fecha_emision: 30.days.ago, fecha_vencimiento: 10.days.ago, valor_total: 500_000 }],
      notas_credito: [{ external_id: 'nc1', factura_external_id: 'f1', valor: 50_000, fecha: 5.days.ago, motivo: 'Descuento' }],
      pagos: [{ external_id: 'p1', cliente_external_id: 'c1', factura_external_id: 'f1',
                fecha: 2.days.ago, valor: 100_000, medio_pago: 'transferencia' }],
      anticipos: [{ external_id: 'a1', cliente_external_id: 'c1', fecha: 1.day.ago, valor: 20_000 }]
    }
  end

  let(:connector) do
    instance_double(
      Cartera::ErpConnector,
      fetch_clientes: datos[:clientes], fetch_cupos: datos[:cupos], fetch_facturas: datos[:facturas],
      fetch_notas_credito: datos[:notas_credito], fetch_pagos: datos[:pagos], fetch_anticipos: datos[:anticipos]
    )
  end

  it 'crea cliente, factura, nota credito, pago y anticipo en la primera corrida' do
    service.run('alegra', connector)

    expect(Cartera::Cliente.where(account: account).count).to eq(1)
    factura = Cartera::Factura.find_by(account: account, external_id: 'f1')
    expect(factura.saldo_pendiente.to_f).to eq(500_000 - 50_000 - 100_000)
    expect(Cartera::Pago.where(account: account).count).to eq(2) # pago regular + anticipo
  end

  it 'es idempotente: correr la misma corrida dos veces no duplica filas ni vuelve a descontar saldo' do
    service.run('alegra', connector)
    service.run('alegra', connector)

    expect(Cartera::Cliente.where(account: account).count).to eq(1)
    expect(Cartera::Factura.where(account: account).count).to eq(1)
    expect(Cartera::NotaCredito.where(account: account).count).to eq(1)
    expect(Cartera::Pago.where(account: account).count).to eq(2)

    factura = Cartera::Factura.find_by(account: account, external_id: 'f1')
    expect(factura.saldo_pendiente.to_f).to eq(500_000 - 50_000 - 100_000)
  end

  it 'registra la corrida en CorridaSync con el resultado' do
    resultado = service.run('alegra', connector)

    corrida = Cartera::CorridaSync.find(resultado.corrida_id)
    expect(corrida.estado).to eq('exitosa')
    expect(corrida.registros_procesados).to eq(resultado.registros_procesados)
  end
end
