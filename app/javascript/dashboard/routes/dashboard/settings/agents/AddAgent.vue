<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useVuelidate } from '@vuelidate/core';
import { required, email, sameAs, minLength } from '@vuelidate/validators';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import MultiInboxCheckboxSelector from 'dashboard/components/widgets/MultiInboxCheckboxSelector.vue';

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const agentName = ref('');
const agentEmail = ref('');
const selectedRoleId = ref('agent');
const avatarFile = ref(null);
const avatarUrl = ref('');
const password = ref('');
const passwordConfirmation = ref('');
const showPassword = ref(false);
const selectedInboxIds = ref([]);

const rules = {
  agentName: { required },
  agentEmail: { required, email },
  selectedRoleId: { required },
  password: { minLength: minLength(6) },
  passwordConfirmation: { sameAsPassword: sameAs(password) },
};

const v$ = useVuelidate(rules, {
  agentName,
  agentEmail,
  selectedRoleId,
  password,
  passwordConfirmation,
});

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');
const inboxes = useMapGetter('inboxes/getInboxes');
// Un admin restringido a inbox(es) nunca puede crear otro administrator
// (ver AccountUser#inbox_restricted? y la regla D1 del backend) -- se oculta
// la opcion en vez de dejarla y que el servidor la rechace sin explicacion.
const currentUserInboxRestricted = useMapGetter(
  'getCurrentUserInboxRestricted'
);

const roles = computed(() => {
  const defaultRoles = currentUserInboxRestricted.value
    ? []
    : [
        {
          id: 'administrator',
          name: 'administrator',
          label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
        },
      ];
  defaultRoles.push({
    id: 'agent',
    name: 'agent',
    label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
  });

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

const isAdministratorRole = computed(
  () => selectedRole.value?.name === 'administrator'
);

const handleImageUpload = ({ file, url }) => {
  avatarFile.value = file;
  avatarUrl.value = url;
};

const handleAvatarDelete = () => {
  avatarFile.value = null;
  avatarUrl.value = '';
};

const addAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      name: agentName.value,
      email: agentEmail.value,
    };

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
    }

    if (avatarFile.value) {
      payload.avatar = avatarFile.value;
    }

    // Opcional: deja la contrasena vacia y se usa el flujo normal de
    // invitacion por correo (ver AgentBuilder) -- se asigna directo solo si
    // el admin la escribe aqui, para agentes sin email funcional.
    if (password.value) {
      payload.password = password.value;
    }

    if (isAdministratorRole.value && selectedInboxIds.value.length) {
      payload.restricted_inbox_ids = selectedInboxIds.value;
    }

    await store.dispatch('agents/create', payload);
    useAlert(t('AGENT_MGMT.ADD.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    const {
      response: {
        data: {
          error: errorResponse = '',
          attributes: attributes = [],
          message: attrError = '',
        } = {},
      } = {},
    } = error;

    let errorMessage = '';
    if (error?.response?.status === 422 && !attributes.includes('base')) {
      errorMessage = t('AGENT_MGMT.ADD.API.EXIST_MESSAGE');
    } else {
      errorMessage = t('AGENT_MGMT.ADD.API.ERROR_MESSAGE');
    }
    useAlert(errorResponse || attrError || errorMessage);
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="$t('AGENT_MGMT.ADD.TITLE')"
      :header-content="$t('AGENT_MGMT.ADD.DESC')"
    />
    <form class="flex flex-col items-start w-full" @submit.prevent="addAgent">
      <div class="w-full mb-4 flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_MGMT.AVATAR.LABEL') }}
        </span>
        <Avatar
          :src="avatarUrl"
          :name="agentName"
          :size="56"
          allow-upload
          @upload="handleImageUpload"
          @delete="handleAvatarDelete"
        />
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.ADD.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.ADD.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.ADD.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.ADD.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentEmail.$error }">
          {{ $t('AGENT_MGMT.ADD.FORM.EMAIL.LABEL') }}
          <input
            v-model="agentEmail"
            type="email"
            :placeholder="$t('AGENT_MGMT.ADD.FORM.EMAIL.PLACEHOLDER')"
            @input="v$.agentEmail.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.password.$error }">
          {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD.LABEL') }}
          <div class="flex items-center gap-2">
            <input
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              autocomplete="new-password"
              :placeholder="$t('AGENT_MGMT.ADD.FORM.PASSWORD.PLACEHOLDER')"
              class="!mb-0"
              @input="v$.password.$touch"
            />
            <Button
              type="button"
              :icon="showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              slate
              faded
              @click="showPassword = !showPassword"
            />
          </div>
          <span v-if="v$.password.$error" class="message">
            {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD.ERROR') }}
          </span>
          <p v-else-if="password" class="text-xs text-n-slate-11 mt-1">
            {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD.HINT') }}
          </p>
        </label>
      </div>

      <div v-if="password" class="w-full">
        <label :class="{ error: v$.passwordConfirmation.$error }">
          {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD_CONFIRMATION.LABEL') }}
          <input
            v-model="passwordConfirmation"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="new-password"
            :placeholder="
              $t('AGENT_MGMT.ADD.FORM.PASSWORD_CONFIRMATION.PLACEHOLDER')
            "
            @input="v$.passwordConfirmation.$touch"
          />
          <span v-if="v$.passwordConfirmation.$error" class="message">
            {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD_CONFIRMATION.ERROR') }}
          </span>
        </label>
      </div>

      <MultiInboxCheckboxSelector
        v-if="isAdministratorRole"
        v-model="selectedInboxIds"
        :inboxes="inboxes"
        :label="$t('AGENT_MGMT.ADD.FORM.RESTRICTED_INBOXES.LABEL')"
        :hint="$t('AGENT_MGMT.ADD.FORM.RESTRICTED_INBOXES.HINT')"
      />

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <Button
          faded
          slate
          type="reset"
          :label="$t('AGENT_MGMT.ADD.CANCEL_BUTTON_TEXT')"
          @click.prevent="emit('close')"
        />
        <Button
          type="submit"
          :label="$t('AGENT_MGMT.ADD.FORM.SUBMIT')"
          :disabled="v$.$invalid || uiFlags.isCreating"
          :is-loading="uiFlags.isCreating"
        />
      </div>
    </form>
  </div>
</template>
