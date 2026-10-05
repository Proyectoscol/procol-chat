# Resuelve los valores reales de las variables semanticas de una plantilla
# (nombre_cliente, saldo_abierto, etc.) a partir de la foto que guardo
# cartera_envios en el momento del envio - nunca de las facturas abiertas
# actuales del cliente, que para cuando esto se procese pueden ser otras.
class Cartera::Campanas::VariableResolver
  pattr_initialize [:envio!]

  # mapa_variables: {"1" => "nombre_cliente", "2" => "saldo_abierto", ...}
  # (Cartera::PlantillaWhatsapp#variables) -> {"1" => "Juan Perez", "2" => "$300.000"}
  def resolve_todas(mapa_variables)
    Hash(mapa_variables).transform_values { |nombre_semantico| resolve(nombre_semantico) }
  end

  def resolve(nombre_semantico)
    case nombre_semantico
    when 'nombre_cliente' then cliente.nombre.to_s
    when 'saldo_abierto' then formatear_cop(envio.saldo_al_enviar)
    when 'dias_vencido' then envio.dias_vencido_max_al_enviar.to_s
    when 'tramo' then I18n.t("cartera.tramos.#{envio.tramo_al_enviar}", default: envio.tramo_al_enviar.to_s)
    when 'numero_factura' then numeros_factura
    when 'fecha_vencimiento' then fecha_vencimiento_mas_proxima
    else ''
    end
  end

  private

  def cliente
    @cliente ||= envio.cliente
  end

  def facturas
    @facturas ||= Cartera::Factura.where(id: envio.factura_ids)
  end

  def numeros_factura
    facturas.pluck(:numero).join(', ')
  end

  def fecha_vencimiento_mas_proxima
    facturas.minimum(:fecha_vencimiento)&.to_date&.strftime('%d/%m/%Y').to_s
  end

  def formatear_cop(valor)
    return '' if valor.nil?

    ActiveSupport::NumberHelper.number_to_currency(valor, unit: '$', precision: 0, delimiter: '.', separator: ',')
  end
end
