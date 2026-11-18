// Reemplazo casero de lo que @fullcalendar/resource-timegrid hace con
// licencia paga: calcula la posicion (top/left/height/width en %) de cada
// cita dentro de una columna de dia, incluyendo el reparto lado-a-lado de
// citas que se superponen en el tiempo para el MISMO profesional (mismo
// criterio visual que usa Google Calendar).
export const DAY_START_HOUR = 6;
export const DAY_END_HOUR = 19;
export const TOTAL_MINUTES = (DAY_END_HOUR - DAY_START_HOUR) * 60;

const minutesFromDayStart = date => {
  const minutes = (date.getHours() - DAY_START_HOUR) * 60 + date.getMinutes();
  return Math.min(Math.max(minutes, 0), TOTAL_MINUTES);
};

// Agrupa eventos superpuestos en "clusters" (si A se cruza con B y B con C,
// los 3 van en el mismo cluster aunque A y C no se crucen entre si) y
// dentro de cada cluster asigna cada evento a la primera columna libre
// (algoritmo greedy estandar para este problema) -- asi el ancho se reparte
// solo entre los que realmente compiten por el mismo espacio.
export const layoutDayEvents = events => {
  const sorted = [...events].sort(
    (a, b) => new Date(a.start) - new Date(b.start)
  );

  const clusters = [];
  let current = [];
  let clusterEnd = -Infinity;

  sorted.forEach(event => {
    const start = new Date(event.start).getTime();
    const end = new Date(event.end).getTime();
    if (current.length && start >= clusterEnd) {
      clusters.push(current);
      current = [];
      clusterEnd = -Infinity;
    }
    current.push(event);
    clusterEnd = Math.max(clusterEnd, end);
  });
  if (current.length) clusters.push(current);

  const positioned = [];
  clusters.forEach(cluster => {
    const columnEnds = [];
    const columnByEventId = new Map();

    cluster.forEach(event => {
      const start = new Date(event.start).getTime();
      const end = new Date(event.end).getTime();
      const columnIndex = columnEnds.findIndex(lastEnd => lastEnd <= start);
      if (columnIndex === -1) {
        columnEnds.push(end);
        columnByEventId.set(event.id, columnEnds.length - 1);
      } else {
        columnEnds[columnIndex] = end;
        columnByEventId.set(event.id, columnIndex);
      }
    });

    const columnCount = columnEnds.length;
    cluster.forEach(event => {
      const top =
        (minutesFromDayStart(new Date(event.start)) / TOTAL_MINUTES) * 100;
      const bottom =
        (minutesFromDayStart(new Date(event.end)) / TOTAL_MINUTES) * 100;
      const columnIndex = columnByEventId.get(event.id);
      positioned.push({
        ...event,
        topPct: top,
        heightPct: Math.max(bottom - top, 1.5),
        leftPct: (columnIndex / columnCount) * 100,
        widthPct: 100 / columnCount,
      });
    });
  });

  return positioned;
};

export const isSameDay = (a, b) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

// Minutos desde medianoche -> fecha real del dia dado, redondeado a los 15
// min mas cercanos (mismo "snap" que slotDuration en FullCalendar).
export const dateFromDayOffset = (day, offsetMinutesFromStart) => {
  const rounded = Math.round(offsetMinutesFromStart / 15) * 15;
  const date = new Date(day);
  date.setHours(DAY_START_HOUR, 0, 0, 0);
  date.setMinutes(date.getMinutes() + rounded);
  return date;
};
