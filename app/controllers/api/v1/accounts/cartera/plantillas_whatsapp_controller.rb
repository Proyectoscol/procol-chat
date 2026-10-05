class Api::V1::Accounts::Cartera::PlantillasWhatsappController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  rescue_from Cartera::Plantillas::WhatsappSubmissionService::Error, with: :render_submission_error

  before_action :ensure_administrator, only: [:create, :solicitar_aprobacion]

  def index
    render json: Current.account.cartera_plantillas_whatsapp.order(created_at: :desc).map { |p| plantilla_json(p) }
  end

  def create
    plantilla = Current.account.cartera_plantillas_whatsapp.new(plantilla_params)
    plantilla.save!
    render json: plantilla_json(plantilla), status: :created
  end

  def solicitar_aprobacion
    plantilla = Current.account.cartera_plantillas_whatsapp.find(params[:id])
    Cartera::Plantillas::WhatsappSubmissionService.new(plantilla: plantilla).call
    render json: plantilla_json(plantilla)
  end

  private

  # Crear una plantilla o someterla a aprobacion de Meta tiene costo y
  # reputacion en juego - mismo guardado que Cartera::SyncsController#create.
  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  def plantilla_params
    params.require(:plantilla).permit(:nombre, :categoria, :tipo, :idioma, :cuerpo, variables: {})
  end

  def plantilla_json(plantilla)
    plantilla.as_json(only: %i[id nombre categoria tipo idioma cuerpo variables content_sid estado created_at])
             .merge(estado_twilio: estado_twilio_de(plantilla))
  end

  # El estado real de aprobacion ante Meta nunca se duplica en la tabla local -
  # se lee en vivo del espejo que mantiene Twilio::TemplateSyncService.
  def estado_twilio_de(plantilla)
    return nil if plantilla.content_sid.blank?

    canal_whatsapp&.content_templates&.dig('templates')&.find { |t| t['content_sid'] == plantilla.content_sid }&.dig('status')
  end

  def canal_whatsapp
    @canal_whatsapp ||= Channel::TwilioSms.whatsapp_for_account(Current.account.id)
  end

  def render_submission_error(exception)
    render_could_not_create_error(exception.message)
  end
end
