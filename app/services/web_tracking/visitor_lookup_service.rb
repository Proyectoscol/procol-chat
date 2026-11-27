# Pregunta a tracking-api (urologyncare.com, servicio separado, otro VPS)
# por la navegacion previa de un visitante -- ver WebTracking::AttributionLookupJob
# para cual metodo se usa primero y por que. Server-to-server, nunca
# navegador: TRACKING_API_INTERNAL_TOKEN es un secreto propio, distinto al
# login de administracion de ese panel.
#
# Sin ENV configurado (instalaciones sin este tracking, o mientras no se
# haya desplegado el lado de tracking-api todavia) ambos metodos no hacen
# nada -- nunca deben romper la creacion de una conversacion real por un
# feature opcional de atribucion.
class WebTracking::VisitorLookupService
  pattr_initialize [{ phone_number: nil }]

  # La ruta REAL: el sitio casi nunca captura telefono (solo en el
  # formulario de agendamiento) -- en cambio, casi todo lead le da click a
  # un boton "whatsapp_cta_click" (el link wa.me trae el numero + mensaje
  # precargado) y luego manda el primer mensaje real segundos/minutos
  # despues. `whatsapp_number` aqui es el numero DEL INBOX (a donde
  # apuntan los CTAs), no el del contacto. Confirmado con datos reales
  # 2026-11-27: en 419 clicks historicos, solo UNA vez dos visitantes
  # distintos clickearon en el mismo minuto -- una ventana corta es
  # segura. tracking-api se niega a adivinar si hay 0 o 2+ candidatos en
  # la ventana (404), este metodo simplemente devuelve nil en ese caso.
  def by_recent_click(whatsapp_number:, within_minutes: 2)
    get('/api/internal/attribution-from-recent-click', phone: digits_only(whatsapp_number), within_minutes: within_minutes)
  end

  # Respaldo: solo encuentra algo si el contacto alguna vez lleno su
  # telefono en el formulario de agendamiento del sitio -- la minoria de
  # los casos, pero no cuesta nada intentarlo si el metodo de arriba no
  # encontro nada.
  def by_phone
    return if normalized_contact_phone.blank?

    get('/api/internal/visitor-by-phone', phone: normalized_contact_phone)
  end

  private

  def get(path, **query)
    return if base_url.blank? || token.blank?

    response = HTTParty.get("#{base_url}#{path}", query: query, headers: { 'X-Internal-Token' => token }, timeout: 5)
    return unless response.success?

    response.parsed_response['visitor']
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    nil
  end

  # Mismo criterio en ambos lados (ver lastTenDigits en tracking-api/src/routes/internal.ts):
  # numeros moviles colombianos son 10 digitos, comparar los ultimos 10
  # absorbe el +57/espacios/guiones/prefijo "whatsapp:" sin necesitar una
  # libreria real de telefonos para un solo lookup.
  def normalized_contact_phone
    digits_only(phone_number)
  end

  def digits_only(raw)
    digits = raw.to_s.gsub(/\D/, '')
    digits.length >= 10 ? digits[-10..] : nil
  end

  def base_url
    ENV.fetch('TRACKING_API_BASE', nil)
  end

  def token
    ENV.fetch('TRACKING_API_INTERNAL_TOKEN', nil)
  end
end
