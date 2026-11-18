class AddTestModeToCalendarioAppointmentEventTriggers < ActiveRecord::Migration[7.1]
  def change
    # Permite probar un disparador (confirmacion, recordatorio, etc.) sin
    # mandarle un mensaje real de WhatsApp al paciente -- en vez de llamar a
    # channel.send_template, se crea una nota privada en la conversacion con
    # el contenido que se habria enviado. Pedido explicito del usuario antes
    # de pasar a produccion: "quiero primero hacer envios de notas privadas
    # no de mensajes reales, para ver como esta funcionando el envio".
    add_column :calendario_appointment_event_triggers, :test_mode, :boolean, null: false, default: false
  end
end
