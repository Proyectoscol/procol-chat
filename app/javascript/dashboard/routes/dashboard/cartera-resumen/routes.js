import { frontendURL } from '../../../helper/URLHelper';
import CarteraResumenIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cartera/resumen'),
    name: 'cartera_resumen_view',
    component: CarteraResumenIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
