import { frontendURL } from '../../../helper/URLHelper';
import ClientesIndex from './Index.vue';
import ClientesFicha from './Ficha.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cartera/clientes'),
    name: 'cartera_clientes_view',
    component: ClientesIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/cartera/clientes/:clienteId'),
    name: 'cartera_clientes_ficha_view',
    component: ClientesFicha,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
