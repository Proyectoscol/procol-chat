# Indicativos telefonicos regionales de Colombia, unificados desde 2021
# (Resolucion CRC) - solo 8 codigos cubren los 32 departamentos + Bogota D.C.
module Cartera::IndicativoTelefonico
  INDICATIVO_POR_DEPARTAMENTO_NORMALIZADO = {
    'bogota dc' => '601', 'cundinamarca' => '601',
    'cauca' => '602', 'narino' => '602', 'valle del cauca' => '602',
    'antioquia' => '604', 'cordoba' => '604', 'choco' => '604',
    'atlantico' => '605', 'bolivar' => '605', 'cesar' => '605', 'la guajira' => '605', 'magdalena' => '605', 'sucre' => '605',
    'caldas' => '606', 'quindio' => '606', 'risaralda' => '606',
    'arauca' => '607', 'norte de santander' => '607', 'santander' => '607',
    'amazonas' => '608', 'boyaca' => '608', 'casanare' => '608', 'caqueta' => '608', 'guaviare' => '608',
    'guainia' => '608', 'huila' => '608', 'meta' => '608', 'tolima' => '608', 'putumayo' => '608',
    'san andres y providencia' => '608', 'vaupes' => '608', 'vichada' => '608'
  }.freeze

  module_function

  def indicativo_por_departamento(departamento)
    return nil if departamento.blank?

    INDICATIVO_POR_DEPARTAMENTO_NORMALIZADO[normalizar(departamento)]
  end

  # Sugiere el indicativo regional cuando el telefono es un fijo de 7
  # digitos (sin indicativo) y se conoce el departamento del domicilio.
  # Nunca reemplaza el dato crudo del origen.
  def sugerir_telefono(telefono, departamento)
    clasificado = clasificar_telefono(telefono, departamento)
    return nil unless clasificado && clasificado[:tipo] == :fijo_sin_indicativo

    indicativo = clasificado[:numero_para_llamar][0, 3]
    { indicativo: indicativo, telefono_sugerido: "#{indicativo} #{clasificado[:numero_para_llamar][3..]}" }
  end

  # Formato E.164 (+57 + numero nacional completo) listo para WhatsApp/
  # llamadas - nil cuando no se puede completar con confianza (formato
  # "desconocido": sin eso, se estaria inventando un numero de contacto).
  def formatear_e164(telefono, departamento)
    clasificado = clasificar_telefono(telefono, departamento)
    return nil unless clasificado && clasificado[:tipo] != :desconocido

    "+57#{clasificado[:numero_para_llamar]}"
  end

  # Clasifica un telefono colombiano: celular (10 digitos, empieza en 3) y
  # fijo con indicativo (10 digitos) ya estan completos; un fijo de 7
  # digitos sin indicativo se completa por departamento cuando se conoce.
  def clasificar_telefono(telefono, departamento)
    return nil if telefono.blank?

    digitos = telefono.gsub(/\D/, '')
    return { tipo: :celular, numero_para_llamar: digitos, etiqueta: 'Celular' } if digitos.length == 10 && digitos.start_with?('3')
    return { tipo: :fijo_completo, numero_para_llamar: digitos, etiqueta: "Fijo (#{digitos[0, 3]})" } if digitos.length == 10

    if digitos.length == 7
      indicativo = indicativo_por_departamento(departamento)
      return { tipo: :fijo_sin_indicativo, numero_para_llamar: "#{indicativo}#{digitos}", etiqueta: "Fijo (#{indicativo}, sugerido)" } if indicativo

      return { tipo: :desconocido, numero_para_llamar: digitos, etiqueta: 'Fijo - falta indicativo (departamento desconocido)' }
    end

    { tipo: :desconocido, numero_para_llamar: digitos, etiqueta: 'Formato no reconocido' }
  end

  def normalizar(texto)
    texto.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, '').downcase.gsub(/[.,]/, '').strip
  end
end
