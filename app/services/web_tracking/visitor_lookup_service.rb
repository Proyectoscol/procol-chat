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
  # message_text: el primer mensaje real entrante -- sirve para desambiguar
  # cuando hay 2+ clicks al mismo numero en la ventana (ver internal.ts),
  # comparando contra el texto precargado de cada click. Nunca es
  # obligatorio: con 1 solo candidato la atribucion no depende de el (la
  # persona pudo borrar el texto precargado y escribir cualquier cosa).
  def by_recent_click(whatsapp_number:, within_minutes: 2, message_text: nil)
    get('/api/internal/attribution-from-recent-click', phone: digits_only(whatsapp_number), within_minutes: within_minutes,
                                                       message_text: message_text)
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

  # Hallazgo real 2026-11-27: un lookup que NO encuentra nada (404 "not
  # found", candidate_count 0 o 2+) devolvia nil en silencio total -- sin
  # log, sin excepcion -- asi que cuando un caso que a simple vista deberia
  # haber matcheado (click real 34s antes del primer mensaje, mismo numero
  # de inbox) no encontro atribucion, no quedaba ningun rastro de POR QUE
  # para diagnosticarlo despues (la ventana de busqueda de tracking-api es
  # de maximo 30 min, no se puede re-consultar pasado ese tiempo). Ahora
  # cada intento deja log: el resultado exacto (encontrado/candidate_count/
  # no configurado) para poder diagnosticar la PROXIMA vez sin tener que
  # reconstruirlo a mano cruzando contra el panel de tracking.
  def get(path, **query)
    return log_not_configured(path, query) if base_url.blank? || token.blank?

    response = HTTParty.get("#{base_url}#{path}", query: query, headers: { 'X-Internal-Token' => token }, timeout: 5)
    return log_no_match(path, query, response) unless response.success?

    log_match(path, query, response)
  rescue StandardError => e
    Rails.logger.error("[WebTracking] #{path} error -- query=#{query.inspect} #{e.class}: #{e.message}")
    ChatwootExceptionTracker.new(e).capture_exception
    nil
  end

  def log_not_configured(path, query)
    Rails.logger.warn("[WebTracking] #{path} sin configurar (TRACKING_API_BASE/TRACKING_API_INTERNAL_TOKEN) -- query=#{query.inspect}")
    nil
  end

  def log_no_match(path, query, response)
    Rails.logger.info("[WebTracking] #{path} sin match -- query=#{query.inspect} status=#{response.code} body=#{response.body}")
    nil
  end

  def log_match(path, query, response)
    visitor = response.parsed_response['visitor']
    Rails.logger.info("[WebTracking] #{path} match -- query=#{query.inspect} visitor_id=#{visitor&.dig('visitorId')}")
    visitor
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
