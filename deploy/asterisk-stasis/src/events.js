// Reporter de eventos de ciclo de vida al endpoint Rails POST /sip/events.
// Todos los eventos son best-effort: un fallo de red nunca debe cortar la voz.
import { postEvent } from './railsClient.js';

export const reportAnswered = ({ linkedid, extension, phone }) =>
  postEvent({ event_type: 'answered', linkedid, extension, phone });

export const reportEnded = ({ linkedid, durationSeconds, cause }) =>
  postEvent({ event_type: 'ended', linkedid, duration_seconds: durationSeconds, cause });

export const reportNoAnswer = ({ linkedid, phone }) =>
  postEvent({ event_type: 'no_answer', linkedid, phone });

// Presencia SIP (ver index.js — TODO U3: migrar a AMI ContactStatus).
export const reportPresence = ({ extension, online }) =>
  postEvent({ event_type: online ? 'sip_register' : 'sip_unregister', extension });
