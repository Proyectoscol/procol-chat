// Paleta categorica validada (skill dataviz) -- orden fijo, nunca se
// reordena, para que el color de una categoria no cambie segun que otras
// esten visibles. Compartida entre CategoryMentionsChart (lineas de
// tiempo) y CategoryBreakdownPieChart (gajos de subcategoria) para que
// ambas vistas se sientan parte del mismo sistema visual.
export const AUDITORIA_CATEGORY_PALETTE = [
  { light: '#2a78d6', dark: '#3987e5' },
  { light: '#eb6834', dark: '#d95926' },
  { light: '#1baf7a', dark: '#199e70' },
  { light: '#eda100', dark: '#c98500' },
  { light: '#e87ba4', dark: '#d55181' },
  { light: '#008300', dark: '#008300' },
  { light: '#4a3aa7', dark: '#9085e9' },
  { light: '#e34948', dark: '#e66767' },
];

export const colorForIndex = index =>
  AUDITORIA_CATEGORY_PALETTE[index % AUDITORIA_CATEGORY_PALETTE.length];
