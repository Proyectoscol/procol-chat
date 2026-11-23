import { frontendURL } from 'dashboard/helper/URLHelper.js';

import MensajeriaPageRouteView from './MensajeriaPageRouteView.vue';
import CalendarioNotificationsPage from '../../calendario/pages/CalendarioNotificationsPage.vue';
import CalendarioWelcomeBotFlowsPage from '../../calendario/pages/CalendarioWelcomeBotFlowsPage.vue';
import CalendarioTemplateLibraryPage from '../../calendario/pages/CalendarioTemplateLibraryPage.vue';
import CalendarioReturningAppointmentPromptPage from '../../calendario/pages/CalendarioReturningAppointmentPromptPage.vue';

const adminMeta = { permissions: ['administrator'] };

const mensajeriaRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/mensajeria'),
      component: MensajeriaPageRouteView,
      children: [
        {
          path: '',
          redirect: to => ({
            name: 'mensajeria_notifications_index',
            params: to.params,
          }),
        },
        {
          path: 'notifications',
          name: 'mensajeria_notifications_index',
          meta: adminMeta,
          component: CalendarioNotificationsPage,
        },
        {
          path: 'welcome-bot',
          name: 'mensajeria_welcome_bot_flows_index',
          meta: adminMeta,
          component: CalendarioWelcomeBotFlowsPage,
        },
        {
          path: 'templates',
          name: 'mensajeria_message_templates_index',
          meta: adminMeta,
          component: CalendarioTemplateLibraryPage,
        },
        {
          path: 'returning-appointment-prompt',
          name: 'mensajeria_returning_appointment_prompt_index',
          meta: adminMeta,
          component: CalendarioReturningAppointmentPromptPage,
        },
      ],
    },
  ],
};

export default mensajeriaRoutes;
