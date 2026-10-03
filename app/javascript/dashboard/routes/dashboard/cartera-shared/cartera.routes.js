import { frontendURL } from '../../../helper/URLHelper';
import CarteraWrapper from './CarteraWrapper.vue';
import CarteraResumenIndex from '../cartera-resumen/Index.vue';
import ClientesIndex from '../clientes/Index.vue';
import ClientesFicha from '../clientes/Ficha.vue';
import FacturasIndex from '../facturas/Index.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/cartera'),
    component: CarteraWrapper,
    children: [
      {
        path: 'resumen',
        name: 'cartera_resumen_view',
        meta,
        component: CarteraResumenIndex,
      },
      {
        path: 'clientes',
        name: 'cartera_clientes_view',
        meta,
        component: ClientesIndex,
      },
      {
        path: 'clientes/:clienteId',
        name: 'cartera_clientes_ficha_view',
        meta,
        component: ClientesFicha,
      },
      {
        path: 'facturas',
        name: 'cartera_facturas_view',
        meta,
        component: FacturasIndex,
      },
    ],
  },
];
