// Config de idioma para vue-datepicker-next (el mismo componente ya usado en
// produccion por CustomSnoozeModal). La forma "formatLocale" anidada es la
// que la libreria realmente usa para el encabezado mes/anio -- copiada de su
// propio node_modules/vue-datepicker-next/locale/es.js (ese archivo es un
// bundle UMD pensado para <script> global, no para import ESM de Vite, por
// eso se define en linea en vez de importarlo).
const formatLocale = {
  months: [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ],
  monthsShort: [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ],
  weekdays: [
    'domingo',
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
  ],
  weekdaysShort: ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'],
  weekdaysMin: ['do', 'lu', 'ma', 'mi', 'ju', 'vi', 'sá'],
  firstDayOfWeek: 1,
  firstWeekContainsDate: 1,
};

export const ES_DATEPICKER_LANG = {
  formatLocale,
  yearFormat: 'YYYY',
  monthFormat: 'MMMM',
  monthBeforeYear: true,
};
