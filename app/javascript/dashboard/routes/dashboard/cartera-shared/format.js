export const formatearCop = valor =>
  new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency: 'COP',
    maximumFractionDigits: 0,
  }).format(Number(valor) || 0);

export const formatearFecha = iso =>
  iso
    ? new Intl.DateTimeFormat('es-CO', { dateStyle: 'medium' }).format(
        new Date(iso)
      )
    : '—';
