# Fecha en letras ("14 de octubre de 2026") en vez de numerica (14/10/2026)
# en TODO lo que el paciente lee -- pedido explicito del usuario: los
# clientes de este consultorio suelen tener mas de 60 anios, y DD/MM/AAAA se
# presta a confusion (se puede leer como MM/DD) de una forma en que la fecha
# escrita en letras no.
#
# strftime('%B') (no usado aqui) depende del locale global de Rails, que en
# el contexto de un background job casi siempre es :en -- bug real ya
# encontrado y corregido en Calendario::NoShowReplyListener. Esta lista fija
# evita ese problema sin tener que fijar I18n.locale en cada job.
module Calendario::SpanishDateFormatter
  MONTHS = %w[
    enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre
  ].freeze

  module_function

  def long_date(time)
    "#{time.day} de #{MONTHS[time.month - 1]} de #{time.year}"
  end

  def long_date_time(time)
    "#{long_date(time)} a las #{time.strftime('%I:%M %p')}"
  end
end
