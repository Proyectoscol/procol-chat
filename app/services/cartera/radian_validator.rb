# Clasifica una factura segun sus eventos RADIAN (Decreto 1154 de 2020).
# Pura y deterministica. Ayuda operativa, no concepto juridico: cada
# resultado trae sus supuestos, y el llamador debe mostrar el aviso
# "Validar con abogado".
module Cartera::RadianValidator
  DIAS_HABILES_PLAZO_RECLAMO = 3

  module_function

  def clasificar_factura(eventos, fecha_referencia)
    return sin_eventos if eventos.empty?
    return en_reclamo if buscar_evento(eventos, :evento_031)

    evento_030 = buscar_evento(eventos, :evento_030)
    return incompleta('030 - acuse de recibo') unless evento_030

    evento_032 = buscar_evento(eventos, :evento_032)
    return incompleta('032 - recibo del bien o servicio') unless evento_032

    return { estado: :ejecutable, supuestos: ['Aceptación expresa (evento 033).'] } if buscar_evento(eventos, :evento_033)

    clasificar_por_plazo_de_reclamo(evento_032, fecha_referencia)
  end

  def buscar_evento(eventos, tipo)
    eventos.find { |evento| evento[:tipo_evento].to_sym == tipo }
  end
  private_class_method :buscar_evento

  def sin_eventos
    { estado: :no_verificable, supuestos: ['No hay ningún evento RADIAN registrado para esta factura.'] }
  end
  private_class_method :sin_eventos

  def en_reclamo
    { estado: :en_reclamo,
      supuestos: ['El deudor radicó un reclamo (evento 031), lo que bloquea la ejecutabilidad del título mientras no se resuelva.'] }
  end
  private_class_method :en_reclamo

  def incompleta(evento_faltante)
    { estado: :incompleta, evento_faltante: evento_faltante, supuestos: [] }
  end
  private_class_method :incompleta

  def clasificar_por_plazo_de_reclamo(evento_032, fecha_referencia)
    fecha_limite_reclamo = Cartera::BusinessDays.sumar_dias_habiles(evento_032[:fecha], DIAS_HABILES_PLAZO_RECLAMO)

    if fecha_referencia.to_date >= fecha_limite_reclamo
      return {
        estado: :ejecutable,
        supuestos: ["Aceptación tácita: no se registró reclamo (031) dentro de los #{DIAS_HABILES_PLAZO_RECLAMO} días hábiles " \
                    "siguientes al recibo del bien o servicio (art. 773 C.Co), vencidos el #{fecha_limite_reclamo.iso8601}."]
      }
    end

    {
      estado: :incompleta,
      evento_faltante: "aceptación (expresa o tácita) - aún dentro del plazo de reclamo, vence el #{fecha_limite_reclamo.iso8601}",
      supuestos: []
    }
  end
  private_class_method :clasificar_por_plazo_de_reclamo
end
