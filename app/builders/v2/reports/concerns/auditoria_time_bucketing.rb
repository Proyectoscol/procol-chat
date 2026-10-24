# Umbrales + resolucion de bucket (dia/semana/mes) compartidos entre los
# builders de series de tiempo de Auditoria (menciones de categoria,
# sentimiento de conversacion) -- un rango corto agrupado por dia satura el
# eje X (ej. un ano completo = 365 puntos), pero agrupar por semana/mes en
# un rango corto perderia resolucion util. Cada builder sigue dueno de su
# propio #bucket_column (la columna de fecha a truncar difiere: DATE vs
# TIMESTAMP segun la tabla), este modulo solo comparte lo que es identico:
# los umbrales, el calculo de resolucion, y la normalizacion del valor
# truncado a Date.
module V2::Reports::Concerns::AuditoriaTimeBucketing
  extend ActiveSupport::Concern

  DAY_BUCKET_MAX_DAYS = 35
  WEEK_BUCKET_MAX_DAYS = 180

  private

  def bucket_resolution
    @bucket_resolution ||= if range_days <= DAY_BUCKET_MAX_DAYS
                             :day
                           elsif range_days <= WEEK_BUCKET_MAX_DAYS
                             :week
                           else
                             :month
                           end
  end

  def range_days
    (range.end - range.begin).to_i
  end

  # date_trunc devuelve un timestamp (no un Date) para semana/mes -- se
  # normaliza a Date para que el formato de salida (date: "YYYY-MM-DD") sea
  # identico sin importar el bucket.
  def bucket_start_date(value)
    value.to_date
  end

  def range
    Time.zone.at(params[:since].to_i).to_date..Time.zone.at(params[:until].to_i).to_date
  end
end
