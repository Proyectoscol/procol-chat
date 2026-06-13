/* global axios */
// Usa el axios GLOBAL de Chatwoot (instancia wootApi configurada en APIHelper.js):
// lleva los headers de devise-token-auth (access-token/token-type/client/uid) en
// defaults.headers.common. El `import axios from 'axios'` crudo NO los tiene → 401.
import { readonly, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import JsSIP from 'jssip';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_STATUS,
} from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

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
const callFailureReason = ref('');
const isRegisteredReadonly = readonly(isRegistered);
const isReconnectingReadonly = readonly(isReconnecting);
const callFailureReasonReadonly = readonly(callFailureReason);

// Sin TURN/STUN del backend el navegador solo emite host candidates y el media
// browser↔Asterisk cae en cualquier NAT no trivial. Fallback igual que WhatsApp.
// Dos servidores STUN en paralelo: el browser usa el primero que responda.
// Reduce la latencia de ICE gathering de ~300 ms a ~50-100 ms en la mayoría
// de redes. Si ambos fallan, el timeout de 400 ms envía el INVITE con candidatos host.
const DEFAULT_ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
];

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

// Feedback sonoro al colgar.
const HANGUP_SOUND_URL = '/audio/dashboard/ping.mp3';
const playHangupSound = () => {
  try {
    new Audio(HANGUP_SOUND_URL).play().catch(() => {});
  } catch (_) {
    /* noop */
  }
};

// Ringback: tono que el llamante escucha mientras espera respuesta.
// Genera 440 Hz + 480 Hz (tono PSTN estándar) con Web Audio API — sin archivo.
// Patrón: 2 s tono · 4 s silencio · repite.
let ringbackCtx = null;
let ringbackTimer = null;

const startRingback = () => {
  if (ringbackCtx) return;
  try {
    // eslint-disable-next-line no-undef
    ringbackCtx = new (window.AudioContext || window.webkitAudioContext)();
  } catch (_) {
    return;
  }
  const playBurst = () => {
    if (!ringbackCtx || ringbackCtx.state === 'closed') return;
    // Chrome crea el AudioContext en 'suspended' cuando no hay gesto de usuario
    // activo en el stack. resume() lo activa antes de crear los osciladores.
    ringbackCtx
      .resume()
      .then(() => {
        if (!ringbackCtx || ringbackCtx.state === 'closed') return;
        [440, 480].forEach(freq => {
          const osc = ringbackCtx.createOscillator();
          const gain = ringbackCtx.createGain();
          osc.frequency.value = freq;
          gain.gain.value = 0.15;
          osc.connect(gain);
          gain.connect(ringbackCtx.destination);
          osc.start();
          osc.stop(ringbackCtx.currentTime + 2);
        });
      })
      .catch(() => {});
    ringbackTimer = setTimeout(playBurst, 6000);
  };
  playBurst();
};

const stopRingback = () => {
  clearTimeout(ringbackTimer);
  ringbackTimer = null;
  try {
    ringbackCtx?.close();
  } catch (_) {
    /* noop */
  }
  ringbackCtx = null;
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

// Teardown WebRTC por-llamada: libera mic, limpia audio remoto, descarta
// notificación nativa. NO toca el store — el llamador es responsable de invocar
// callsStore.clearActiveCall() para evitar la recursión:
//   clearActiveCall → teardownByProvider → cleanupSipSession → cleanup
//                                                               → clearActiveCall → ∞
const cleanup = () => {
  if (localStream) localStream.getTracks().forEach(track => track.stop());
  if (remoteAudioEl) remoteAudioEl.srcObject = null;
  dismissIncomingNotification();
  currentSession = null;
  localStream = null;
};

// Máximo tiempo de espera para que el browser recoja candidatos ICE antes de
// enviar el INVITE. Sin límite el browser puede tardar hasta 60 s si el servidor
// STUN no responde. 400 ms es suficiente: candidatos host se recogen en <50 ms y
// STUN reflexivo suele llegar en 20-150 ms. Si no llega, se envía con host only.
const ICE_GATHERING_TIMEOUT_MS = 400;

const attachSessionHandlers = session => {
  session.on('peerconnection', ({ peerconnection }) => {
    peerconnection.addEventListener('track', event => {
      if (event.streams && event.streams[0]) playRemoteStream(event.streams[0]);
    });

    // ICE gathering timeout: JsSIP 3.13 espera el evento 'icecandidate' con
    // candidate=null (vía addEventListener, no la propiedad onicecandidate).
    // dispatchEvent con RTCPeerConnectionIceEvent alcanza ese listener y llama
    // ready() internamente, enviando el INVITE sin esperar los ~30 s del browser.
    let iceComplete = false;
    const iceTimer = setTimeout(() => {
      if (iceComplete) return;
      iceComplete = true;
      try {
        peerconnection.dispatchEvent(
          new RTCPeerConnectionIceEvent('icecandidate', { candidate: null })
        );
      } catch (_) {
        /* noop — el gathering completará naturalmente */
      }
    }, ICE_GATHERING_TIMEOUT_MS);

    peerconnection.addEventListener('icegatheringstatechange', () => {
      if (iceComplete) return;
      if (peerconnection.iceGatheringState === 'complete') {
        iceComplete = true;
        clearTimeout(iceTimer);
      }
    });
  });

  // 180 Ringing recibido del remoto → arrancar ringback en el llamante.
  // Solo para sesiones salientes; las entrantes ya tienen su propia tonalidad.
  session.on('progress', e => {
    if (e?.originator === 'remote' && session.direction === 'outgoing') {
      startRingback();
    }
  });

  // Llamada contestada: apagar ringback y marcar activa en el store.
  // setCallActive es idempotente — seguro llamarlo desde aquí y desde joinCall().
  session.on('confirmed', () => {
    stopRingback();
    useCallsStore().setCallActive(session.id);
  });

  // Limpia el store al terminar o fallar la sesión.
  //
  // Por qué no basta con c.callSid === session.id:
  // Para llamadas entrantes, el store puede tener DOS entradas para la misma
  // llamada: una de ActionCable (callSid = provider_call_id) y otra de JsSIP
  // (callSid = session.id). Si el agente aceptó usando la entrada de ActionCable
  // (porque llegó primero y es primaryIncomingCall), esa es la entrada activa.
  // El guard callSid === session.id nunca la encuentra → clearActiveCall no se
  // llama → FloatingCallWidget sigue mostrando la llamada activa.
  const clearSipCallFromStore = store => {
    // 1. Dismiss la entrada JsSIP si quedó inactiva (llamada saliente no contestada
    //    o entrante cuya entrada de ActionCable fue la que se activó).
    const stale = store.calls.find(
      c => c.callSid === session.id && !c.isActive
    );
    if (stale) store.dismissCall(session.id);
    // 2. Clear cualquier llamada Asterisk activa. buildCallActions.endCall() ya
    //    llama clearActiveCall() síncronamente (ruta FloatingCallWidget), así que
    //    store.activeCall será null en ese caso — guard natural.
    if (store.activeCall?.provider === VOICE_CALL_PROVIDERS.ASTERISK) {
      store.clearActiveCall();
    }
    // 3. Dismiss la entrada residual inactiva (la contraparte de ActionCable cuando
    //    fue la entrada JsSIP la que quedó activa, o viceversa).
    const residual = store.calls.find(
      c => !c.isActive && c.provider === VOICE_CALL_PROVIDERS.ASTERISK
    );
    if (residual) store.dismissCall(residual.callSid);
  };

  session.on('ended', e => {
    // eslint-disable-next-line no-console
    console.log(
      '[SIP] Sesión terminada:',
      e?.cause,
      'originator:',
      e?.originator
    );
    stopRingback();
    cleanup();
    if (e?.originator === 'remote') playHangupSound();
    clearSipCallFromStore(useCallsStore());
  });

  // Llamada rechazada, ocupada, sin respuesta, etc.
  session.on('failed', e => {
    // eslint-disable-next-line no-console
    console.log(
      '[SIP] Llamada fallida:',
      e?.cause,
      '| SIP status:',
      e?.message?.status_code,
      '| reason:',
      e?.message?.reason_phrase,
      '| originator:',
      e?.originator
    );
    stopRingback();
    callFailureReason.value = e?.cause || '';
    setTimeout(() => {
      callFailureReason.value = '';
    }, 5000);
    playHangupSound();
    cleanup();
    clearSipCallFromStore(useCallsStore());
  });
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

  // Surface the inbound call in the shared store so FloatingCallWidget / CallCard
  // render the accept/reject UI. JsSIP INVITEs arrive over WSS (no cable event),
  // so the composable is the only place that knows about an incoming call.
  useCallsStore().addCall({
    callSid: session.id,
    phoneNumber: session.remote_identity?.uri?.user || '',
    conversationId: null,
    inboxId: null,
    callDirection: VOICE_CALL_DIRECTION.INBOUND,
    provider: VOICE_CALL_PROVIDERS.ASTERISK,
    status: VOICE_CALL_STATUS.RINGING,
  });
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
    // Desactiva los session timers SIP (RE-INVITE periódicos de keepalive) que
    // añaden latencia y pueden causar reinvites inesperados con FreePBX.
    session_timers: false,
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
  const { t } = useI18n();
  translate = t;

  // Pide la credencial y arranca el UA (REGISTER). Se llama al login si el usuario
  // es inbox-member de Voz. Idempotente: si ya hay UA, no crea otro.
  const register = async () => {
    // UA muerto: existía pero no está registrado ni reconectando (p.ej. se instanció
    // con wss_url null). Destruirlo para que buildUa cree uno limpio.
    if (ua && !isRegistered.value && !isReconnecting.value) {
      try {
        ua.stop();
      } catch (_) {
        /* noop */
      }
      ua = null;
    }
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

  const setCallFailure = reason => {
    callFailureReason.value = reason;
    setTimeout(() => {
      callFailureReason.value = '';
    }, 5000);
  };

  // Saliente: INVITE de JsSIP a la extensión/destino. Pasamos NUESTRO mediaStream
  // para controlar la liberación del mic en cleanup (FIX).
  const startCall = async target => {
    if (!ua || !isRegistered.value || currentSession) return null;

    // Prevent SIP URI injection: only allow phone number characters.
    if (!/^[0-9+*#]{1,30}$/.test(target)) {
      setCallFailure('Invalid Number');
      return null;
    }

    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (_) {
      setCallFailure('Mic Denied');
      return null;
    }
    localStream = stream;
    const session = ua.call(`sip:${target}@${credentials.sip_domain}`, {
      mediaStream: localStream,
      pcConfig: {
        iceServers: credentials.ice_servers || DEFAULT_ICE_SERVERS,
        // max-bundle reduce los candidatos ICE a recolectar (un solo puerto para
        // todos los medios en vez de uno por stream), acelerando el ICE gathering.
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require',
      },
      rtcOfferConstraints: {
        offerToReceiveAudio: true,
        offerToReceiveVideo: false,
      },
    });
    currentSession = session;
    attachSessionHandlers(session);
    return session;
  };

  // Entrante: el asesor contesta. Su clic = pickup.
  const acceptCall = async () => {
    if (!currentSession) return;
    // Bug 1: answer() lanza NOT_SUPPORTED_ERROR en sesiones salientes. Para ellas
    // la conexión ya está en curso por ua.call(); no hay nada que "aceptar".
    if (currentSession.direction === 'outgoing') {
      // eslint-disable-next-line no-console
      console.warn(
        '[SIP] acceptCall() ignorado: sesión saliente ya conectando'
      );
      return;
    }

    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (_) {
      setCallFailure('Mic Denied');
      cleanup();
      throw new Error('Mic Denied');
    }
    localStream = stream;
    currentSession.answer({
      mediaStream: localStream,
      pcConfig: {
        iceServers: credentials?.ice_servers || DEFAULT_ICE_SERVERS,
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require',
      },
    });
    dismissIncomingNotification();
  };

  // Cancela/rechaza la sesión actual:
  // - Saliente no contestada → CANCEL (JsSIP lo hace automáticamente con terminate()).
  // - Entrante              → 486 Busy Here.
  const rejectCall = () => {
    stopRingback();
    if (currentSession) {
      try {
        if (currentSession.direction === 'outgoing') {
          currentSession.terminate();
        } else {
          currentSession.terminate({
            status_code: 486,
            reason_phrase: 'Busy Here',
          });
        }
      } catch (_) {
        /* noop */
      }
    }
    cleanup();
  };

  // Cuelga la llamada activa. Suena feedback inmediato (no esperar el BYE ack).
  // terminate() dispara 'ended' asíncronamente → clearActiveCall limpia el store.
  // cleanup() explícito aquí garantiza que el mic se libera aunque el evento no llegue.
  const endCall = () => {
    stopRingback();
    playHangupSound();
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
    callFailureReason: callFailureReasonReadonly,
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
