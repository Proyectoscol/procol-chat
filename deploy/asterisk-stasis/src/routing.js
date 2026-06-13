// Lógica de routing: Dial, IVR, transferencia ciega, fallback.
import { getRouting } from './railsClient.js';
import { reportAnswered, reportEnded, reportNoAnswer } from './events.js';
import { playPromptAndGetDigit } from './ivr.js';

const DIAL_TIMEOUT = Number(process.env.DIAL_TIMEOUT_SECONDS || 30);
const FALLBACK_CONTEXT = process.env.FALLBACK_CONTEXT || 'from-voicemail';

export async function handleInbound(client, channel) {
  const linkedid = channel.linkedid || channel.id;
  const phone = normalizeE164(channel.caller?.number);
  // DID que fue marcado (extensión del dialplan = número de la troncal SIP).
  // Rails lo usa para resolver el Channel::Voice correcto (resolve_voice_inbox).
  const to = normalizeE164(channel.dialplan?.exten);
  let answeredAt = null;

  // StasisEnd del canal entrante → reportar duración si hubo bridge.
  channel.once('StasisEnd', () => {
    if (answeredAt) {
      reportEnded({
        linkedid,
        to,
        durationSeconds: Math.round((Date.now() - answeredAt) / 1000),
      });
    }
  });

  const decision = await getRouting({ phone, to, linkedid });

  if (decision.action === 'busy') {
    await channel.hangup().catch(() => {});
    return;
  }

  if (decision.action === 'dial') {
    const ok = await dialExtension(client, channel, decision.extension, linkedid, () => {
      answeredAt = Date.now();
    }, to);
    if (!ok) {
      await reportNoAnswer({ linkedid, phone, to });
      return sendToFallback(channel);
    }
    return; // bridge activo; StasisEnd reportará 'ended'
  }

  if (decision.action === 'ivr') {
    const digit = await playPromptAndGetDigit(client, channel, decision.prompt);
    if (!digit) return sendToFallback(channel);

    // Round-robin: Rails devuelve el siguiente asesor disponible cada vez.
    let pick = await getRouting({ to, teamDigit: digit, linkedid });
    while (pick.action === 'dial') {
      const ok = await dialExtension(client, channel, pick.extension, linkedid, () => {
        answeredAt = Date.now();
      }, to);
      if (ok) return;
      pick = await getRouting({ to, teamDigit: digit, linkedid });
    }
    await reportNoAnswer({ linkedid, phone, to });
    return sendToFallback(channel);
  }

  // action === 'voicemail' o desconocido
  return sendToFallback(channel);
}

// Origina hacia PJSIP/<extension> y crea un bridge mixing si contesta.
// Devuelve true si la llamada fue contestada.
async function dialExtension(client, channel, extension, linkedid, onAnswered, to) {
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

  return new Promise((resolve) => {
    let bridged = false;
    let answered = false;

    // Timeout de seguridad JS (Asterisk ya tiene timeout en la originación).
    const timer = setTimeout(() => {
      if (!bridged) {
        dialed.hangup().catch(() => {});
        resolve(false);
      }
    }, DIAL_TIMEOUT * 1000 + 2000); // +2s de margen

    // Task spec: ChannelStateChange(Up) → evento 'answered'.
    dialed.on('ChannelStateChange', (evt) => {
      if (evt.channel?.state === 'Up' && !answered) {
        answered = true;
        onAnswered?.();
        reportAnswered({ linkedid, to, extension });
      }
    });

    dialed.on('StasisStart', async () => {
      if (bridged) return;
      bridged = true;
      clearTimeout(timer);
      // Fallback: si ChannelStateChange(Up) no llegó antes de StasisStart.
      if (!answered) {
        answered = true;
        onAnswered?.();
        reportAnswered({ linkedid, to, extension });
      }
      try {
        const bridge = client.Bridge();
        await bridge.create({ type: 'mixing' });
        await bridge.addChannel({ channel: [channel.id, dialed.id] });
      } catch {
        // Si el bridge falla, la llamada sigue sin audio — colgar limpiamente.
        dialed.hangup().catch(() => {});
        channel.hangup().catch(() => {});
      }
      resolve(true);
    });

    dialed.on('ChannelDestroyed', () => {
      if (!bridged) {
        clearTimeout(timer);
        resolve(false);
      }
    });
  });
}

// Transferencia ciega asesor→asesor (REFER del agente o petición del panel).
export async function blindTransfer(client, channelId, targetExtension) {
  const ch = client.Channel(channelId);
  await ch.redirect({ endpoint: `PJSIP/${targetExtension}` });
}

function normalizeE164(num) {
  if (!num) return num;
  let n = String(num).replace(/[^\d+]/g, '');
  if (!n.startsWith('+')) n = n.length === 10 ? `+57${n}` : `+${n}`; // Colombia
  return n;
}

function sendToFallback(channel) {
  return channel.continueInDialplan({ context: FALLBACK_CONTEXT }).catch(() => {});
}
