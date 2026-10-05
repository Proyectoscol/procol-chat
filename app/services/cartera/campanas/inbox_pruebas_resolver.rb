# La bandeja de pruebas de una cuenta: el inbox tipo Channel::Api que el
# entorno de pruebas usa para enrutar envios sin que nada real le llegue a
# un telefono o correo - ver Cartera::Campanas::PruebaService. Se asume una
# sola por cuenta (decision confirmada con el usuario); si hay varias se usa
# la mas antigua para que el comportamiento sea estable entre corridas.
class Cartera::Campanas::InboxPruebasResolver
  pattr_initialize [:account!]

  def resolver!
    account.inboxes.where(channel_type: 'Channel::Api').order(:id).first ||
      raise('No hay un inbox de pruebas (tipo API) configurado en esta cuenta. ' \
            'Crea uno desde Ajustes > Bandejas > Añadir bandeja > API.')
  end
end
