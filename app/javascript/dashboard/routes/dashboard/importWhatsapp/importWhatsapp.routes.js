import { frontendURL } from 'dashboard/helper/URLHelper.js';

import ImportWhatsappChatPage from './pages/ImportWhatsappChatPage.vue';

const importWhatsappRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/import-whatsapp'),
      name: 'import_whatsapp_chat_index',
      meta: { permissions: ['administrator'] },
      component: ImportWhatsappChatPage,
    },
  ],
};

export default importWhatsappRoutes;
