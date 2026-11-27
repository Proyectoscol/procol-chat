# Pregunta a tracking-api (urologyncare.com/admin, servicio separado, otro
# VPS) si un numero de telefono ya visito el sitio -- ver
# tracking-api/src/routes/internal.ts#GET /api/internal/visitor-by-phone.
# Server-to-server, nunca navegador: TRACKING_API_INTERNAL_TOKEN es un
# secreto propio, distinto al login de administracion de ese panel.
#
# Sin ENV configurado (instalaciones sin este tracking, o mientras no se
# haya desplegado el lado de tracking-api todavia) simplemente no hace
# nada -- nunca debe romper la creacion de una conversacion real por un
# feature opcional de atribucion.
class WebTracking::VisitorLookupService
  pattr_initialize [:phone_number!]

  def perform
    return if base_url.blank? || token.blank? || normalized_phone.blank?

    response = HTTParty.get(
      "#{base_url}/api/internal/visitor-by-phone",
      query: { phone: normalized_phone },
      headers: { 'X-Internal-Token' => token },
      timeout: 5
    )
    return unless response.success?

    response.parsed_response['visitor']
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    nil
  end

  private

  # Mismo criterio que el lado de tracking-api (ver lastTenDigits en
  # internal.ts): numeros moviles colombianos son 10 digitos, comparar los
  # ultimos 10 absorbe el +57/espacios/guiones de cualquiera de los dos
  # lados sin necesitar una libreria real de telefonos para un solo lookup.
  def normalized_phone
    digits = phone_number.to_s.gsub(/\D/, '')
    digits.length >= 10 ? digits[-10..] : nil
  end

  def base_url
    ENV.fetch('TRACKING_API_BASE', nil)
  end

  def token
    ENV.fetch('TRACKING_API_INTERNAL_TOKEN', nil)
  end
end
