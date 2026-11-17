// El estado de una cita es un selector unico (no una fila de botones) --
// pedido explicito del usuario: "los estados son confirmar, no asistio,
// cancelar y pendiente [...] necesito que en accion me quede mas bien un
// selector unico con el estado". Reagendar NO es un estado, es una accion
// aparte que siempre queda visible junto al selector.
//
// Orden y color son UNICOS para todo el modulo -- cualquier lugar que
// muestre el estado de una cita (Citas, Agenda, Contacto, conversacion,
// detalle) usa este mismo orden y el mismo color de fondo para que el
// personal reconozca el estado de un vistazo sin importar donde este.
export const APPOINTMENT_STATUSES = [
  'pending',
  'confirmed',
  'attended',
  'no_show',
  'cancelled',
];

// Opciones para el <Select> de estado -- requiere `t` porque las etiquetas
// vienen de i18n (CALENDARIO.APPOINTMENTS.STATUS.*).
export const statusSelectOptions = t =>
  APPOINTMENT_STATUSES.map(status => ({
    value: status,
    label: t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`),
  }));

// Color de fondo de la fila/tarjeta completa segun el estado elegido en el
// selector -- pedido explicito: "el color de la tarjeta de la cita es el
// que refleja el estado". Pendiente no se resalta (es el estado neutro de
// partida). Atendida usa un verde deliberadamente mas vivo/neon que
// Confirmada para que ambos "verdes" se distingan de un vistazo (no hay un
// segundo tono de verde en los tokens `n-*` del design system, por eso se
// usan valores hexadecimales explicitos aqui en vez de un token de color).
export const STATUS_ROW_BACKGROUND_CLASS = {
  pending: '',
  confirmed: 'bg-[#22c55e]/15 dark:bg-[#22c55e]/25',
  attended: 'bg-[#39ff14]/25 dark:bg-[#39ff14]/30',
  no_show: 'bg-n-amber-2 dark:bg-n-amber-3',
  cancelled: 'bg-n-ruby-2 dark:bg-n-ruby-3',
};

export const statusRowBackgroundClass = status =>
  STATUS_ROW_BACKGROUND_CLASS[status] || '';

// FullCalendar siempre fija el color de cada evento como estilo inline (no
// clases), asi que ahi una clase de Tailwind como las de arriba nunca gana
// la especificidad -- se necesitan colores resueltos en vez de tokens.
export const STATUS_EVENT_COLOR = {
  pending: { background: 'transparent', border: 'transparent' },
  confirmed: { background: 'rgba(34, 197, 94, 0.18)', border: '#22c55e' },
  attended: { background: 'rgba(57, 255, 20, 0.3)', border: '#39ff14' },
  no_show: { background: 'rgba(234, 179, 8, 0.25)', border: '#eab308' },
  cancelled: { background: 'rgba(239, 68, 68, 0.2)', border: '#ef4444' },
};

export const statusEventColor = status =>
  STATUS_EVENT_COLOR[status] || STATUS_EVENT_COLOR.pending;

export const RESCHEDULE_ACTION = {
  labelKey: 'CALENDARIO.APPOINTMENTS.ACTIONS.RESCHEDULE',
  color: 'blue',
  icon: 'i-lucide-calendar-clock',
};

// Estetica unica del boton de Reagendar: variante "faded" (fondo tenue, sin
// solido) + letra negra fija (no el color propio de la variante) + borde
// sutil del mismo color -- pedido explicito del usuario de "algo elegante,
// transparentoso, no solido".
export const ACTION_BUTTON_VARIANT = 'faded';
export const ACTION_BUTTON_CLASS = '!text-n-slate-12 border border-n-weak';

export const rescheduleCountLabel = (t, count) =>
  count === 1
    ? t('CALENDARIO.APPOINTMENTS.RESCHEDULE.COUNT_ONE')
    : t('CALENDARIO.APPOINTMENTS.RESCHEDULE.COUNT_OTHER', { count });
