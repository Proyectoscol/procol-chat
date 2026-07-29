import { frontendURL } from '../../../helper/URLHelper';
import AgentLockIndex from './Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/agent-lock'),
    name: 'agent_lock_view',
    component: AgentLockIndex,
    meta: {
      permissions: ['administrator'],
    },
  },
];
