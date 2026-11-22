class Api::V1::Accounts::Calendario::MessageTemplatesController < Api::V1::Accounts::BaseController
  wrap_parameters :message_template, include: %i[key label body quick_replies notes]

  before_action :check_authorization
  before_action :fetch_template, only: [:update, :destroy, :activate]

  def index
    templates = Current.account.calendario_message_templates.ordered
    render json: templates.map { |template| serialize(template) }
  end

  def create
    template = Current.account.calendario_message_templates.create!(
      template_params.merge(
        version: Calendario::MessageTemplate.next_version_for(Current.account, template_params[:key]),
        status: first_version_for_key?(template_params[:key]) ? 'active' : 'draft'
      )
    )
    render json: serialize(template)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # Solo se puede editar una version en borrador -- una vez activa, el
  # historial no debe mutar; para corregirla hay que crear una version nueva
  # (ver create) y activarla.
  def update
    unless @template.status == 'draft'
      return render json: { error: 'No se puede editar una versión activa, crea una nueva.' },
                    status: :unprocessable_entity
    end

    @template.update!(template_params.except(:key))
    render json: serialize(@template)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    return render json: { error: 'No se puede borrar una versión activa.' }, status: :unprocessable_entity unless @template.status == 'draft'

    @template.destroy!
    head :no_content
  end

  def activate
    @template.activate!
    render json: serialize(@template)
  end

  private

  def first_version_for_key?(key)
    !Current.account.calendario_message_templates.for_key(key).exists?
  end

  def fetch_template
    @template = Current.account.calendario_message_templates.find(params[:id])
  end

  def template_params
    params.require(:message_template).permit(:key, :label, :body, :notes, quick_replies: [])
  end

  def serialize(template)
    {
      id: template.id, key: template.key, label: template.label, version: template.version,
      body: template.body, quick_replies: template.quick_replies, status: template.status,
      notes: template.notes, created_at: template.created_at
    }
  end

  def check_authorization
    authorize(:'calendario/message_templates')
  end
end
