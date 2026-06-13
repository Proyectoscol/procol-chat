# GET /api/v1/accounts/:account_id/sip/recent_calls
# Últimas 20 llamadas Asterisk del account para el panel de Recientes.
# Auth: sesión de asesor (heredada de BaseController).
class Api::V1::Accounts::Sip::RecentCallsController < Api::V1::Accounts::BaseController
  def index
    calls = Call
            .where(account_id: Current.account.id, provider: :asterisk)
            .includes(:contact)
            .order(created_at: :desc)
            .limit(20)

    render json: calls.map { |c| serialize_call(c) }
  end

  private

  def serialize_call(call)
    {
      id:              call.id,
      createdAt:       call.created_at,
      direction:       frontend_direction(call),
      status:          call.status,
      durationSeconds: call.duration_seconds.to_i,
      name:            call.contact&.name,
      phoneNumber:     call.contact&.phone_number,
      conversationId:  call.conversation_id
    }
  end

  # incoming + completed → 'incoming', incoming + no_answer → 'missed', outgoing → 'outgoing'
  def frontend_direction(call)
    return 'outgoing' if call.outgoing?
    return 'missed' if call.status == 'no_answer'

    'incoming'
  end
end
