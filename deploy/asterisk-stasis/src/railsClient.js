// Cliente HTTP a los endpoints internos de Rails (/sip/*).
// Stateless: una petición por decisión. Token compartido (constant-time en Rails).
import { request } from 'undici';

const BASE = process.env.RAILS_BASE_URL;
const SECRET = process.env.RAILS_SIP_SECRET;

const headers = () => ({
  'Content-Type': 'application/json',
  'X-Asterisk-Token': SECRET,
});

// GET /sip/routing → decisión de enrutamiento.
// Devuelve { extension, agent_id } | { ivr: true } | { voicemail: true }
export async function getRouting({ phone, teamDigit, linkedid }) {
  const qs = new URLSearchParams({ linkedid });
  if (phone) qs.set('phone', phone);
  if (teamDigit) qs.set('team_digit', teamDigit);
  try {
    const res = await request(`${BASE}/sip/routing?${qs}`, {
      headers: headers(),
    });
    if (res.statusCode !== 200) return { fallback: true };
    return await res.body.json();
  } catch {
    // FIX-3/aislamiento: si Rails no responde, fallback local (el caller manda a IVR/cola).
    return { fallback: true };
  }
}

// POST /sip/events → ciclo de vida + presencia.
// type: ringing | answered | ended | missed | sip_register | sip_unregister
export async function postEvent(payload) {
  try {
    await request(`${BASE}/sip/events`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify(payload),
    });
  } catch {
    // No-op: los eventos son best-effort; el estado de la llamada no debe romper la voz.
  }
}
