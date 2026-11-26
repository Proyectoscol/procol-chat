<script setup>
import { computed, reactive, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { required, requiredIf, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { splitName } from '@chatwoot/utils';
import countries from 'shared/constants/countries.js';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import calendarioPayersAPI from 'dashboard/api/calendarioPayers';

const props = defineProps({
  contactData: {
    type: Object,
    default: null,
  },
  isDetailsView: {
    type: Boolean,
    default: false,
  },
  isNewContact: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const FORM_CONFIG = {
  FIRST_NAME: { field: 'firstName' },
  LAST_NAME: { field: 'lastName' },
  DOCUMENT_TYPE: { field: 'documentType', newContactOnly: true },
  IDENTIFIER: { field: 'identifier', newContactOnly: true },
  EMAIL_ADDRESS: { field: 'email' },
  PHONE_NUMBER: { field: 'phoneNumber' },
  SECONDARY_PHONE_NUMBER: { field: 'secondaryPhoneNumber' },
  BIRTH_DATE: { field: 'customAttributes.date_of_birth' },
  CITY: { field: 'additionalAttributes.city' },
  COUNTRY: { field: 'additionalAttributes.countryCode' },
  PAYER: { field: 'payerId' },
};

const DOCUMENT_TYPE_OPTIONS = ['cc', 'ti', 'ce', 'pa', 'rc', 'pep', 'ppt'];

// Colombia por defecto -- la inmensa mayoria de los pacientes son de aqui,
// y asi el selector de pais no queda vacio al crear un contacto nuevo.
const DEFAULT_COUNTRY = { id: 'CO', name: 'Colombia' };

// Funcion (no objeto compartido) -- un objeto module-level con sub-objetos
// anidados (additionalAttributes/customAttributes) se pasaria por
// REFERENCIA en cada `{ ...defaultState }`, asi que escribir en el
// formulario corrompia ese "default" compartido entre contactos distintos
// de la misma sesion (bug real encontrado: la ciudad/pais del contacto
// anterior se filtraba al formulario de uno nuevo tras resetForm()).
const createDefaultState = () => ({
  id: 0,
  name: '',
  email: '',
  firstName: '',
  lastName: '',
  documentType: 'cc',
  identifier: '',
  phoneNumber: '',
  secondaryPhoneNumber: '',
  payerId: '',
  customAttributes: {
    date_of_birth: '',
  },
  additionalAttributes: {
    countryCode: DEFAULT_COUNTRY.id,
    country: DEFAULT_COUNTRY.name,
    city: '',
  },
});

const state = reactive(createDefaultState());

const payers = ref([]);
const payerOptions = computed(() => [
  ...[...payers.value]
    .sort((a, b) => a.name.localeCompare(b.name, 'es'))
    .map(payer => ({ value: payer.id, label: payer.name })),
]);

onMounted(async () => {
  const response = await calendarioPayersAPI.get();
  payers.value = response.data;
});

// El documento no es obligatorio si ya se tiene el telefono -- hay casos
// donde solo se conoce el numero y se solicita el resto despues por
// WhatsApp (mismo criterio que el backend en ContactsController#create).
const isDocumentRequired = () =>
  props.isNewContact && !state.phoneNumber?.trim();

const validationRules = {
  firstName: { required },
  email: { email },
  documentType: { required: requiredIf(isDocumentRequired) },
  identifier: { required: requiredIf(isDocumentRequired) },
};

const v$ = useVuelidate(validationRules, state);

const isFormInvalid = computed(() => v$.value.$invalid);

const prepareStateBasedOnProps = () => {
  if (props.isNewContact) {
    return; // Added to prevent state update for new contact form
  }

  const {
    id,
    name = '',
    email: emailAddress,
    phoneNumber,
    secondaryPhoneNumber = '',
    payerId = '',
    customAttributes = {},
    additionalAttributes = {},
  } = props.contactData || {};
  const { firstName, lastName } = splitName(name || '');
  const {
    countryCode = '',
    country = '',
    city = '',
  } = additionalAttributes || {};

  Object.assign(state, {
    id,
    name,
    firstName,
    lastName,
    email: emailAddress,
    phoneNumber,
    secondaryPhoneNumber,
    payerId,
    customAttributes: {
      date_of_birth: customAttributes.date_of_birth || '',
    },
    additionalAttributes: {
      countryCode,
      country,
      city,
    },
  });
};

const countryOptions = computed(() =>
  countries.map(({ name, id }) => ({ label: name, value: id }))
);

const documentTypeOptions = computed(() =>
  DOCUMENT_TYPE_OPTIONS.map(value => ({
    value,
    label: t(
      `CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.${value.toUpperCase()}`
    ),
  }))
);

const editDetailsForm = computed(() =>
  Object.keys(FORM_CONFIG)
    .filter(key => props.isNewContact || !FORM_CONFIG[key].newContactOnly)
    .map(key => ({
      key,
      placeholder: t(
        `CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM.${key}.PLACEHOLDER`
      ),
    }))
);

const isValidationField = key => {
  const field = FORM_CONFIG[key]?.field;
  return ['firstName', 'email', 'documentType', 'identifier'].includes(field);
};

const getValidationKey = key => {
  return FORM_CONFIG[key]?.field;
};

// Creates a computed property for two-way form field binding
const getFormBinding = key => {
  const field = FORM_CONFIG[key]?.field;
  if (!field) return null;

  return computed({
    get: () => {
      // Handle firstName/lastName fields
      if (field === 'firstName' || field === 'lastName') {
        return state[field]?.toString() || '';
      }

      // Handle nested vs non-nested fields
      const [base, nested] = field.split('.');
      // Example: 'email' → state.email
      // Example: 'additionalAttributes.city' → state.additionalAttributes.city
      return (nested ? state[base][nested] : state[base])?.toString() || '';
    },

    set: async value => {
      // Handle name fields specially to maintain the combined 'name' field
      if (field === 'firstName' || field === 'lastName') {
        state[field] = value;
        // Example: firstName="John", lastName="Doe" → name="John Doe"
        state.name = `${state.firstName} ${state.lastName}`.trim();
      } else {
        // Handle nested vs non-nested fields
        const [base, nested] = field.split('.');
        if (nested) {
          // Example: additionalAttributes.city = "New York"
          state[base][nested] = value;
        } else {
          // Example: email = "test@example.com"
          state[base] = value;
        }
      }

      const isFormValid = await v$.value.$validate();
      if (isFormValid) {
        const { firstName, lastName, ...stateWithoutNames } = state;
        emit('update', stateWithoutNames);
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
  emit('update', state);
};

const resetValidation = () => {
  v$.value.$reset();
};

const resetForm = () => {
  Object.assign(state, createDefaultState());
};

watch(
  () => props.contactData?.id,
  id => {
    if (id) prepareStateBasedOnProps();
  },
  { immediate: true }
);

// Expose state to parent component for avatar upload
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
            class="[&>div>button]:h-8"
            :class="{
              '[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent':
                !isDetailsView,
              '[&>div>button]:!bg-n-alpha-black2': isDetailsView,
            }"
            @update:model-value="handleCountrySelection"
          />
          <ComboBox
            v-else-if="item.key === 'DOCUMENT_TYPE'"
            v-model="getFormBinding(item.key).value"
            :options="documentTypeOptions"
            :placeholder="item.placeholder"
            class="[&>div>button]:h-8"
            :class="{
              '[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent':
                !isDetailsView,
              '[&>div>button]:!bg-n-alpha-black2': isDetailsView,
            }"
          />
          <PhoneNumberInput
            v-else-if="item.key === 'PHONE_NUMBER'"
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
            :show-border="isDetailsView"
          />
          <ComboBox
            v-else-if="item.key === 'PAYER'"
            v-model="getFormBinding(item.key).value"
            :options="payerOptions"
            :placeholder="item.placeholder"
            class="[&>div>button]:h-8"
            :class="{
              '[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent':
                !isDetailsView,
              '[&>div>button]:!bg-n-alpha-black2': isDetailsView,
            }"
          />
          <input
            v-else-if="item.key === 'BIRTH_DATE'"
            v-model="getFormBinding(item.key).value"
            type="date"
            class="reset-base !mb-0 h-8 w-full"
          />
          <Input
            v-else
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
            :message-type="getMessageType(item.key)"
            :custom-input-class="`h-8 !pt-1 !pb-1 ${
              !isDetailsView
                ? '[&:not(.error,.focus)]:!outline-transparent'
                : ''
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
  </div>
</template>
