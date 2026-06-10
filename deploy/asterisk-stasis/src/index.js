// Punto de entrada: conecta a ARI y registra los handlers de routing + presencia.
import ari from 'ari-client';
import { handleInbound, blindTransfer } from './routing.js';
import { postEvent } from './railsClient.js';

const { ARI_URL, ARI_USERNAME, ARI_PASSWORD, ARI_APP } = process.env;

async function main() {
  const client = await ari.connect(ARI_URL, ARI_USERNAME, ARI_PASSWORD);

  // Una llamada entra al contexto Stasis desde el dialplan de FreePBX
  // (ver deploy/freepbx/extensions_custom.conf.example).
  client.on('StasisStart', async (event, channel) => {
    // El leg "dialed" (agente) se maneja dentro de routing.js; aquí solo el entrante.
    if (event.args?.[0] === 'dialed') return;
    try {
      await handleInbound(client, channel);
    } catch (err) {
      // Aislamiento: cualquier fallo del routing manda la llamada al fallback,
      // nunca la cuelga en seco.
      // eslint-disable-next-line no-console
      console.error('routing error', err);
      channel.continueInDialplan({ context: process.env.FALLBACK_CONTEXT });
    }
  });

  // Transferencia ciega: el agente envía REFER; ARI lo expone como evento.
  // (Mecanismo exacto depende de chan_pjsip; alternativamente exponer un
  //  endpoint HTTP interno que el panel llame y aquí se ejecute blindTransfer.)
  client.on('ChannelTransfer', async (event) => {
    if (event.target_extension) {
      await blindTransfer(client, event.channel.id, event.target_extension);
    }
  });

  // Presencia SIP (FIX-3) — OJO (U3): ARI DeviceState NO es el registro real.
  // El register/unregister verídico llega por AMI (ContactStatus / PeerStatus),
  // NO por DeviceStateChanged de ARI (device state = in-use/idle, no registro).
  // TODO U3: abrir una conexión AMI (manager.conf, ver deploy/freepbx/README) y
  // escuchar evento "ContactStatus" (Status: Reachable/Unreachable/Created/Removed)
  // → postEvent({ type: 'sip_register'|'sip_unregister', extension }).
  // Además, al ARRANCAR (U3/G1) hacer un full-sync: AMI "PJSIPShowContacts"
  // → postEvent({ type: 'sync', registered: [exts...] }) para reconciliar sip_online.
  // El handler ARI de abajo queda como aproximación; reemplazar por AMI.
  client.on('DeviceStateChanged', (event) => {
    const m = /^PJSIP\/(\d+)$/.exec(event.device_state?.name || event.device || '');
    if (!m) return;
    const extension = m[1];
    const online = event.device_state?.state === 'NOT_INUSE' || event.device_state?.state === 'INUSE';
    postEvent({ type: online ? 'sip_register' : 'sip_unregister', extension });
  });

  client.start(ARI_APP);
  // eslint-disable-next-line no-console
  console.log(`Stasis app "${ARI_APP}" conectada a ${ARI_URL}`);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('No se pudo iniciar la Stasis app', err);
  process.exit(1);
});
