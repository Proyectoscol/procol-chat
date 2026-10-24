# Logica de scoping por fecha/bandeja/exclusion de multi-asesor/asesor-o-
# equipo compartida entre los dos builders de Sentimiento (tendencia y
# drilldown de conversaciones) -- estaba duplicada caracter por caracter
# antes de esta extraccion, mismo patron ya usado para el bucketing
# compartido (ver AuditoriaTimeBucketing). Solo el filtro de sentiment en
# si difiere entre los dos (la tendencia siempre trae los 3, el drilldown
# puede acotar a uno via params[:sentiment]) -- cada builder define su
# propio #sentiment_filter.
module V2::Reports::Concerns::AuditoriaSentimentScoping
  extend ActiveSupport::Concern

  private

  # Relation (no array) a proposito: sin filtro de asesor/equipo, esto se
  # usa directo como subquery (ej. `where(conversation_id: base_conversation_ids)`)
  # en vez de traer a Ruby los ids de TODAS las conversaciones del rango
  # (puede ser decenas de miles en un rango largo) solo para reinyectarlos
  # en otro IN inmediatamente despues.
  def base_conversation_ids
    @base_conversation_ids ||= begin
      scope = Auditoria::ConversationAnalysis
              .where(account_id: account.id, sentiment: sentiment_filter)
              .joins(:conversation)
              .where(conversations: { created_at: timestamp_range })
              .where.not(conversation_id: excluded_conversation_ids)
      scope = scope.where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
      scope.select(:conversation_id)
    end
  end

  # Sin filtro de asesor/equipo, se usa la relation de base_conversation_ids
  # directo (subquery, sin pluck). La interseccion con
  # advisor_scoped_conversation_ids SI necesita traer ids a Ruby porque el
  # asesor no es una columna consultable en SQL (vive en el jsonb de
  # mensajes, resuelto en #advisor_user_id_by_conversation_id).
  def filtered_conversation_ids
    @filtered_conversation_ids ||= advisor_scoped? ? advisor_scoped_conversation_ids : base_conversation_ids
  end

  def timestamp_range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def advisor_scoped?
    user_id.present? || team_id.present?
  end

  def advisor_scoped_conversation_ids
    advisor_user_id_by_conversation_id.select { |_conversation_id, advisor_id| target_user_ids.include?(advisor_id) }.keys
  end

  # user_id tiene prioridad sobre team_id cuando ambos llegan (ej. la UI
  # deja seleccionados los dos selects a la vez) -- ver
  # AuditoriaSentimentReportsIndex.vue, donde ambos selects se desactivan
  # mutuamente para que esto nunca sea ambiguo para quien usa el reporte.
  def target_user_ids
    @target_user_ids ||= user_id.present? ? [user_id.to_i] : TeamMember.where(team_id: account.teams.where(id: team_id)).pluck(:user_id)
  end

  # Para una conversacion SIN el label de multi-asesor (ya excluidas en
  # base_conversation_ids), cualquier mensaje con auditoria_source_user_id
  # da el asesor de todo el caso -- son todos iguales por definicion (ver
  # Auditoria::MessageAnnotatorService#flag_multiple_advisors).
  def advisor_user_id_by_conversation_id
    source_column = Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES
    @advisor_user_id_by_conversation_id ||= account.messages
                                                   .where(conversation_id: base_conversation_ids)
                                                   .where("#{source_column}->>'auditoria_source_user_id' IS NOT NULL")
                                                   .pluck(:conversation_id, Arel.sql("#{source_column}->>'auditoria_source_user_id'"))
                                                   .to_h.transform_values(&:to_i)
  end

  def user_id
    params[:user_id]
  end

  def team_id
    params[:team_id]
  end

  def inbox_id
    params[:inbox_id]
  end
end
