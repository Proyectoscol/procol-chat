import { frontendURL } from 'dashboard/helper/URLHelper.js';

import CalendarioPageRouteView from './pages/CalendarioPageRouteView.vue';
import CalendarioAgendaPage from './pages/CalendarioAgendaPage.vue';
import CalendarioCalendarPage from './pages/CalendarioCalendarPage.vue';
import CalendarioSchedulesPage from './pages/CalendarioSchedulesPage.vue';
import CalendarioProfessionalsPage from './pages/CalendarioProfessionalsPage.vue';
import CalendarioSpecialtiesPage from './pages/CalendarioSpecialtiesPage.vue';
import CalendarioServicesPage from './pages/CalendarioServicesPage.vue';
import CalendarioPayersPage from './pages/CalendarioPayersPage.vue';
import CalendarioStatsPage from './pages/CalendarioStatsPage.vue';
import CalendarioNotificationsPage from './pages/CalendarioNotificationsPage.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};
const adminMeta = { permissions: ['administrator'] };

const calendarioRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/calendario'),
      component: CalendarioPageRouteView,
      children: [
        {
          path: '',
          redirect: to => ({
            name: 'calendario_agenda_index',
            params: to.params,
          }),
        },
        {
          path: 'agenda',
          name: 'calendario_agenda_index',
          meta,
          component: CalendarioAgendaPage,
        },
        {
          path: 'calendar',
          name: 'calendario_calendar_index',
          meta,
          component: CalendarioCalendarPage,
        },
        {
          path: 'schedules',
          name: 'calendario_schedules_index',
          meta,
          component: CalendarioSchedulesPage,
        },
        {
          path: 'specialties',
          name: 'calendario_specialties_index',
          meta: adminMeta,
          component: CalendarioSpecialtiesPage,
        },
        {
          path: 'professionals',
          name: 'calendario_professionals_index',
          meta: adminMeta,
          component: CalendarioProfessionalsPage,
        },
        {
          path: 'services',
          name: 'calendario_services_index',
          meta: adminMeta,
          component: CalendarioServicesPage,
        },
        {
          path: 'payers',
          name: 'calendario_payers_index',
          meta: adminMeta,
          component: CalendarioPayersPage,
        },
        {
          path: 'stats',
          name: 'calendario_stats_index',
          meta,
          component: CalendarioStatsPage,
        },
        {
          path: 'notifications',
          name: 'calendario_notifications_index',
          meta: adminMeta,
          component: CalendarioNotificationsPage,
        },
      ],
    },
  ],
};

export default calendarioRoutes;
