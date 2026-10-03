import { frontendURL } from '../../../helper/URLHelper';
import ClientesIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cartera/clientes'),
    name: 'cartera_clientes_view',
    component: ClientesIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
