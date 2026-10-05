# KPIs de una campana para comparar campana contra campana: cuantos
# mensajes reales se enviaron, a cuantos clientes, cuantos fallaron (y por
# que), cuantos contestaron, cuantas notas nuevas escribio el Agente IA
# desde que la campana arranco, y cuantos se escalaron a un humano.
#
# Todo se agrega sobre datos que ya existen (cartera_envios, Message,
# ReportingEvent, Note) - no hay calculo nuevo, solo lectura. Deliberadamente
# excluye envios de prueba (modo_prueba: true, ver PruebaService): las
# estadisticas de una campana deben reflejar su efecto real, no las pruebas
# que el administrador corrio mientras la ajustaba.
class Cartera::Campanas::EstadisticasService
  pattr_initialize [:campana!]

  def call
    {
      campana_id: campana.id,
      activada_en: campana.activada_en,
      semanas_activa: semanas_activa,
      mensajes_enviados: envios_enviados.count,
      clientes_alcanzados: envios_enviados.distinct.count(:cliente_id),
      errores: errores,
      total_errores: errores.size,
      conversaciones_contestadas: conversaciones_contestadas_count,
      interacciones_ia_nuevas: interacciones_ia_nuevas_count,
      escalamientos: escalamientos_count
    }
  end

  private

  def envios_reales
    campana.envios.where(modo_prueba: false)
  end

  def envios_enviados
    envios_reales.where(estado: 'enviado')
  end

  def semanas_activa
    return nil if campana.activada_en.nil?

    ((Time.current - campana.activada_en) / 1.week).floor
  end

  def errores
    envios_reales.where(estado: 'fallido').includes(:cliente, :message).map do |envio|
      {
        envio_id: envio.id,
        cliente_id: envio.cliente_id,
        nombre_cliente: envio.cliente&.nombre,
        canal: envio.canal,
        error: envio.message&.external_error
      }
    end
  end

  # reorder(nil): Message tiene default_scope { order(created_at: :asc) },
  # que Postgres rechaza combinado con SELECT DISTINCT si la columna de
  # orden no esta en la lista de columnas seleccionadas.
  def conversaciones_de_envios
    @conversaciones_de_envios ||= Message.where(id: envios_enviados.select(:message_id))
                                         .reorder(nil).distinct.pluck(:conversation_id)
  end

  def conversaciones_contestadas_count
    return 0 if conversaciones_de_envios.empty?

    Conversation.where(id: conversaciones_de_envios)
                .joins(:messages).where(messages: { message_type: :incoming })
                .reorder(nil).distinct.count('conversations.id')
  end

  # Notas nuevas en los contactos de clientes que esta campana alcanzo,
  # desde que la campana arranco - el Agente IA ya las escribe solo al
  # resolver una conversacion (Captain::Llm::ContactNotesService).
  def interacciones_ia_nuevas_count
    return 0 if campana.activada_en.nil?

    contact_ids = Cartera::Cliente.where(id: envios_enviados.distinct.select(:cliente_id)).joins(:contact).pluck('contacts.id')
    return 0 if contact_ids.empty?

    Note.where(account_id: campana.account_id, contact_id: contact_ids).where(created_at: campana.activada_en..).count
  end

  def escalamientos_count
    return 0 if conversaciones_de_envios.empty?

    ReportingEvent.where(name: 'conversation_bot_handoff', conversation_id: conversaciones_de_envios).distinct.count(:conversation_id)
  end
end
