# Cliente HTTP minimo compartido por todos los metodos de AlegraConnector -
# paginacion y reintento ante rate-limit viven en un solo lugar.
class Cartera::Alegra::ApiClient
  include HTTParty

  base_uri 'https://api.alegra.com/api/v1'

  TAMANO_PAGINA = 30
  # 150 req/min por usuario (developer.alegra.com/reference/limite-de-request).
  # Un 429 trae X-Rate-Limit-Reset con los segundos restantes del periodo.
  RATE_LIMIT_MAX_REINTENTOS = 3

  def initialize(email:, token:)
    @basic_auth = { username: email, password: token }
  end

  def paginar(path, query = {})
    items = []
    start = 0

    loop do
      response = fetch_con_reintento(path, query.merge(start: start, limit: TAMANO_PAGINA))
      raise "Cartera::Alegra::ApiClient: #{path} respondio #{response.code}" unless response.success?

      pagina = response.parsed_response
      raise "Cartera::Alegra::ApiClient: la respuesta de #{path} no es un arreglo." unless pagina.is_a?(Array)

      items.concat(pagina)
      break if pagina.length < TAMANO_PAGINA

      start += TAMANO_PAGINA
    end

    items
  end

  private

  def fetch_con_reintento(path, query)
    intento = 0

    loop do
      response = self.class.get(path, query: query, basic_auth: @basic_auth, headers: { 'Accept' => 'application/json' })
      return response if response.code != 429 || intento >= RATE_LIMIT_MAX_REINTENTOS

      espera_segundos = (response.headers['X-Rate-Limit-Reset'] || '60').to_i
      sleep(espera_segundos)
      intento += 1
    end
  end
end
