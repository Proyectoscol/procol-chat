import camelcaseKeys from 'camelcase-keys';

export const getters = {
  getContacts($state) {
    return $state.sortOrder.map(contactId => $state.records[contactId]);
  },
  getContactsList($state) {
    const contacts = $state.sortOrder.map(
      contactId => $state.records[contactId]
    );
    // stopPaths: igual que getContactById -- custom_attributes son claves
    // definidas por el backend (ej. date_of_birth), no deben camelcasearse
    // o un formulario que lea/escriba esa clave queda inconsistente segun
    // desde que getter llego el contacto (bug real encontrado: la fecha de
    // nacimiento se veia vacia al editar desde la lista de Contactos).
    return camelcaseKeys(contacts, {
      deep: true,
      stopPaths: ['custom_attributes'],
    });
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getContact: $state => id => {
    const contact = $state.records[id];
    return contact || {};
  },
  getContactById: $state => id => {
    const contact = $state.records[id];
    return camelcaseKeys(contact || {}, {
      deep: true,
      stopPaths: ['custom_attributes'],
    });
  },
  getMeta: $state => {
    return $state.meta;
  },
  getAppliedContactFilters: _state => {
    return _state.appliedFilters;
  },
  getAppliedContactFiltersV4: _state => {
    return _state.appliedFilters.map(camelcaseKeys);
  },
};
