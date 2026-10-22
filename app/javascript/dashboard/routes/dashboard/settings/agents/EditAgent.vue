<script setup>
import { ref, computed } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, sameAs } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
  thumbnail: {
    type: String,
    default: '',
  },
  restrictedInboxIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const { t } = useI18n();

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const selectedRoleId = ref(props.customRoleId || props.type);
const avatarFile = ref(null);
const avatarUrl = ref(props.thumbnail);
const selectedInboxIds = ref([...props.restrictedInboxIds]);
const showPasswordField = ref(false);
const newPassword = ref('');
const newPasswordConfirmation = ref('');
const showPassword = ref(false);
const isResettingPassword = ref(false);

const rules = {
  agentName: { required, minLength: minLength(1) },
  selectedRoleId: { required },
  agentAvailability: { required },
  newPassword: { minLength: minLength(6) },
  newPasswordConfirmation: { sameAsPassword: sameAs(newPassword) },
};

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
  newPassword,
  newPasswordConfirmation,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');
const inboxes = useMapGetter('inboxes/getInboxes');
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

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const availabilityStatuses = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    disabled: props.availability === AVAILABILITY_STATUS_KEYS[index],
  }))
);

const handleImageUpload = ({ file, url }) => {
  avatarFile.value = file;
  avatarUrl.value = url;
};

const handleAvatarDelete = async () => {
  try {
    await store.dispatch('agents/deleteAgentAvatar', props.id);
    avatarFile.value = null;
    avatarUrl.value = '';
    useAlert(t('AGENT_MGMT.AVATAR.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.AVATAR.DELETE_ERROR'));
  }
};

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      id: props.id,
      name: agentName.value,
      availability: agentAvailability.value,
    };

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
      payload.custom_role_id = null;
    }

    if (isAdministratorRole.value) {
      payload.restricted_inbox_ids = selectedInboxIds.value;
    }

    if (avatarFile.value) {
      payload.avatar = avatarFile.value;
    }

    await store.dispatch('agents/update', payload);
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  v$.value.newPassword.$touch();
  v$.value.newPasswordConfirmation.$touch();
  if (
    v$.value.newPassword.$invalid ||
    v$.value.newPasswordConfirmation.$invalid
  ) {
    return;
  }

  isResettingPassword.value = true;
  try {
    await store.dispatch('agents/resetPassword', {
      id: props.id,
      password: newPassword.value,
    });
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
    showPasswordField.value = false;
    newPassword.value = '';
    newPasswordConfirmation.value = '';
  } catch (error) {
    const message = error?.response?.data?.message;
    useAlert(message || t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  } finally {
    isResettingPassword.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
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
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <select
            v-model="agentAvailability"
            @change="v$.agentAvailability.$touch"
          >
            <option
              v-for="status in availabilityStatuses"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
        </label>
      </div>

      <div v-if="isAdministratorRole" class="w-full mb-4">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_MGMT.EDIT.FORM.RESTRICTED_INBOXES.LABEL') }}
        </span>
        <p class="text-xs text-n-slate-11 mb-2">
          {{ $t('AGENT_MGMT.EDIT.FORM.RESTRICTED_INBOXES.HINT') }}
        </p>
        <div class="flex flex-col gap-1.5">
          <label
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="flex items-center gap-2 cursor-pointer"
          >
            <input
              v-model="selectedInboxIds"
              type="checkbox"
              :value="inbox.id"
            />
            <span class="text-sm text-n-slate-11">{{ inbox.name }}</span>
          </label>
        </div>
      </div>

      <div v-if="provider !== 'saml'" class="w-full mb-4">
        <Button
          v-if="!showPasswordField"
          ghost
          type="button"
          icon="i-lucide-lock-keyhole"
          class="!px-2"
          :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.SHOW_FIELD_BUTTON')"
          @click.prevent="showPasswordField = true"
        />
        <template v-else>
          <label :class="{ error: v$.newPassword.$error }">
            {{ $t('AGENT_MGMT.EDIT.PASSWORD_RESET.LABEL') }}
            <div class="flex items-center gap-2">
              <input
                v-model="newPassword"
                :type="showPassword ? 'text' : 'password'"
                autocomplete="new-password"
                :placeholder="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.PLACEHOLDER')"
                class="!mb-0"
                @input="v$.newPassword.$touch"
              />
              <Button
                type="button"
                :icon="showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'"
                slate
                faded
                @click="showPassword = !showPassword"
              />
            </div>
            <span v-if="v$.newPassword.$error" class="message">
              {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD.ERROR') }}
            </span>
            <p v-else-if="newPassword" class="text-xs text-n-slate-11 mt-1">
              {{ $t('AGENT_MGMT.EDIT.PASSWORD_RESET.HINT') }}
            </p>
          </label>
          <label
            v-if="newPassword"
            :class="{ error: v$.newPasswordConfirmation.$error }"
          >
            {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD_CONFIRMATION.LABEL') }}
            <input
              v-model="newPasswordConfirmation"
              :type="showPassword ? 'text' : 'password'"
              autocomplete="new-password"
              @input="v$.newPasswordConfirmation.$touch"
            />
            <span v-if="v$.newPasswordConfirmation.$error" class="message">
              {{ $t('AGENT_MGMT.ADD.FORM.PASSWORD_CONFIRMATION.ERROR') }}
            </span>
          </label>
          <Button
            type="button"
            size="sm"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.SUBMIT_BUTTON')"
            :is-loading="isResettingPassword"
            :disabled="!newPassword || v$.newPasswordConfirmation.$invalid"
            @click.prevent="resetPassword"
          />
        </template>
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right" />
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="v$.$invalid || uiFlags.isUpdating"
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
