// El consultorio opera en Colombia -- toda fecha/hora de Calendario se
// muestra en es-CO y America/Bogota explicitos, sin importar en que zona
// horaria corra el navegador (el servidor local de pruebas puede estar en
// cualquier otra). Usar `undefined` como locale (como hacia el resto del
// codebase) deja que el idioma del sistema operativo decida -- por eso dias
// y meses aparecian en ingles en maquinas con el SO en ingles.
export const COLOMBIA_TIME_ZONE = 'America/Bogota';
const LOCALE = 'es-CO';

// OpenDay#date (y cualquier "YYYY-MM-DD" de un <input type="date">) es una
// fecha pura, sin hora real -- se ancla a mediodia UTC antes de formatear en
// America/Bogota (UTC-5 -> 7am) para que SIEMPRE caiga en el mismo dia
// calendario, sin el bug ya conocido de interpretar "YYYY-MM-DD" como
// medianoche UTC (que en Bogota cae en el dia anterior).
const anchorDateOnly = dateString => {
  const [y, m, d] = dateString.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12));
};

export const formatDateOnlyEs = (dateString, options = {}) =>
  anchorDateOnly(dateString).toLocaleDateString(LOCALE, {
    timeZone: COLOMBIA_TIME_ZONE,
    ...options,
  });

export const formatInstantDateEs = (isoString, options = {}) =>
  new Date(isoString).toLocaleDateString(LOCALE, {
    timeZone: COLOMBIA_TIME_ZONE,
    ...options,
  });

// 24h (sin a. m./p. m.) a proposito -- pedido explicito del usuario: ancho
// fijo tipo Excel en las tablas de citas, y "a. m."/"p. m." hace que la
// columna de hora varie de ancho (o se parta en dos lineas) segun el caso.
export const formatInstantTimeEs = isoString =>
  new Date(isoString).toLocaleTimeString(LOCALE, {
    timeZone: COLOMBIA_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

export const formatInstantDateTimeEs = isoString =>
  new Date(isoString).toLocaleString(LOCALE, {
    timeZone: COLOMBIA_TIME_ZONE,
    dateStyle: 'medium',
    timeStyle: 'short',
  });

// "YYYY-MM-DD" de un instante ISO, expresado en hora de Bogota -- para
// comparar un Appointment#starts_at contra un OpenDay#date (ya un string
// "YYYY-MM-DD" literal).
export const dateKeyInColombia = isoString => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: COLOMBIA_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(isoString));
  const lookup = Object.fromEntries(parts.map(p => [p.type, p.value]));
  return `${lookup.year}-${lookup.month}-${lookup.day}`;
};
