# prioridad_score era el campo de la formula de priorizacion retirada
# (PriorizacionService::PESOS_DEFAULT) - el panel "Clientes" ahora ordena
# directamente por puntaje_riesgo, el unico puntaje que queda tras unificar
# los dos algoritmos (ver Cartera::PuntajeRiesgoService). Columna sin
# consumidores en frontend ni backend tras la unificacion (verificado por
# grep antes de este cambio).
class RemovePrioridadScoreFromCarteraCasos < ActiveRecord::Migration[7.1]
  def change
    remove_column :cartera_casos, :prioridad_score, :decimal, precision: 10, scale: 4
  end
end
