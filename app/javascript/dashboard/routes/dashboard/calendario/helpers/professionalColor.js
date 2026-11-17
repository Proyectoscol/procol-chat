// Paleta fija por profesional -- a diferencia del Servicio (que ya tiene un
// color propio guardado en la base, editable en /calendario/services), el
// profesional no tiene un campo de color: se asigna de forma determinista
// por posicion en la lista para que cada uno SIEMPRE caiga en el mismo
// color mientras no cambie el orden de profesionales activos, sin tener
// que migrar el modelo para esto.
const PALETTE = [
  '#4F81BD', // azul
  '#C0504D', // rojo
  '#9BBB59', // verde
  '#8064A2', // morado
  '#F79646', // naranja
  '#4BACC6', // cian
  '#C3D69B', // verde claro
  '#D99694', // rosa
  '#808080', // gris (respaldo si hay mas profesionales que colores)
];

export const professionalColor = (professionalId, professionals) => {
  const index = professionals.findIndex(p => p.id === professionalId);
  if (index === -1) return PALETTE[PALETTE.length - 1];
  return PALETTE[index % PALETTE.length];
};

// Blanco o negro segun el contraste del fondo -- evita texto ilegible
// cuando el color de fondo es claro (ej. el verde #9BBB59 con texto blanco
// se lee mal).
export const readableTextColor = hexColor => {
  const hex = hexColor.replace('#', '');
  if (hex.length !== 6) return '#000000';
  const r = parseInt(hex.slice(0, 2), 16);
  const g = parseInt(hex.slice(2, 4), 16);
  const b = parseInt(hex.slice(4, 6), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.6 ? '#000000' : '#ffffff';
};
