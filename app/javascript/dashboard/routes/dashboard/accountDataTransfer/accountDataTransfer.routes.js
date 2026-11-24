import { frontendURL } from 'dashboard/helper/URLHelper.js';

import AccountDataTransferPage from './pages/AccountDataTransferPage.vue';

const accountDataTransferRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/account-data-transfer'),
      name: 'account_data_transfer_index',
      meta: { permissions: ['administrator'] },
      component: AccountDataTransferPage,
    },
  ],
};

export default accountDataTransferRoutes;
