# Corre una campana contra el entorno de pruebas: mismas compuertas de
# elegibilidad que Cartera::Campanas::SimulacionService (no_cobrar,
# exclusion manual, match de reglas, disponibilidad de canal, canal
# bloqueado, compuerta de IA del paso 9) pero a diferencia de esa, SI
# escribe cartera_envios y SI dispara el envio real (EnvioWhatsappService /
# EnvioEmailService) - marcados modo_prueba: true, lo que hace que esos dos
# servicios enruten la conversacion a la bandeja de pruebas (Channel::Api,
# ver InboxPruebasResolver) en vez de la bandeja real de la campana.
#
# Deliberadamente NO corre las compuertas temporales de CorridaService (dia
# de envio, ventana horaria, "ya contactado hoy") - un admin probando una
# campana quiere poder hacerlo en cualquier momento, cuantas veces necesite
# mientras ajusta reglas, no solo dentro de la ventana de envio configurada.
# Tampoco exige plantilla de WhatsApp aprobada por Meta: la bandeja de
# pruebas no llama a Twilio, esa aprobacion no aplica aqui - es justamente
# lo que permite probar una campana antes de que Meta apruebe sus
# plantillas.
class Cartera::Campanas::PruebaService
  pattr_initialize [:campana!]

  def call
    resultado = { casos_enviados: 0, casos_omitidos: 0, errores: [] }

    casos.each do |caso|
      if evaluar_caso(caso)
        resultado[:casos_enviados] += 1
      else
        resultado[:casos_omitidos] += 1
      end
    rescue StandardError => e
      resultado[:errores] << "#{caso.cliente.nombre} (cliente ##{caso.cliente_id}): #{e.message}"
    end

    resultado
  end

  private

  def casos
    campana.account.cartera_casos.includes(:cliente)
  end

  def evaluar_caso(caso)
    regla = resolver_regla_aplicable(caso)
    return false if regla.nil?

    canal = resolver_canal(caso.cliente, regla)
    return false if canal.nil?

    decision = decidir_envio(caso, regla, canal)
    return false if decision && !decision[:enviar]

    crear_y_enviar(caso, regla, canal)
    true
  end

  def resolver_regla_aplicable(caso)
    return nil if caso.no_cobrar
    return nil if caso.excluido_hasta.present? && caso.excluido_hasta.future?

    regla = Cartera::Campanas::ReglaMatcher.primera_coincidencia(campana.reglas, caso)
    return nil if regla.nil? || regla.accion == 'excluir'

    regla
  end

  # Compuerta 9, igual que CorridaService: solo para casos con una nota de
  # contacto de los ultimos 7 dias.
  def decidir_envio(caso, regla, canal)
    return nil unless interaccion_reciente?(caso)

    Cartera::Campanas::DecisionEnvioService.new(caso: caso, mensaje_propuesto: resumen_mensaje(caso, regla, canal)).decidir
  end

  def interaccion_reciente?(caso)
    contact = caso.cliente.contact
    return false if contact.nil?

    contact.notes.exists?(created_at: 7.days.ago..)
  end

  def resumen_mensaje(caso, regla, canal)
    "Canal: #{canal}. Tramo: #{caso.tramo}. Saldo abierto: #{caso.saldo_abierto}. " \
      "Dias vencido: #{caso.dias_vencido_max}. Facturas: #{facturas_abiertas_de(caso).join(', ')}. Regla ##{regla.orden}."
  end

  def resolver_canal(cliente, regla)
    return 'whatsapp' if whatsapp_disponible?(cliente, regla)
    return 'email' if email_disponible?(cliente, regla)

    nil
  end

  def whatsapp_disponible?(cliente, regla)
    return false if regla.plantilla_whatsapp_content_sid.blank?
    return false if bloqueado?(cliente, 'whatsapp')

    Cartera::IndicativoTelefonico.clasificar_telefono(cliente.telefono, cliente.sucursal)&.dig(:tipo) == :celular
  end

  def email_disponible?(cliente, regla)
    return false if regla.plantilla_email_id.blank?
    return false if bloqueado?(cliente, 'email')

    cliente.email.present?
  end

  def bloqueado?(cliente, canal)
    canales_bloqueados[[cliente.id, canal]]
  end

  def canales_bloqueados
    @canales_bloqueados ||= campana.account.cartera_canales_bloqueados.pluck(:cliente_id, :canal).index_with { true }
  end

  def crear_y_enviar(caso, regla, canal)
    envio = campana.account.cartera_envios.create!(
      campana: campana, campana_regla: regla, cliente_id: caso.cliente_id,
      factura_ids: facturas_abiertas_de(caso), saldo_al_enviar: caso.saldo_abierto,
      tramo_al_enviar: caso.tramo, dias_vencido_max_al_enviar: caso.dias_vencido_max,
      canal: canal, estado: 'programado', modo_prueba: true
    )

    if canal == 'whatsapp'
      Cartera::Campanas::EnvioWhatsappService.new(envio: envio).call
    else
      Cartera::Campanas::EnvioEmailService.new(envio: envio).call
    end
  end

  def facturas_abiertas_de(caso)
    caso.cliente.facturas.where('saldo_pendiente > 0').pluck(:id)
  end
end
