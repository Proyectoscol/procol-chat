# Reemplaza el timing hardcodeado de Calendario::BotSessionReminderJob
# (THRESHOLD_BY_REMINDER_COUNT) por una configuracion editable por flow.
# default '[]' -- un flow sin reminder_schedule configurado sigue usando el
# fallback de 5/20 minutos que el job ya tenia antes de este cambio.
class AddReminderScheduleToCalendarioWelcomeBotFlows < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_welcome_bot_flows, :reminder_schedule, :jsonb, null: false, default: []
  end
end
