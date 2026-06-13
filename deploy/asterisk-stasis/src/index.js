// Punto de entrada: conecta a ARI y registra los handlers de routing + presencia.
import ari from 'ari-client';
import { handleInbound, blindTransfer } from './routing.js';
import { reportPresence } from './events.js';

const { ARI_URL, ARI_USERNAME, ARI_PASSWORD, ARI_APP, FALLBACK_CONTEXT } = process.env;

const RECONNECT_BASE_MS = 2_000;
const RECONNECT_MAX_MS = 60_000;

async function connect(attempt = 0) {
  try {
    const client = await ari.connect(ARI_URL, ARI_USERNAME, ARI_PASSWORD);

    // Resetear contador al conectar exitosamente.
    attempt = 0;

    client.on('StasisStart', async (event, channel) => {
      if (event.args?.[0] === 'dialed') return;
      try {
        await handleInbound(client, channel);
      } catch (err) {
        console.error('routing error', err);
        channel.continueInDialplan({ context: FALLBACK_CONTEXT }).catch(() => {});
      }
    });

    client.on('ChannelTransfer', async (event) => {
      if (event.target_extension) {
        await blindTransfer(client, event.channel.id, event.target_extension).catch(() => {});
      }
    });

    // TODO U3: reemplazar por conexión AMI escuchando ContactStatus (registro SIP real).
    client.on('DeviceStateChanged', (event) => {
      const m = /^PJSIP\/(\d+)$/.exec(event.device_state?.name || event.device || '');
      if (!m) return;
      const extension = m[1];
      const online =
        event.device_state?.state === 'NOT_INUSE' || event.device_state?.state === 'INUSE';
      reportPresence({ extension, online });
    });

    client.on('close', () => {
      console.warn('ARI WebSocket cerrado — reconectando...');
      scheduleReconnect(attempt + 1);
    });

    client.on('error', (err) => {
      console.error('ARI error', err.message);
      // 'close' se dispara después; scheduleReconnect lo maneja.
    });

    client.start(ARI_APP);
    console.log(`Stasis app "${ARI_APP}" conectada a ${ARI_URL}`);
  } catch (err) {
    console.error(`ARI connect failed (intento ${attempt + 1}):`, err.message);
    scheduleReconnect(attempt + 1);
  }
}

function scheduleReconnect(attempt) {
  // Backoff exponencial con jitter: 2s, 4s, 8s … cap 60s.
  const delay = Math.min(RECONNECT_BASE_MS * 2 ** attempt, RECONNECT_MAX_MS);
  const jitter = Math.random() * 1000;
  console.log(`Reintentando en ${Math.round((delay + jitter) / 1000)}s...`);
  setTimeout(() => connect(attempt), delay + jitter);
}

connect();
