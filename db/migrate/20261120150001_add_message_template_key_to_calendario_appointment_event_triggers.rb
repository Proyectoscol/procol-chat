class AddMessageTemplateKeyToCalendarioAppointmentEventTriggers < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_appointment_event_triggers, :message_template_key, :string
  end
end
