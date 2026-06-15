// Reporter de eventos de ciclo de vida al endpoint Rails POST /sip/events.
// Todos los eventos son best-effort: un fallo de red nunca debe cortar la voz.
import { postEvent } from './railsClient.js';

export const reportAnswered = ({ linkedid, extension, phone, to }) =>
  postEvent({ event_type: 'answered', linkedid, extension, from_number: phone, to, call_direction: 'inbound' });

export const reportEnded = ({ linkedid, durationSeconds, cause, phone, to, extension }) =>
  postEvent({ event_type: 'ended', linkedid, duration_seconds: durationSeconds, cause, from_number: phone, to, to_extension: extension, call_direction: 'inbound' });

export const reportNoAnswer = ({ linkedid, phone, to }) =>
  postEvent({ event_type: 'no_answer', linkedid, from_number: phone, to, call_direction: 'inbound' });

// Presencia SIP (ver index.js — TODO U3: migrar a AMI ContactStatus).
export const reportPresence = ({ extension, online }) =>
  postEvent({ event_type: online ? 'sip_register' : 'sip_unregister', extension });
