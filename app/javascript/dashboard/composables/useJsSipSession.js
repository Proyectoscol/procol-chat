import { readonly, ref } from 'vue';
import JsSIP from 'jssip';
import axios from 'axios';

// Hermano de useWhatsappCallSession: el provider-session para Asterisk (SIP/WebRTC
// vía JsSIP). NO es un sistema paralelo — useCallSession delega aquí cuando el
// provider es 'asterisk', igual que delega a useWhatsappCallSession para whatsapp.
//
// El estado vive a nivel de módulo (igual que WhatsApp) para que los handlers del
// UA y los listeners de unload alcancen la sesión viva sin prop-drilling de refs.
let ua = null; // JsSIP.UA — una sola instancia por sesión de dashboard
let currentSession = null; // RTCSession activa (entrante o saliente)
let localStream = null; // mic stream — se LIBERA en cleanup (FIX teardown del plan)
let remoteAudioEl = null;
let credentials = null; // credencial cacheada del REGISTER (extension, password, wss…)
let incomingNotification = null;
// vue-i18n no es accesible a nivel de módulo; el composable inyecta su `t` aquí
// para que los handlers del UA (entrante) puedan traducir la notificación nativa.
let translate = null;

const isRegistered = ref(false);
const isReconnecting = ref(false);
const isRegisteredReadonly = readonly(isRegistered);
const isReconnectingReadonly = readonly(isReconnecting);

// Sin TURN/STUN del backend el navegador solo emite host candidates y el media
// browser↔Asterisk cae en cualquier NAT no trivial. Fallback igual que WhatsApp.
const DEFAULT_ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];

// JsSIP reintenta el WebSocket solo; estos límites acotan el backoff (R1-4).
const WS_RECOVERY_MIN_INTERVAL = 2;
const WS_RECOVERY_MAX_INTERVAL = 30;

const ensureRemoteAudioElement = () => {
  if (remoteAudioEl) return remoteAudioEl;
  remoteAudioEl = document.createElement('audio');
  remoteAudioEl.id = 'sip-call-remote-audio';
  remoteAudioEl.autoplay = true;
  remoteAudioEl.playsInline = true;
  remoteAudioEl.style.display = 'none';
  document.body.appendChild(remoteAudioEl);
  return remoteAudioEl;
};

const playRemoteStream = stream => {
  const el = ensureRemoteAudioElement();
  el.srcObject = stream;
  el.play().catch(err => {
    // eslint-disable-next-line no-console
    console.warn('[SIP Call] remote audio play() failed:', err);
  });
};

const dismissIncomingNotification = () => {
  if (!incomingNotification) return;
  try {
    incomingNotification.close();
  } catch (_) {
    /* noop */
  }
  incomingNotification = null;
};

// Notificación nativa del navegador para la llamada entrante (cuando el asesor
// tiene otra pestaña/ventana al frente). Requiere permiso ya concedido.
const showIncomingNotification = session => {
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;
  const caller = session?.remote_identity?.uri?.user || '';
  const title = translate
    ? translate('VOICE_TELEPHONY.INCOMING_CALL.TITLE')
    : 'Incoming call';
  const body = translate
    ? translate('VOICE_TELEPHONY.INCOMING_CALL.BODY', { caller })
    : caller;
  try {
    incomingNotification = new Notification(title, {
      body,
      tag: 'sip-incoming',
    });
  } catch (_) {
    /* noop */
  }
};

// Teardown por-llamada. Clave del FIX: detener los tracks de getUserMedia — JsSIP
// no siempre libera el micrófono al colgar, dejando el indicador de mic encendido.
// NO toca el UA: la registración persiste entre llamadas.
const cleanup = () => {
  if (localStream) localStream.getTracks().forEach(track => track.stop());
  if (remoteAudioEl) remoteAudioEl.srcObject = null;
  dismissIncomingNotification();
  currentSession = null;
  localStream = null;
};

// Audio remoto + ciclo de vida de la sesión. 'ended'/'failed' → cleanup (que
// libera el mic). No re-termina aquí: terminate() lo dispara endCall/rejectCall.
const attachSessionHandlers = session => {
  session.on('peerconnection', ({ peerconnection }) => {
    peerconnection.addEventListener('track', event => {
      if (event.streams && event.streams[0]) playRemoteStream(event.streams[0]);
    });
  });
  session.on('ended', cleanup);
  session.on('failed', cleanup);
};

const handleNewRTCSession = ({ originator, session }) => {
  // Saliente: ya la maneja startCall. Aquí solo interesa la entrante.
  if (originator !== 'remote') return;
  // Ya hay una llamada en curso → rechazar la nueva como ocupado.
  if (currentSession) {
    try {
      session.terminate({ status_code: 486, reason_phrase: 'Busy Here' });
    } catch (_) {
      /* noop */
    }
    return;
  }
  currentSession = session;
  attachSessionHandlers(session);
  showIncomingNotification(session);
};

const attachUaHandlers = instance => {
  instance.on('registered', () => {
    isRegistered.value = true;
    isReconnecting.value = false;
  });
  instance.on('unregistered', () => {
    isRegistered.value = false;
  });
  instance.on('registrationFailed', () => {
    isRegistered.value = false;
  });
  // JsSIP reintenta el WS solo; reflejamos el estado para el badge "Reconectando".
  instance.on('disconnected', () => {
    isReconnecting.value = true;
  });
  instance.on('connected', () => {
    isReconnecting.value = false;
  });
  instance.on('newRTCSession', handleNewRTCSession);
};

const buildUa = creds => {
  const socket = new JsSIP.WebSocketInterface(creds.wss_url);
  const instance = new JsSIP.UA({
    sockets: [socket],
    uri: `sip:${creds.sip_extension}@${creds.sip_domain}`,
    password: creds.sip_password,
    register: true,
    connection_recovery_min_interval: WS_RECOVERY_MIN_INTERVAL,
    connection_recovery_max_interval: WS_RECOVERY_MAX_INTERVAL,
  });
  attachUaHandlers(instance);
  return instance;
};

// El accountId sale de la ruta (igual que useWhatsappCallSession para el beacon).
const fetchCredentials = async () => {
  const accountId = window.location.pathname.split('/')[3];
  if (!accountId) return null;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId}/sip/credential`
    );
    return data && Object.keys(data).length ? data : null;
  } catch (_) {
    // 404 = el usuario no tiene SipIdentity (no es asesor de Voz). Degrada limpio.
    return null;
  }
};

export const hasActiveSipCall = () => !!currentSession;

export const isSipRegistered = () => isRegistered.value;

export const cleanupSipSession = () => cleanup();

// Silencia/reactiva el mic deshabilitando los tracks (no los detiene: la llamada
// sigue viva). Espejo de setWhatsappCallMuted.
export const setSipCallMuted = muted => {
  if (!localStream) return false;
  localStream.getAudioTracks().forEach(track => {
    track.enabled = !muted;
  });
  return muted;
};

export function useJsSipSession() {
  // Inyecta el traductor del composable a los handlers de módulo (notificación).
  const setTranslator = t => {
    translate = t;
  };

  // Pide la credencial y arranca el UA (REGISTER). Se llama al login si el usuario
  // es inbox-member de Voz. Idempotente: si ya hay UA, no crea otro.
  const register = async () => {
    if (ua) return isRegistered.value;

    credentials = await fetchCredentials();
    if (!credentials || !credentials.wss_url) return false;

    ua = buildUa(credentials);
    ua.start();
    return true;
  };

  const unregister = () => {
    cleanup();
    if (ua) {
      try {
        ua.stop();
      } catch (_) {
        /* noop */
      }
      ua = null;
    }
    isRegistered.value = false;
    isReconnecting.value = false;
  };

  // Saliente: INVITE de JsSIP a la extensión/destino. Pasamos NUESTRO mediaStream
  // para controlar la liberación del mic en cleanup (FIX).
  const startCall = async target => {
    if (!ua || !isRegistered.value || currentSession) return null;

    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const session = ua.call(`sip:${target}@${credentials.sip_domain}`, {
      mediaStream: localStream,
      pcConfig: { iceServers: credentials.ice_servers || DEFAULT_ICE_SERVERS },
    });
    currentSession = session;
    attachSessionHandlers(session);
    return session;
  };

  // Entrante: el asesor contesta. Su clic = pickup.
  const acceptCall = async () => {
    if (!currentSession) return;

    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    currentSession.answer({
      mediaStream: localStream,
      pcConfig: { iceServers: credentials?.ice_servers || DEFAULT_ICE_SERVERS },
    });
    dismissIncomingNotification();
  };

  // Rechaza la entrante (486 Busy Here) y libera el mic.
  const rejectCall = () => {
    if (currentSession) {
      try {
        currentSession.terminate({
          status_code: 486,
          reason_phrase: 'Busy Here',
        });
      } catch (_) {
        /* noop */
      }
    }
    cleanup();
  };

  // Cuelga la llamada activa. terminate() dispara 'ended' → cleanup; el cleanup
  // explícito garantiza la liberación del mic aunque el evento no llegue.
  const endCall = () => {
    if (currentSession) {
      try {
        currentSession.terminate();
      } catch (_) {
        /* noop */
      }
    }
    cleanup();
  };

  return {
    isRegistered: isRegisteredReadonly,
    isReconnecting: isReconnectingReadonly,
    setTranslator,
    register,
    unregister,
    startCall,
    acceptCall,
    rejectCall,
    endCall,
    setMuted: setSipCallMuted,
    hasActiveCall: hasActiveSipCall,
  };
}
