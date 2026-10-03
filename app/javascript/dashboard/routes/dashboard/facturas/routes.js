import { frontendURL } from '../../../helper/URLHelper';
import FacturasIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cartera/facturas'),
    name: 'cartera_facturas_view',
    component: FacturasIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
