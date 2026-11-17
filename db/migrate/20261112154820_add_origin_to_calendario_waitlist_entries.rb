class AddOriginToCalendarioWaitlistEntries < ActiveRecord::Migration[7.1]
  def change
    # "manual": el personal agrego el contacto directamente. "cancellation":
    # la entrada nacio de una cancelacion temporal (ver
    # Calendario::WaitlistFulfillmentService#reactivate!) -- sirve para
    # priorizar a quien ya tenia cita y se enfermo sobre alguien nuevo.
    add_column :calendario_waitlist_entries, :origin, :integer, null: false, default: 0
  end
end
