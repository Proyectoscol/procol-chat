# Arranca manualmente un Calendario::WelcomeBotFlow para esta conversacion,
# elegido por el agente (no por palabra clave) -- pensado para conversaciones
# que llegaron como historico importado (solo notas privadas) y nunca
# dispararon el bot de verdad. Tiene exactamente las mismas consecuencias que
# un arranque normal: primer paso real por WhatsApp, recordatorios si no
# responde, entrega a un humano al terminar.
class Api::V1::Accounts::Conversations::WelcomeBotTriggersController < Api::V1::Accounts::Conversations::BaseController
  def create
    flow = Current.account.calendario_welcome_bot_flows.active.find(params[:welcome_bot_flow_id])
    return render_error(wrong_inbox_message) if flow.inbox_id != @conversation.inbox_id
    return render_error(already_active_message) if active_session?
    return render_error(no_phone_message) if @conversation.contact.phone_number.blank?

    Calendario::WelcomeBotFlowRunner.new(conversation: @conversation, flow: flow).perform
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error(flow_not_found_message)
  end

  private

  def active_session?
    Calendario::BotSession.active.exists?(conversation: @conversation)
  end

  def wrong_inbox_message
    I18n.t('calendario.welcome_bot_trigger.wrong_inbox', default: 'This flow does not belong to this inbox')
  end

  def already_active_message
    I18n.t('calendario.welcome_bot_trigger.already_active', default: 'This conversation already has an active bot session')
  end

  def no_phone_message
    I18n.t('calendario.welcome_bot_trigger.no_phone', default: 'This contact has no phone number')
  end

  def flow_not_found_message
    I18n.t('calendario.welcome_bot_trigger.flow_not_found', default: 'Flow not found')
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
