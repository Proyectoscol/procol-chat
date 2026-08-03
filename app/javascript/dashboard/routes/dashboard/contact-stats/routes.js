import { frontendURL } from '../../../helper/URLHelper';
import ContactStatsIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contact-stats'),
    name: 'contact_stats_view',
    component: ContactStatsIndex,
    meta: {
      permissions: ['administrator'],
    },
  },
];
