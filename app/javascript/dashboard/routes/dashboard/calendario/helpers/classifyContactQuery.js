// Clasifica lo que se escribio en el buscador de contacto para precargar el
// campo correcto al crear uno nuevo sobre la marcha (patron "no encuentro a
// X, crear contacto nuevo"). Pedido explicito del usuario: si escribe un
// numero de celular colombiano (con o sin +57) deberia ir al campo telefono,
// si escribe cualquier otro numero deberia ir al campo documento, y si
// escribe letras deberia ir al campo nombre -- para ahorrar pasos de
// digitacion.
export const classifyContactQuery = query => {
  const trimmed = (query || '').trim();
  const digitsOnly = trimmed.replace(/\D/g, '');
  const isNumeric = digitsOnly.length > 0 && /^\+?\d+$/.test(trimmed);

  if (!isNumeric) return { name: trimmed };

  const isMobileWithCountryCode =
    digitsOnly.length === 12 && digitsOnly.startsWith('57');
  const isLocalMobile = digitsOnly.length === 10 && digitsOnly.startsWith('3');

  if (isMobileWithCountryCode || isLocalMobile) {
    return {
      phoneNumber: isLocalMobile ? `+57${digitsOnly}` : `+${digitsOnly}`,
    };
  }

  return { identifier: digitsOnly };
};
