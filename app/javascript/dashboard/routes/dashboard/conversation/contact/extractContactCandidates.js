// Heuristicas de extraccion para el modal "crear contacto desde este
// mensaje" (ContactFromMessageModal.vue) -- el patron real detectado en 182+
// chats historicos es que un gestor de EPS/aseguradora (ej. Previser) cita o
// cotiza por un tercero, y a veces menciona su documento/telefono en texto
// libre, sin un formato fijo. Esto es best-effort: el agente SIEMPRE revisa
// y corrige en el formulario antes de crear el contacto, nunca se guarda
// nada sin esa revision.

// Numeros colombianos (celular 3XX, o con +57 / codigo de pais), separados
// por espacios/puntos/guiones opcionales entre grupos.
const PHONE_PATTERN = /(?:\+?57\s?)?3\d{2}[\s.-]?\d{3}[\s.-]?\d{4}/g;

// "CC 123456789", "cedula: 123456789", "documento 123456789" -- 6 a 12
// digitos, con o sin puntos de mil.
const IDENTIFIER_PATTERN =
  /\b(?:c\.?c\.?|c[eé]dula|documento)\.?\s*:?\s*([\d.]{6,15})\b/i;

// "nacio el 10/05/1990", "fecha de nacimiento: 10-05-1990"
const BIRTH_DATE_PATTERN =
  /(?:naci[oó]|fecha de nacimiento)\D{0,15}(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})/i;

// Contact#phone_number exige formato E.164 (ver validacion del modelo) --
// un numero colombiano de 10 digitos sin "+" se vuelve inválido al crear el
// contacto si se manda tal cual. Esta cuenta opera solo en Colombia, asi que
// anteponer +57 es seguro; si ya trae "+" se deja igual.
const normalizePhone = raw => {
  const digitsOnly = raw.replace(/[\s.-]/g, '');
  if (digitsOnly.startsWith('+')) return digitsOnly;
  if (/^57\d{10}$/.test(digitsOnly)) return `+${digitsOnly}`;
  return `+57${digitsOnly}`;
};
const normalizeIdentifier = raw => raw.replace(/\./g, '');

// <input type="date"> exige yyyy-mm-dd -- convierte dd/mm/aaaa (o con
// guiones, o con año de 2 digitos) a eso. Devuelve '' si no se puede
// interpretar con confianza, en vez de adivinar.
export const toIsoDate = ddmmyyyy => {
  if (!ddmmyyyy) return '';

  const [day, month, yearRaw] = ddmmyyyy.split(/[/-]/);
  if (!day || !month || !yearRaw) return '';

  const year = yearRaw.length === 2 ? `19${yearRaw}` : yearRaw;
  const paddedDay = day.padStart(2, '0');
  const paddedMonth = month.padStart(2, '0');
  if (Number(paddedDay) > 31 || Number(paddedMonth) > 12) return '';

  return `${year}-${paddedMonth}-${paddedDay}`;
};

export const extractContactCandidates = text => {
  const content = text || '';

  const phoneMatches = [...content.matchAll(PHONE_PATTERN)].map(match =>
    normalizePhone(match[0])
  );
  const uniquePhones = [...new Set(phoneMatches)];

  const identifierMatch = content.match(IDENTIFIER_PATTERN);
  const birthDateMatch = content.match(BIRTH_DATE_PATTERN);

  return {
    phones: uniquePhones,
    identifier: identifierMatch ? normalizeIdentifier(identifierMatch[1]) : '',
    birthDate: birthDateMatch ? toIsoDate(birthDateMatch[1]) : '',
  };
};
