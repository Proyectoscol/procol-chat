// Duracion por defecto de una cita -- bug real 2026-11-26: el servicio
// "Consulta" (compartido por Urologia y Ginecologia) tenia una sola
// duracion fija para cualquier profesional y forma de pago. Mismo patron de
// fallback que el precio (service.price_for en el backend): override por
// profesional+EPS/particular -> duration_minutes fijo del servicio.
export const MIN_DURATION_MINUTES = 5;
export const MAX_DURATION_MINUTES = 60;
export const DURATION_STEP_MINUTES = 5;

export function defaultDurationMinutes(service, professionalId, payerKind) {
  if (!service) return MIN_DURATION_MINUTES;

  const link = (service.service_professionals || []).find(
    sp => sp.professional_id === professionalId
  );
  if (!link) return service.duration_minutes || MIN_DURATION_MINUTES;

  const override =
    payerKind === 'eps'
      ? link.eps_duration_minutes
      : link.private_duration_minutes;
  return override || service.duration_minutes || MIN_DURATION_MINUTES;
}

export function clampDurationMinutes(minutes) {
  return Math.min(
    MAX_DURATION_MINUTES,
    Math.max(MIN_DURATION_MINUTES, minutes)
  );
}
