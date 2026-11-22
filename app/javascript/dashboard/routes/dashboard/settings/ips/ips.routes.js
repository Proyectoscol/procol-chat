import { frontendURL } from 'dashboard/helper/URLHelper.js';

import IpsPageRouteView from './IpsPageRouteView.vue';
import CalendarioSpecialtiesPage from '../../calendario/pages/CalendarioSpecialtiesPage.vue';
import CalendarioProfessionalsPage from '../../calendario/pages/CalendarioProfessionalsPage.vue';
import CalendarioServicesPage from '../../calendario/pages/CalendarioServicesPage.vue';
import CalendarioPayersPage from '../../calendario/pages/CalendarioPayersPage.vue';

const adminMeta = { permissions: ['administrator'] };

const ipsRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/ips'),
      component: IpsPageRouteView,
      children: [
        {
          path: '',
          redirect: to => ({
            name: 'ips_specialties_index',
            params: to.params,
          }),
        },
        {
          path: 'specialties',
          name: 'ips_specialties_index',
          meta: adminMeta,
          component: CalendarioSpecialtiesPage,
        },
        {
          path: 'professionals',
          name: 'ips_professionals_index',
          meta: adminMeta,
          component: CalendarioProfessionalsPage,
        },
        {
          path: 'services',
          name: 'ips_services_index',
          meta: adminMeta,
          component: CalendarioServicesPage,
        },
        {
          path: 'payers',
          name: 'ips_payers_index',
          meta: adminMeta,
          component: CalendarioPayersPage,
        },
      ],
    },
  ],
};

export default ipsRoutes;
