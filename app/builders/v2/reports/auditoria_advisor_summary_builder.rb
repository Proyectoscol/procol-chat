# Esta cuenta nunca llena reporting_events -- los mensajes del espejo
# externo son privados a proposito (ver
# Base::SendOnChannelService#invalid_message?) para que jamas se reenvien de
# verdad por el canal, y Chatwoot excluye los privados de ese pipeline (ver
# Message#valid_first_reply?/#update_waiting_since). Este builder calcula
# todo directo de messages/content_attributes en vez del pipeline nativo, y
# excluye las conversaciones marcadas "auditoria-multiple-asesor" (ver
# Auditoria::MessageAnnotatorService) para que ningun asesor se quede con
# metricas infladas o robadas por un numero que en realidad comparte con
# otro.
class V2::Reports::AuditoriaAdvisorSummaryBuilder
  pattr_initialize [:account!, :params!]

  # Buckets del desglose por orden de respuesta: 1-4 explicitos, 5 en
  # adelante se agrupan en un solo bucket para no generar una fila por cada
  # numero en conversaciones muy largas.
  MAX_EXPLICIT_RESPONSE_ORDER = 4
  OVERFLOW_RESPONSE_ORDER_LABEL = '5+'.freeze

  def build
    stats = agent_user_ids.map { |user_id| build_advisor_stats(user_id) }
    # Cuando se filtra por una bandeja puntual, la mayoria de asesores no
    # trabajan ahi -- mostrarlos en "--" es ruido; se quitan del todo y solo
    # quedan quienes de verdad tuvieron actividad en esa bandeja.
    stats = stats.reject { |row| row[:conversations_count].zero? } if inbox_id.present?
    { advisors: stats, totals: totals }
  end

  private

  def build_advisor_stats(user_id)
    samples = filtered_samples(response_samples_by_advisor[user_id])
    {
      id: user_id,
      conversations_count: conversation_ids_by_advisor[user_id]&.size || 0,
      avg_response_time_seconds: average_seconds(samples),
      response_breakdown: response_breakdown(samples)
    }
  end

  # Sobre el mismo scope ya filtrado (fecha/bandeja/multiple-asesor) que las
  # filas por asesor, para que el total/promedio general sea consistente con
  # lo que se ve en la tabla -- nunca una cifra distinta "por fuera".
  def totals
    samples = filtered_samples(response_samples_by_advisor.values.flatten)
    {
      conversations_count: conversation_ids_by_advisor.values.sum(&:size),
      avg_response_time_seconds: average_seconds(samples),
      response_breakdown: response_breakdown(samples)
    }
  end

  # Punto unico de filtro para que el promedio y el desglose por orden nunca
  # queden inconsistentes entre si al prender/apagar el toggle.
  def filtered_samples(samples)
    return samples unless same_day_only?

    samples.select { |sample| sample[:same_day] }
  end

  def same_day_only?
    return @same_day_only if defined?(@same_day_only)

    @same_day_only = ActiveModel::Type::Boolean.new.cast(params[:same_day_only])
  end

  def average_seconds(samples)
    return nil if samples.blank?

    seconds = samples.pluck(:seconds)
    (seconds.sum / seconds.size).round
  end

  # Agrupa por orden de respuesta dentro de la conversacion (1ra, 2da, ...),
  # con 5+ como bucket unico. Un orden sin muestras (por ejemplo, nadie tuvo
  # una 4ta respuesta en el rango, o el toggle "mismo dia" filtro todas las
  # de ese orden) simplemente no aparece -- no se rellena con count: 0.
  def response_breakdown(samples)
    samples.group_by { |sample| response_order_bucket(sample[:order]) }
           .map { |bucket, bucket_samples| { order: bucket, avg_response_time_seconds: average_seconds(bucket_samples), count: bucket_samples.size } }
           .sort_by { |row| row[:order] == OVERFLOW_RESPONSE_ORDER_LABEL ? Float::INFINITY : row[:order] }
  end

  def response_order_bucket(order)
    order > MAX_EXPLICIT_RESPONSE_ORDER ? OVERFLOW_RESPONSE_ORDER_LABEL : order
  end

  # Solo agentes (no administradores) -- igual que el filtro que ya aplica
  # el frontend sobre agents/getAgents, pero aqui ademas evita que un mensaje
  # resuelto por casualidad al nombre de un administrador infle el total.
  def agent_user_ids
    @agent_user_ids ||= account.account_users.where(role: :agent).pluck(:user_id)
  end

  def conversation_ids_by_advisor
    @conversation_ids_by_advisor ||= rows.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |row, acc|
      acc[row[:advisor_id]] << row[:conversation_id] if row[:advisor_id]
    end
  end

  # Recorre cada conversacion en orden y mide el tiempo entre cada mensaje
  # entrante y la siguiente respuesta saliente de un asesor resuelto -- un
  # numero honesto de "cuanto tarda en responder", promediado sobre toda la
  # historia (no solo la primera respuesta, como hace el FRT nativo).
  def response_samples_by_advisor
    return @response_samples_by_advisor if defined?(@response_samples_by_advisor)

    @response_samples_by_advisor = Hash.new { |h, k| h[k] = [] }
    rows.group_by { |row| row[:conversation_id] }.each_value { |rows_in_conversation| collect_samples(rows_in_conversation) }
    @response_samples_by_advisor
  end

  # order es un contador local a esta conversacion (arranca en 0, pasa a 1 en
  # el primer par entrante->saliente que calza, 2 en el segundo, etc) --
  # excluir conversaciones con mas de un asesor (ver excluded_conversation_ids)
  # garantiza que nunca hay ambiguedad sobre a quien le pertenece ese orden.
  def collect_samples(rows_in_conversation)
    prev_type = nil
    prev_created_at = nil
    order = 0
    rows_in_conversation.each do |row|
      if row[:message_type] == 'outgoing' && row[:advisor_id] && prev_type == 'incoming'
        order += 1
        @response_samples_by_advisor[row[:advisor_id]] << {
          seconds: row[:created_at] - prev_created_at,
          order: order,
          same_day: row[:created_at].to_date == prev_created_at.to_date
        }
      end
      prev_type = row[:message_type]
      prev_created_at = row[:created_at]
    end
  end

  # select al final: descarta filas resueltas a un administrador, para que
  # ni las filas por asesor ni totals (ambas construidas sobre rows) se
  # inflen con un mensaje que por coincidencia calzo con el nombre de un
  # administrador.
  def rows
    return @rows if defined?(@rows)

    mapped = scoped_messages.map do |conversation_id, message_type, created_at, advisor_id|
      { conversation_id: conversation_id, message_type: message_type, created_at: created_at, advisor_id: advisor_id&.to_i }
    end
    @rows = mapped.select { |row| row[:advisor_id].nil? || agent_user_ids.include?(row[:advisor_id]) }
  end

  # pluck(:message_type) devuelve el label del enum ("incoming"/"outgoing"),
  # no el entero crudo -- Rails lo castea al leer la columna aunque sea un
  # pluck directo. Lo mismo aplica a created_at: con time_zone_aware_attributes
  # y config.time_zone = 'America/Bogota' (config/application.rb), pluck ya
  # devuelve el valor casteado a esa zona -- el to_date en collect_samples ya
  # refleja el dia calendario de Bogota, sin plomeria extra de timezone.
  # message_type: [:incoming, :outgoing] explicito -- sin esto, un mensaje de
  # otro tipo intercalado (ej. "activity" de asignacion, que se crea
  # automaticamente con cada asignacion/reasignacion/resolucion, o un
  # "template" de csat/greeting/auto-resolve) rompe la adyacencia que
  # collect_samples detecta via prev_type == 'incoming' justo antes del
  # saliente -- la respuesta real del asesor queda totalmente fuera del
  # promedio y del desglose, en vez de solo medirse distinto.
  def scoped_messages
    scope = account.messages.where(created_at: range, message_type: [:incoming, :outgoing])
                   .where.not(conversation_id: excluded_conversation_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.reorder('messages.conversation_id ASC, messages.id ASC')
         .pluck(:conversation_id, :message_type, :created_at,
                Arel.sql("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def inbox_id
    params[:inbox_id]
  end

  def range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end
end
