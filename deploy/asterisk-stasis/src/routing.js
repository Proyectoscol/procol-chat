// Lógica de routing: Dial a extensión, IVR de Teams, transferencia ciega, fallback.
import { getRouting, postEvent } from './railsClient.js';

const DIAL_TIMEOUT = Number(process.env.DIAL_TIMEOUT_SECONDS || 15);
const IVR_PROMPT = process.env.IVR_PROMPT || 'ivr-ciudades';
const FALLBACK_CONTEXT = process.env.FALLBACK_CONTEXT || 'from-voicemail';

// Marca a una extensión PJSIP y espera respuesta. Devuelve true si contestó.
async function dialExtension(client, channel, extension, linkedid) {
  const dialed = client.Channel();
  try {
    await dialed.originate({
      endpoint: `PJSIP/${extension}`,
      app: process.env.ARI_APP,
      appArgs: 'dialed',
      timeout: DIAL_TIMEOUT,
      originator: channel.id,
    });
  } catch {
    return false;
  }

  return await new Promise(resolve => {
    let answered = false;
    dialed.on('StasisStart', async () => {
      answered = true;
      await postEvent({ type: 'answered', linkedid }); // FIX-4: Rails asigna conversación AQUÍ
      const bridge = client.Bridge();
      await bridge.create({ type: 'mixing' });
      await bridge.addChannel({ channel: [channel.id, dialed.id] });
      resolve(true);
    });
    dialed.on('ChannelDestroyed', (evt) => {
      if (!answered) {
        // FIX-9: reenviar el cause; Rails lo mapea (no_answer/busy/failed).
        postEvent({ type: 'missed', linkedid, cause: evt.cause });
        resolve(false);
      }
    });
  });
}

// Entrada principal por cada llamada que entra al contexto Stasis.
export async function handleInbound(client, channel) {
  const linkedid = channel.linkedid || channel.id; // FIX-10: Linkedid estable
  const phone = normalizeE164(channel.caller?.number);

  await postEvent({ type: 'ringing', linkedid, from: phone });

  let decision = await getRouting({ phone, linkedid });
  if (decision.fallback) return sendToFallback(channel);

  // Contacto con asesor asignado → suena solo a él (con caída al RR si no contesta).
  if (decision.extension) {
    const ok = await dialExtension(client, channel, decision.extension, linkedid);
    if (ok) return;
    decision = { ivr: true }; // no contestó el asignado → IVR/RR
  }

  // IVR de Teams.
  if (decision.ivr) {
    const digit = await playIvrAndGetDigit(client, channel);
    let pick = await getRouting({ teamDigit: digit, linkedid });
    // RR: intentar en orden hasta que alguien conteste.
    while (pick.extension) {
      const ok = await dialExtension(client, channel, pick.extension, linkedid);
      if (ok) return;
      pick = await getRouting({ teamDigit: digit, linkedid }); // siguiente del RR
    }
    return sendToVoicemail(channel, linkedid); // sin asesor → buzón + Rails crea conversación
  }
}

// Transferencia ciega asesor→asesor (REFER del agente llega como evento; redirige el leg).
export async function blindTransfer(client, channelId, targetExtension) {
  const ch = client.Channel(channelId);
  await ch.redirect({ endpoint: `PJSIP/${targetExtension}` });
}

// ---- helpers (TODOs de implementación) ----
function normalizeE164(num) {
  // FIX-8: normalización canónica. Rails re-normaliza igual, pero mandamos limpio.
  if (!num) return num;
  let n = String(num).replace(/[^\d+]/g, '');
  if (!n.startsWith('+')) n = n.length === 10 ? `+57${n}` : `+${n}`; // Colombia default
  return n;
}

async function playIvrAndGetDigit(/* client, channel */) {
  // TODO: playback(IVR_PROMPT) + recolectar 1 dígito DTMF con timeout.
  return '1';
}

function sendToFallback(channel) {
  return channel.continueInDialplan({ context: FALLBACK_CONTEXT });
}

async function sendToVoicemail(channel, linkedid) {
  await postEvent({ type: 'missed', linkedid, reason: 'no_agent' });
  return channel.continueInDialplan({ context: FALLBACK_CONTEXT });
}
