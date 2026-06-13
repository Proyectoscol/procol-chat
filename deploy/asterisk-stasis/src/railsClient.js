// Cliente HTTP a los endpoints internos de Rails (/sip/*).
// Stateless: una petición por decisión. Token compartido (constant-time en Rails).
import { request } from 'undici';

const BASE = process.env.RAILS_INTERNAL_URL; // e.g. https://chat.example.com/api/v1/internal
const TOKEN = process.env.SIP_INTERNAL_TOKEN;

const headers = () => ({
  'Content-Type': 'application/json',
  'X-Asterisk-Token': TOKEN,
});

// GET /sip/routing → {action:'dial'|'ivr'|'voicemail'|'busy', extension?, prompt?}
export async function getRouting({ phone, teamDigit, linkedid }) {
  const qs = new URLSearchParams({ linkedid });
  if (phone) qs.set('phone', phone);
  if (teamDigit) qs.set('ivr_digit', teamDigit);
  try {
    const res = await request(`${BASE}/sip/routing?${qs}`, { headers: headers() });
    if (res.statusCode !== 200) return { action: 'voicemail' };
    return await res.body.json();
  } catch {
    // Aislamiento: si Rails no responde, fallback local.
    return { action: 'voicemail' };
  }
}

// POST /sip/events → ciclo de vida + presencia.
// event_type: answered | ended | no_answer | sip_register | sip_unregister
export async function postEvent(payload) {
  try {
    await request(`${BASE}/sip/events`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify(payload),
    });
  } catch {
    // No-op: los eventos son best-effort; la voz nunca rompe por esto.
  }
}
