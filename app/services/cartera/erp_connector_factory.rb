# Selector explicito por variable de entorno (ERP_PROVEEDOR): un valor
# explicito decide, y solo entonces se exigen las variables especificas de
# ese proveedor. Punto de extension para un futuro conector de Carvajal -
# una clase nueva heredando de Cartera::ErpConnector, sin tocar SyncService.
class Cartera::ErpConnectorFactory
  def self.build
    proveedor = ENV.fetch('ERP_PROVEEDOR', 'alegra')

    case proveedor
    when 'alegra'
      email = ENV.fetch('ALEGRA_EMAIL', nil)
      token = ENV.fetch('ALEGRA_TOKEN', nil)
      raise 'ERP_PROVEEDOR="alegra" requiere ALEGRA_EMAIL y ALEGRA_TOKEN.' if email.blank? || token.blank?

      Cartera::AlegraConnector.new(email: email, token: token)
    else
      raise "ERP_PROVEEDOR=\"#{proveedor}\" no esta implementado en este sistema. Usa \"alegra\"."
    end
  end
end
