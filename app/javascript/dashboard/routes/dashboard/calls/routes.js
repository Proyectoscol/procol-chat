import { frontendURL } from '../../../helper/URLHelper';
import CallsPage from './CallsPage.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/calls'),
    name: 'calls_view',
    component: CallsPage,
    meta: {
      permissions: ['administrator', 'agent', 'contact_manage'],
    },
  },
];
