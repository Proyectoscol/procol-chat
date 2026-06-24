<script setup>
import { computed, reactive, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import countries from 'shared/constants/countries.js';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';

const emit = defineEmits(['update']);

const { t } = useI18n();
const store = useStore();

const currentUser = useMapGetter('getCurrentUser');
const allAgents = useMapGetter('agents/getAgents');

// Only role:'agent' users appear in the dropdown
const agentOptions = computed(() =>
  allAgents.value
    .filter(a => a.role === 'agent')
    .map(a => ({ label: a.available_name || a.name, value: a.id }))
);

const currentUserRole = computed(() => currentUser.value?.role);
const currentUserIsAgent = computed(() => currentUserRole.value === 'agent');

// Fields config — Bio excluded intentionally for this custom form
const FORM_CONFIG = {
  FIRST_NAME: { field: 'firstName' },
  LAST_NAME: { field: 'lastName' },
  EMAIL_ADDRESS: { field: 'email' },
  PHONE_NUMBER: { field: 'phoneNumber' },
  CITY: { field: 'additionalAttributes.city' },
  COUNTRY: { field: 'additionalAttributes.countryCode' },
  COMPANY_NAME: { field: 'additionalAttributes.companyName' },
};

const SOCIAL_CONFIG = {
  LINKEDIN: 'i-ri-linkedin-box-fill',
  FACEBOOK: 'i-ri-facebook-circle-fill',
  INSTAGRAM: 'i-ri-instagram-line',
  TELEGRAM: 'i-ri-telegram-fill',
  TIKTOK: 'i-ri-tiktok-fill',
  TWITTER: 'i-ri-twitter-x-fill',
  GITHUB: 'i-ri-github-fill',
};

const defaultState = {
  id: 0,
  name: '',
  email: '',
  firstName: '',
  lastName: '',
  phoneNumber: '',
  additionalAttributes: {
    companyName: '',
    countryCode: '',
    country: '',
    city: '',
    socialProfiles: {
      facebook: '',
      github: '',
      instagram: '',
      telegram: '',
      tiktok: '',
      linkedin: '',
      twitter: '',
    },
  },
  asesorAgentId: null,
  asesorAgentName: '',
};

const state = reactive({ ...defaultState });

const validationRules = {
  firstName: { required },
  email: { email },
  asesorAgentId: { required },
};

const v$ = useVuelidate(validationRules, state);

const isFormInvalid = computed(() => v$.value.$invalid);

const countryOptions = computed(() =>
  countries.map(({ name, id }) => ({ label: name, value: id }))
);

const editDetailsForm = computed(() =>
  Object.keys(FORM_CONFIG).map(key => ({
    key,
    placeholder: t(
      `CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM.${key}.PLACEHOLDER`
    ),
  }))
);

const socialProfilesForm = computed(() =>
  Object.entries(SOCIAL_CONFIG).map(([key, icon]) => ({
    key,
    placeholder: t(`CONTACTS_LAYOUT.CARD.SOCIAL_MEDIA.FORM.${key}.PLACEHOLDER`),
    icon,
  }))
);

const isValidationField = key => {
  const field = FORM_CONFIG[key]?.field;
  return ['firstName', 'email'].includes(field);
};

const getValidationKey = key => FORM_CONFIG[key]?.field;

const emitUpdate = () => {
  const { firstName, lastName, asesorAgentId, asesorAgentName, ...rest } =
    state;
  emit('update', {
    ...rest,
    customAttributes: {
      asesor_asignado_id: asesorAgentId,
      asesor_asignado_nombre: asesorAgentName,
    },
  });
};

const getFormBinding = key => {
  const field = FORM_CONFIG[key]?.field;
  if (!field) return null;

  return computed({
    get: () => {
      if (field === 'firstName' || field === 'lastName') {
        return state[field]?.toString() || '';
      }
      const [base, nested] = field.split('.');
      return (nested ? state[base][nested] : state[base])?.toString() || '';
    },
    set: async value => {
      if (field === 'firstName' || field === 'lastName') {
        state[field] = value;
        state.name = `${state.firstName} ${state.lastName}`.trim();
      } else {
        const [base, nested] = field.split('.');
        if (nested) {
          state[base][nested] = value;
        } else {
          state[base] = value;
        }
      }

      const isFormValid = await v$.value.$validate();
      if (isFormValid) {
        emitUpdate();
      }
    },
  });
};

const getMessageType = key => {
  return isValidationField(key) && v$.value[getValidationKey(key)]?.$error
    ? 'error'
    : 'info';
};

const handleCountrySelection = value => {
  const selectedCountry = countries.find(option => option.id === value);
  state.additionalAttributes.country = selectedCountry?.name || '';
  emitUpdate();
};

const handleAgentSelection = agentId => {
  state.asesorAgentId = agentId;
  const agent = allAgents.value.find(a => a.id === agentId);
  state.asesorAgentName = agent ? agent.available_name || agent.name : '';
  v$.value.asesorAgentId.$touch();
  emitUpdate();
};

const resetValidation = () => {
  v$.value.$reset();
};

const resetForm = () => {
  Object.assign(state, {
    ...defaultState,
    additionalAttributes: {
      ...defaultState.additionalAttributes,
      socialProfiles: { ...defaultState.additionalAttributes.socialProfiles },
    },
  });
  // Re-apply agent preselection for agent users
  if (currentUserIsAgent.value) {
    state.asesorAgentId = currentUser.value.id;
    state.asesorAgentName =
      currentUser.value.available_name || currentUser.value.name;
  }
};

// Preselect current agent when the form mounts and the user is an agent
watch(
  [currentUser, allAgents],
  ([user, agents]) => {
    if (user?.role === 'agent' && !state.asesorAgentId && agents.length > 0) {
      state.asesorAgentId = user.id;
      state.asesorAgentName = user.available_name || user.name;
    }
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('agents/get');
});

defineExpose({
  state,
  resetValidation,
  isFormInvalid,
  resetForm,
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col items-start gap-2">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.TITLE') }}
      </span>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <template v-for="item in editDetailsForm" :key="item.key">
          <ComboBox
            v-if="item.key === 'COUNTRY'"
            v-model="state.additionalAttributes.countryCode"
            :options="countryOptions"
            :placeholder="item.placeholder"
            class="[&>div>button]:h-8 [&>div>button]:!bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent"
            @update:model-value="handleCountrySelection"
          />
          <PhoneNumberInput
            v-else-if="item.key === 'PHONE_NUMBER'"
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
          />
          <Input
            v-else
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
            :message-type="getMessageType(item.key)"
            :custom-input-class="`h-8 !pt-1 !pb-1 ${
              isValidationField(item.key)
                ? ''
                : '[&:not(.error,.focus)]:!outline-transparent'
            }`"
            class="w-full"
            @input="
              isValidationField(item.key) &&
              v$[getValidationKey(item.key)].$touch()
            "
            @blur="
              isValidationField(item.key) &&
              v$[getValidationKey(item.key)].$touch()
            "
          />
        </template>
      </div>
    </div>

    <!-- Asesor asignado -->
    <div class="flex flex-col items-start gap-2">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_LAYOUT.CREATE_WITH_ADVISOR.ADVISOR_SECTION_TITLE') }}
      </span>
      <div class="w-full">
        <ComboBox
          :model-value="state.asesorAgentId"
          :options="agentOptions"
          :placeholder="
            t('CONTACTS_LAYOUT.CREATE_WITH_ADVISOR.ADVISOR_PLACEHOLDER')
          "
          :has-error="v$.asesorAgentId.$error"
          :message="
            v$.asesorAgentId.$error
              ? t('CONTACTS_LAYOUT.CREATE_WITH_ADVISOR.ADVISOR_REQUIRED')
              : ''
          "
          class="[&>div>button]:h-8 [&>div>button]:!bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent w-full"
          @update:model-value="handleAgentSelection"
        />
        <p v-if="v$.asesorAgentId.$error" class="mt-1 text-xs text-n-ruby-9">
          {{ t('CONTACTS_LAYOUT.CREATE_WITH_ADVISOR.ADVISOR_REQUIRED') }}
        </p>
      </div>
    </div>

    <!-- Social profiles -->
    <div class="flex flex-col items-start gap-2">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_LAYOUT.CARD.SOCIAL_MEDIA.TITLE') }}
      </span>
      <div class="flex flex-wrap gap-2">
        <div
          v-for="item in socialProfilesForm"
          :key="item.key"
          class="flex items-center h-8 gap-2 px-2 rounded-lg bg-n-alpha-2 dark:bg-n-solid-3"
        >
          <Icon
            :icon="item.icon"
            class="flex-shrink-0 text-n-slate-11 size-4"
          />
          <input
            v-model="
              state.additionalAttributes.socialProfiles[item.key.toLowerCase()]
            "
            class="w-auto min-w-[100px] text-sm bg-transparent outline-none reset-base text-n-slate-12 dark:text-n-slate-12 placeholder:text-n-slate-10 dark:placeholder:text-n-slate-10"
            :placeholder="item.placeholder"
            :size="item.placeholder.length"
            @input="emitUpdate"
          />
        </div>
      </div>
    </div>
  </div>
</template>
