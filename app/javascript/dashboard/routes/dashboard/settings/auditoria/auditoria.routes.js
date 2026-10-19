import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import AiFieldConfigsIndex from './AiFieldConfigsIndex.vue';

export default {
  routes: [
    {
      path: frontendURL(
        'accounts/:accountId/settings/auditoria/ai-field-configs'
      ),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'auditoria_ai_field_configs',
          component: AiFieldConfigsIndex,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
