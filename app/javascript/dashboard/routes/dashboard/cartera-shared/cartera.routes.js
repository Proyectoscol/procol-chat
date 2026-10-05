import { frontendURL } from '../../../helper/URLHelper';
import CarteraWrapper from './CarteraWrapper.vue';
import CarteraResumenIndex from '../cartera-resumen/Index.vue';
import ClientesIndex from '../clientes/Index.vue';
import ClientesFicha from '../clientes/Ficha.vue';
import FacturasIndex from '../facturas/Index.vue';
import FacturasFicha from '../facturas/Ficha.vue';
import PlantillasIndex from '../plantillas/Index.vue';
import CampanasIndex from '../campanas/Index.vue';
import CampanaDetalle from '../campanas/Detalle.vue';
import AjustesIndex from '../cartera-ajustes/Index.vue';

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
      {
        path: 'facturas/:facturaId',
        name: 'cartera_facturas_ficha_view',
        meta,
        component: FacturasFicha,
      },
      {
        path: 'plantillas',
        name: 'cartera_plantillas_view',
        meta,
        component: PlantillasIndex,
      },
      {
        path: 'campanas',
        name: 'cartera_campanas_view',
        meta,
        component: CampanasIndex,
      },
      {
        path: 'campanas/:campanaId',
        name: 'cartera_campana_detail_view',
        meta,
        component: CampanaDetalle,
      },
      {
        path: 'ajustes',
        name: 'cartera_ajustes_view',
        meta,
        component: AjustesIndex,
      },
    ],
  },
];
