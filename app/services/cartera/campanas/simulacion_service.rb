# Corrida en seco de una campana: cuantos clientes le pegaria a cada regla,
# por que canal, y cuanto costaria - sin enviar nada y sin escribir
# cartera_envios. Deliberadamente NO corre las compuertas temporales (campana
# activa/dia de envio, ventana horaria instantanea, ya contactado hoy): esas
# dependen del momento en que se ejecuta la corrida real (Cartera::Campanas::
# CorridaJob, ver tarea 5) y harian la simulacion inutil fuera de esa
# ventana exacta. Esto evalua solo elegibilidad (no_cobrar, exclusion
# manual, match de regla, disponibilidad de canal, plantilla lista) - lo que
# de verdad responde "si activo esto, que pasaria".
class Cartera::Campanas::SimulacionService
  pattr_initialize [:campana!]

  def call
    resultados_por_regla = Hash.new { |h, k| h[k] = regla_vacia }
    resumen = resumen_vacio

    casos.each do |caso|
      resumen[:total_casos_evaluados] += 1
      evaluar_caso(caso, resultados_por_regla, resumen)
    end

    {
      campana_id: campana.id,
      fecha_calculo: Time.current,
      tarifas_actualizadas_at: tarifas_actualizadas_at,
      advertencia_frecuencia: advertencia_frecuencia,
      resumen: resumen,
      por_regla: campana.reglas.map { |regla| regla_resumen(regla, resultados_por_regla[regla.id]) }
    }
  end

  private

  def casos
    campana.account.cartera_casos.includes(:cliente)
  end

  def evaluar_caso(caso, resultados_por_regla, resumen)
    if caso.no_cobrar
      resumen[:total_excluidos_no_cobrar] += 1
      return
    end
    if caso.excluido_hasta.present? && caso.excluido_hasta.future?
      resumen[:total_excluidos_manual] += 1
      return
    end

    regla = Cartera::Campanas::ReglaMatcher.primera_coincidencia(campana.reglas, caso)
    if regla.nil?
      resumen[:total_sin_regla] += 1
      return
    end
    if regla.accion == 'excluir'
      resultados_por_regla[regla.id][:cantidad_excluidos] += 1
      return
    end

    resumen[:total_a_enviar] += 1
    acumular_envio(resultados_por_regla[regla.id], caso, regla, resumen)
  end

  def acumular_envio(acumulado, caso, regla, resumen)
    acumulado[:cantidad_clientes] += 1
    canal = resolver_canal(caso.cliente, regla)
    acumulado[:por_canal][canal] += 1
    return unless canal == 'whatsapp'

    costo = costo_estimado(regla)
    acumulado[:costo_estimado] += costo
    resumen[:costo_total_estimado] += costo
  end

  # Igual que la resolucion real (tarea 5), pero sin el "ya use este canal
  # esta semana": la simulacion no tiene una semana concreta a la cual
  # atarse, solo pregunta "este cliente seria alcanzable por este canal".
  def resolver_canal(cliente, regla)
    if whatsapp_disponible?(cliente, regla)
      'whatsapp'
    elsif email_disponible?(cliente, regla)
      'email'
    else
      'sin_canal_disponible'
    end
  end

  def whatsapp_disponible?(cliente, regla)
    return false if regla.plantilla_whatsapp_content_sid.blank?
    return false if canales_bloqueados[[cliente.id, 'whatsapp']]

    clasificado = Cartera::IndicativoTelefonico.clasificar_telefono(cliente.telefono, cliente.sucursal)
    clasificado&.dig(:tipo) == :celular
  end

  def email_disponible?(cliente, regla)
    return false if regla.plantilla_email_id.blank?
    return false if canales_bloqueados[[cliente.id, 'email']]

    cliente.email.present?
  end

  def canales_bloqueados
    @canales_bloqueados ||= campana.account.cartera_canales_bloqueados.pluck(:cliente_id, :canal).index_with { true }
  end

  def costo_estimado(regla)
    categoria = categoria_de(regla.plantilla_whatsapp_content_sid)
    return 0.0 if categoria.blank?

    (tarifas[categoria] || 0.0).to_f
  end

  def categoria_de(content_sid)
    return nil if content_sid.blank?

    plantillas_whatsapp_por_sid[content_sid]
  end

  def plantillas_whatsapp_por_sid
    @plantillas_whatsapp_por_sid ||= templates_whatsapp.index_by { |t| t['content_sid'] }.transform_values { |t| t['category'] }
  end

  def templates_whatsapp
    canal_whatsapp&.content_templates&.dig('templates') || []
  end

  def canal_whatsapp
    @canal_whatsapp ||= Channel::TwilioSms.whatsapp_for_account(campana.account_id)
  end

  def tarifas
    @tarifas ||= campana.account.cartera_tarifas_mensajeria.pluck(:categoria, :costo).to_h
  end

  def tarifas_actualizadas_at
    campana.account.cartera_tarifas_mensajeria.maximum(:actualizado_at)
  end

  # Solo informa - no bloquea. El techo duro de frecuencia (un contacto al
  # dia, un canal por semana) lo aplica la corrida real (tarea 5).
  def advertencia_frecuencia
    dias = Array(campana.dias_envio)
    return nil if dias.size <= 1

    nombres = dias.sort.map { |d| I18n.t('date.day_names')[d] }
    "Esta configuracion contacta hasta #{dias.size} veces por semana (#{nombres.join(', ')})."
  end

  def regla_resumen(regla, acumulado)
    {
      regla_id: regla.id,
      orden: regla.orden,
      accion: regla.accion,
      cantidad_clientes: acumulado[:cantidad_clientes],
      cantidad_excluidos: acumulado[:cantidad_excluidos],
      por_canal: acumulado[:por_canal],
      plantilla_whatsapp_lista: plantilla_whatsapp_lista?(regla),
      plantilla_email_lista: regla.plantilla_email_id.present?,
      costo_estimado: acumulado[:costo_estimado].round(2)
    }
  end

  def plantilla_whatsapp_lista?(regla)
    return false if regla.plantilla_whatsapp_content_sid.blank?

    template = templates_whatsapp.find { |t| t['content_sid'] == regla.plantilla_whatsapp_content_sid }
    template&.dig('status') == 'approved'
  end

  def regla_vacia
    { cantidad_clientes: 0, cantidad_excluidos: 0, por_canal: Hash.new(0), costo_estimado: 0.0 }
  end

  def resumen_vacio
    {
      total_casos_evaluados: 0, total_excluidos_no_cobrar: 0, total_excluidos_manual: 0,
      total_sin_regla: 0, total_a_enviar: 0, costo_total_estimado: 0.0
    }
  end
end
