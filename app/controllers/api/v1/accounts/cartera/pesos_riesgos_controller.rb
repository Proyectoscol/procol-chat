# Pesos del algoritmo de puntaje de riesgo unificado (Cartera::
# PuntajeRiesgoService) - recurso singular, una fila por cuenta. show
# siempre devuelve 7 valores (los guardados, o los defaults de columna si
# la cuenta aun no ha guardado ninguno - ver Cartera::PesoRiesgo.para).
class Api::V1::Accounts::Cartera::PesosRiesgosController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  before_action :ensure_administrator, only: [:update]

  def show
    render json: pesos_json(Cartera::PesoRiesgo.para(Current.account))
  end

  def update
    pesos = Current.account.cartera_peso_riesgo || Current.account.build_cartera_peso_riesgo
    pesos.assign_attributes(pesos_params)
    return render_could_not_create_error(pesos.errors.full_messages.join(', ')) unless pesos.save

    # Los pesos alimentan el puntaje de cada cliente - cambiarlos sin
    # recalcular dejaria la UI mostrando un puntaje calculado con los pesos
    # viejos hasta el proximo sync.
    Cartera::PriorizacionService.new(Current.account).recalcular
    render json: pesos_json(pesos)
  end

  private

  def pesos_params
    params.require(:pesos).permit(*Cartera::PesoRiesgo::FACTORES)
  end

  def pesos_json(pesos)
    Cartera::PesoRiesgo::FACTORES.index_with { |factor| pesos.public_send(factor).to_f }
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
