// Las filas de Agendas/Agenda de hoy son angostas y ya muestran telefono +
// documento + EPS en la misma linea -- "Cédula de ciudadanía" ocupaba
// demasiado espacio y se confundia visualmente con el numero de telefono de
// al lado. Pedido explicito del usuario: usar la sigla (coincide con el
// valor real del enum document_type: 'cc', 'ti', 'ce', 'pa', 'rc', 'pep',
// 'ppt') en mayuscula + un punto, para separarla claramente del numero de
// documento que la sigue (ej. "CC. 24767673").
export const documentTypeAbbreviation = documentType =>
  documentType ? `${documentType.toUpperCase()}.` : '';
