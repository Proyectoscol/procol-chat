import { frontendURL } from 'dashboard/helper/URLHelper.js';

import CalendarioPageRouteView from './pages/CalendarioPageRouteView.vue';
import CalendarioAgendaPage from './pages/CalendarioAgendaPage.vue';
import CalendarioCalendarPage from './pages/CalendarioCalendarPage.vue';
import CalendarioSchedulesPage from './pages/CalendarioSchedulesPage.vue';
import CalendarioStatsPage from './pages/CalendarioStatsPage.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

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
          path: 'stats',
          name: 'calendario_stats_index',
          meta,
          component: CalendarioStatsPage,
        },
      ],
    },
  ],
};

export default calendarioRoutes;
