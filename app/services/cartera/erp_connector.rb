# Contrato de solo lectura hacia el sistema contable del cliente. A proposito
# no declara ningun metodo de escritura/actualizacion/borrado - "cero
# escritura" es verdad por construccion, no por un chequeo en runtime.
class Cartera::ErpConnector
  def fetch_clientes
    raise NotImplementedError
  end

  def fetch_cupos
    raise NotImplementedError
  end

  def fetch_facturas
    raise NotImplementedError
  end

  def fetch_pagos
    raise NotImplementedError
  end

  def fetch_anticipos
    raise NotImplementedError
  end

  def fetch_notas_credito
    raise NotImplementedError
  end

  def fetch_eventos_radian
    raise NotImplementedError
  end
end
