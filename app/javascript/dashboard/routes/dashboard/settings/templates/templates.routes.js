import { frontendURL } from '../../../../helper/URLHelper';

// WhatsApp template management lives under Cartera > Campañas > Plantillas
// now (one unified page instead of two) - this route only exists so old
// links/bookmarks to /settings/templates keep working.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/templates'),
      redirect: to => ({ name: 'cartera_plantillas_view', params: to.params }),
    },
  ],
};
