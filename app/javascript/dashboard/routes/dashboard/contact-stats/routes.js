import { frontendURL } from '../../../helper/URLHelper';
import { LEAD_STATS_PERMISSIONS } from 'dashboard/constants/permissions.js';
import ContactStatsIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contact-stats'),
    name: 'contact_stats_view',
    component: ContactStatsIndex,
    meta: {
      permissions: ['administrator', LEAD_STATS_PERMISSIONS],
    },
  },
];
