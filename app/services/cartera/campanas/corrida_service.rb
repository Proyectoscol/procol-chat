# Evalua la campana activa de una cuenta contra cada uno de sus casos y
# escribe en cartera_envios lo que el motor decidiria hacer - compuertas 1
# a 9 del diseno aprobado (la 9, de IA, solo corre para casos con
# interaccion reciente). Deliberadamente NO envia nada: cada caso que pasa
# todas las compuertas queda en estado "programado", a la espera del envio
# real (ver Cartera::Campanas::EnviarWhatsappJob).
#
# Instancia nueva por cuenta (ver Cartera::Campanas::CorridaJob) - la
# memoizacion de plantillas de WhatsApp es segura porque no cruza cuentas.
class Cartera::Campanas::CorridaService
  pattr_initialize [:account!]

  def call
    campana = account.cartera_campanas.find_by(estado: 'activa')
    return resultado(0, 0) if campana.nil?
    return resultado(0, 0) unless campana.dias_envio.include?(Time.current.wday)
    return resultado(0, 0) unless dentro_de_ventana_de_la_campana?(campana)

    evaluados = 0
    programados = 0
    account.cartera_casos.includes(:cliente).find_each do |caso|
      evaluados += 1
      programados += 1 if evaluar_caso(campana, caso)
    end
    resultado(evaluados, programados)
  end

  private

  def resultado(evaluados, programados)
    { casos_evaluados: evaluados, casos_programados: programados }
  end

  # La ventana legal del dia (Ley 2300) Y la ventana propia de la campana
  # (subconjunto de la legal, ya validado en el modelo) deben cumplirse
  # ambas en el momento exacto en que corre el job.
  def dentro_de_ventana_de_la_campana?(campana)
    ahora = Time.current
    return false unless Cartera::Campanas::LeyCobranza.dentro_de_ventana_legal?(ahora)

    segundos = ahora.seconds_since_midnight
    segundos.between?(campana.hora_inicio.seconds_since_midnight, campana.hora_fin.seconds_since_midnight)
  end

  # Compuertas 4-8. Devuelve true si el caso quedo "programado".
  def evaluar_caso(campana, caso)
    return false if ya_contactado_hoy?(caso)

    regla = resolver_regla_aplicable(campana, caso)
    return false if regla.nil?

    canal = resolver_canal(caso, regla)
    if canal.nil?
      registrar_omision(campana, caso, 'omitido_canal_bloqueado', 'sin canal disponible (bloqueado o no clasificable)', regla)
      return false
    end

    verificar_plantilla_lista!(campana, regla, canal)

    decision = decidir_envio(caso, regla, canal)
    if decision && !decision[:enviar]
      registrar_omision(campana, caso, 'omitido_ia', decision[:razon], regla)
      return false
    end

    crear_programado(campana, caso, regla, canal)
    true
  end

  # Compuerta 9: solo para casos con una nota de contacto de los ultimos 7
  # dias - para todos los demas, nil (nada que decidir, se envia directo).
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

  # Compuertas 4-6: no_cobrar, exclusion manual y match de reglas. Devuelve
  # la regla aplicable (accion "enviar"), o nil habiendo ya registrado la
  # omision correspondiente.
  def resolver_regla_aplicable(campana, caso)
    motivo = motivo_omision_regla(caso)
    if motivo
      registrar_omision(campana, caso, 'omitido_regla', motivo)
      return nil
    end

    regla = Cartera::Campanas::ReglaMatcher.primera_coincidencia(campana.reglas, caso)
    if regla.nil?
      registrar_omision(campana, caso, 'omitido_regla', 'ninguna regla aplica a este caso')
      return nil
    end
    if regla.accion == 'excluir'
      registrar_omision(campana, caso, 'omitido_regla', "la regla #{regla.orden} excluye este caso", regla)
      return nil
    end

    regla
  end

  def motivo_omision_regla(caso)
    return 'no_cobrar' if caso.no_cobrar
    return "excluido manualmente hasta #{caso.excluido_hasta.to_date}" if caso.excluido_hasta.present? && caso.excluido_hasta.future?

    nil
  end

  # El job corre cada 30 minutos (ver config/schedule.yml): esto evita
  # re-evaluar (y duplicar en la bitacora) un caso ya procesado hoy, sea
  # cual sea el resultado - no solo cuando se llego a enviar/programar.
  # modo_prueba: false - un envio de Cartera::Campanas::PruebaService (quien
  # pueda correr varias veces el mismo dia mientras se ajusta una campana)
  # nunca debe bloquear el envio real de ese mismo dia.
  def ya_contactado_hoy?(caso)
    account.cartera_envios.exists?(cliente_id: caso.cliente_id, created_at: Time.current.all_day, modo_prueba: false)
  end

  # Si ya se eligio un canal esta semana, se respeta ese mismo canal
  # (nunca varios canales en la misma semana, Ley 2300 art. 3). Si ese
  # canal ya no esta disponible (se bloqueo a mitad de semana), se
  # resuelve de nuevo - no se espera a la semana siguiente para corregir.
  # A diferencia de ya_contactado_hoy?, aqui si importa el estado: solo un
  # envio realmente programado/enviado cuenta como "canal usado".
  def resolver_canal(caso, regla)
    canal_de_la_semana = envios_del_cliente(caso).where(created_at: Time.current.beginning_of_week..).order(:created_at).pick(:canal)
    return canal_de_la_semana if canal_de_la_semana.present? && canal_disponible?(caso, regla, canal_de_la_semana)

    return 'whatsapp' if canal_disponible?(caso, regla, 'whatsapp')
    return 'email' if canal_disponible?(caso, regla, 'email')

    nil
  end

  # modo_prueba: false - ver ya_contactado_hoy?, misma razon: un envio de
  # prueba no debe contar como "el canal ya usado esta semana" para la
  # corrida real.
  def envios_del_cliente(caso)
    account.cartera_envios.where(cliente_id: caso.cliente_id, estado: %w[programado enviado], modo_prueba: false)
  end

  def canal_disponible?(caso, regla, canal)
    case canal
    when 'whatsapp' then whatsapp_disponible?(caso, regla)
    when 'email' then email_disponible?(caso, regla)
    else false
    end
  end

  def whatsapp_disponible?(caso, regla)
    return false if regla.plantilla_whatsapp_content_sid.blank?
    return false if bloqueado?(caso, 'whatsapp')

    Cartera::IndicativoTelefonico.clasificar_telefono(caso.cliente.telefono, caso.cliente.sucursal)&.dig(:tipo) == :celular
  end

  def email_disponible?(caso, regla)
    return false if regla.plantilla_email_id.blank?
    return false if bloqueado?(caso, 'email')

    caso.cliente.email.present?
  end

  def bloqueado?(caso, canal)
    account.cartera_canales_bloqueados.exists?(cliente_id: caso.cliente_id, canal: canal)
  end

  # Una plantilla de WhatsApp sin aprobar en una regla que SI se esta
  # usando es un error de configuracion, no una decision de negocio por
  # caso - debe detener esta cuenta (el rescue vive en CorridaJob), no
  # saltarse el caso en silencio.
  def verificar_plantilla_lista!(campana, regla, canal)
    return unless canal == 'whatsapp'
    return if plantilla_whatsapp_aprobada?(campana, regla.plantilla_whatsapp_content_sid)

    raise "La plantilla de WhatsApp de la regla #{regla.id} (orden #{regla.orden}, " \
          "content_sid=#{regla.plantilla_whatsapp_content_sid}) no esta aprobada."
  end

  def plantilla_whatsapp_aprobada?(campana, content_sid)
    templates_whatsapp(campana).find { |t| t['content_sid'] == content_sid }&.dig('status') == 'approved'
  end

  def templates_whatsapp(campana)
    @templates_whatsapp ||= Channel::TwilioSms.whatsapp_for_account(campana.account_id)&.content_templates&.dig('templates') || []
  end

  def crear_programado(campana, caso, regla, canal)
    account.cartera_envios.create!(
      campana: campana, campana_regla: regla, cliente_id: caso.cliente_id,
      factura_ids: facturas_abiertas_de(caso), saldo_al_enviar: caso.saldo_abierto,
      tramo_al_enviar: caso.tramo, dias_vencido_max_al_enviar: caso.dias_vencido_max,
      canal: canal, estado: 'programado',
      categoria_plantilla: canal == 'whatsapp' ? categoria_de(campana, regla.plantilla_whatsapp_content_sid) : nil
    )
  end

  def facturas_abiertas_de(caso)
    caso.cliente.facturas.where('saldo_pendiente > 0').pluck(:id)
  end

  def categoria_de(campana, content_sid)
    templates_whatsapp(campana).find { |t| t['content_sid'] == content_sid }&.dig('category')
  end

  def registrar_omision(campana, caso, estado, razon, regla = nil)
    account.cartera_envios.create!(
      campana: campana, campana_regla: regla, cliente_id: caso.cliente_id,
      factura_ids: facturas_abiertas_de(caso), saldo_al_enviar: caso.saldo_abierto,
      tramo_al_enviar: caso.tramo, dias_vencido_max_al_enviar: caso.dias_vencido_max,
      estado: estado, razon_omision: razon
    )
    true
  end
end
