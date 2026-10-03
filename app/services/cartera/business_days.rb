# Dias habiles colombianos (lunes a viernes, sin festivos nacionales).
# Implementado a mano, sin dependencia externa. Cubre 2010-2030 (el
# algoritmo es valido para cualquier anio gregoriano - este rango es solo
# el limite del cache). Fuente de las reglas: Ley 51 de 1983 ("Ley
# Emiliani") + festivos moviles basados en el Domingo de Pascua (algoritmo
# de Meeus/Jones/Butcher).
module Cartera::BusinessDays
  ANIO_MIN = 2010
  ANIO_MAX = 2030

  module_function

  def festivo?(fecha)
    cache_festivos.include?(fecha.to_date)
  end

  def dia_habil?(fecha)
    date = fecha.to_date
    return false if [0, 6].include?(date.wday)

    !festivo?(date)
  end

  # Avanza `dias` dias habiles desde `fecha_inicio` (sin contar el dia de
  # inicio). Usado para el plazo de reclamo del art. 773 C.Co (3 dias habiles).
  def sumar_dias_habiles(fecha_inicio, dias)
    resultado = fecha_inicio.to_date
    restantes = dias
    while restantes.positive?
      resultado += 1
      restantes -= 1 if dia_habil?(resultado)
    end
    resultado
  end

  # Dias habiles estrictos entre `desde` (exclusive) y `hasta` (inclusive) -
  # fines de semana y festivos colombianos no cuentan. Negativo si `hasta`
  # es anterior a `desde` (pago adelantado).
  def dias_habiles_entre(desde_original, hasta_original)
    desde = desde_original.to_date
    hasta = hasta_original.to_date
    return 0 if hasta == desde

    adelante = hasta > desde
    cursor = desde
    dias = 0
    until cursor == hasta
      cursor += (adelante ? 1 : -1)
      dias += (adelante ? 1 : -1) if dia_habil?(cursor)
    end
    dias
  end

  def cache_festivos
    @cache_festivos ||= (ANIO_MIN..ANIO_MAX).flat_map { |anio| festivos_del_anio(anio) }.to_set
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- lista fija de festivos colombianos (Ley 51/1983), no se presta a descomponer sin perder la vista de conjunto
  def festivos_del_anio(anio)
    pascua = domingo_de_pascua(anio)

    fijos_sin_traslado = [
      Date.new(anio, 1, 1),  # Ano Nuevo
      Date.new(anio, 5, 1),  # Dia del Trabajo
      Date.new(anio, 7, 20), # Independencia
      Date.new(anio, 8, 7),  # Batalla de Boyaca
      Date.new(anio, 12, 8), # Inmaculada Concepcion
      Date.new(anio, 12, 25) # Navidad
    ]

    fijos_con_traslado = [
      Date.new(anio, 1, 6),   # Reyes Magos
      Date.new(anio, 3, 19),  # San Jose
      Date.new(anio, 6, 29),  # San Pedro y San Pablo
      Date.new(anio, 8, 15),  # Asuncion de la Virgen
      Date.new(anio, 10, 12), # Dia de la Raza
      Date.new(anio, 11, 1),  # Todos los Santos
      Date.new(anio, 11, 11)  # Independencia de Cartagena
    ].map { |fecha| trasladar_a_lunes(fecha) }

    moviles_sin_traslado = [pascua - 3, pascua - 2] # Jueves y Viernes Santo

    moviles_con_traslado = [pascua + 39, pascua + 60, pascua + 68] # Ascension, Corpus Christi, Sagrado Corazon
                           .map { |fecha| trasladar_a_lunes(fecha) }

    fijos_sin_traslado + fijos_con_traslado + moviles_sin_traslado + moviles_con_traslado
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def trasladar_a_lunes(fecha)
    fecha += 1 until fecha.wday == 1
    fecha
  end

  # Algoritmo de Meeus/Jones/Butcher para el Domingo de Pascua (calendario gregoriano).
  # rubocop:disable Metrics/AbcSize -- formula publicada; dividirla en pasos perderia la correspondencia con la referencia
  def domingo_de_pascua(anio)
    a = anio % 19
    b = anio / 100
    c = anio % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = ((19 * a) + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + (2 * e) + (2 * i) - h - k) % 7
    m = (a + (11 * h) + (22 * l)) / 451
    numero = h + l - (7 * m) + 114
    mes = numero / 31
    dia = (numero % 31) + 1
    Date.new(anio, mes, dia)
  end
  # rubocop:enable Metrics/AbcSize
end
