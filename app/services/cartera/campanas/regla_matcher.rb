# Evalua el arbol de condiciones de una regla de campana contra un caso.
# Mismo shape de arbol (grupo {operator, conditions: [...]} vs hoja
# {attribute_key, filter_operator, values}) que Captain::AudienceMatcher,
# pero sobre los 7 campos de cartera que puede usar una regla.
class Cartera::Campanas::ReglaMatcher
  ATTRIBUTES = %w[tramo dias_vencido_max puntaje_riesgo score_credito saldo_abierto antiguedad_relacion_dias tipo_deudor].freeze
  CASO_ATTRIBUTES = %w[tramo dias_vencido_max puntaje_riesgo score_credito saldo_abierto].freeze

  def initialize(caso, fecha_referencia: Time.current)
    @caso = caso
    @fecha_referencia = fecha_referencia
  end

  # Primera regla (por orden) cuyas condiciones coinciden - nil si ninguna.
  def self.primera_coincidencia(reglas, caso, fecha_referencia: Time.current)
    matcher = new(caso, fecha_referencia: fecha_referencia)
    reglas.find { |regla| matcher.matches?(regla.condiciones) }
  end

  def matches?(node)
    return true if node.blank?

    node = node.with_indifferent_access
    node.key?(:conditions) ? matches_group?(node) : matches_leaf?(node)
  end

  private

  def matches_group?(group)
    conditions = Array(group[:conditions])
    if group[:operator].to_s.casecmp?('or')
      conditions.any? { |child| matches?(child) }
    else
      conditions.all? { |child| matches?(child) }
    end
  end

  def matches_leaf?(leaf)
    actual = attribute_value(leaf[:attribute_key])
    values = Array(leaf[:values])

    case leaf[:filter_operator]
    when 'is_present' then actual.present?
    when 'is_not_present' then actual.blank?
    when 'equal_to' then values.any? { |v| values_equal?(actual, v) }
    when 'not_equal_to' then values.none? { |v| values_equal?(actual, v) }
    else matches_comparison?(leaf[:filter_operator], actual, values.first)
    end
  end

  def matches_comparison?(operator, actual, expected)
    case operator
    when 'is_greater_than' then compare(actual, expected) == 1
    when 'is_less_than' then compare(actual, expected) == -1
    else false
    end
  end

  def attribute_value(key)
    if CASO_ATTRIBUTES.include?(key)
      valor = @caso.public_send(key)
      key == 'saldo_abierto' ? valor&.to_f : valor
    else
      attribute_value_calculado(key)
    end
  end

  def attribute_value_calculado(key)
    case key
    when 'antiguedad_relacion_dias' then antiguedad_relacion_dias
    when 'tipo_deudor' then @caso.cliente.tipo_deudor
    end
  end

  def antiguedad_relacion_dias
    return nil if @caso.fecha_primera_factura.blank?

    (@fecha_referencia.to_date - @caso.fecha_primera_factura.to_date).to_i
  end

  def values_equal?(actual, expected)
    return numeric_equal?(actual, expected) if actual.is_a?(Numeric)

    actual.to_s.casecmp?(expected.to_s)
  end

  def numeric_equal?(actual, expected)
    BigDecimal(actual.to_s) == BigDecimal(expected.to_s)
  rescue ArgumentError, TypeError
    false
  end

  # -1/0/1 como <=>, o nil si no se puede comparar (nunca coincide).
  def compare(actual, expected)
    return nil if actual.blank? || expected.blank?

    BigDecimal(actual.to_s) <=> BigDecimal(expected.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
