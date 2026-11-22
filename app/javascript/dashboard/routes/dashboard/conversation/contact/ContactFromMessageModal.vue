<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import calendarioPayersAPI from 'dashboard/api/calendarioPayers';
import { extractContactCandidates } from './extractContactCandidates';

const props = defineProps({
  messageContent: { type: String, default: '' },
  conversationId: { type: [String, Number], default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const DOCUMENT_TYPE_OPTIONS = [
  { value: 'cc', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CC') },
  { value: 'ti', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.TI') },
  { value: 'ce', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CE') },
  { value: 'pa', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PA') },
  { value: 'rc', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.RC') },
  { value: 'pep', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PEP') },
  { value: 'ppt', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PPT') },
];

const payers = ref([]);
const payerOptions = computed(() => [
  { value: '', label: t('CALENDARIO.CONTACT_FROM_MESSAGE.PAYER_PLACEHOLDER') },
  ...[...payers.value]
    .sort((a, b) => a.name.localeCompare(b.name, 'es'))
    .map(payer => ({ value: payer.id, label: payer.name })),
]);

const candidates = computed(() =>
  extractContactCandidates(props.messageContent)
);

// El primer numero detectado se asume el "WhatsApp autorizado" (el que se
// usa para confirmar la cita); si hay un segundo, se ofrece como telefono
// secundario -- pedido explicito: "el numero de confirmacion seria el del
// WhatsApp autorizado y el otro numero, si existe, quedaria como telefono
// secundario".
const form = ref({
  name: '',
  phoneNumber: '',
  secondaryPhoneNumber: '',
  documentType: 'cc',
  identifier: '',
  payerId: '',
  dateOfBirth: '',
});

const applyCandidates = () => {
  const found = candidates.value;
  form.value = {
    name: '',
    phoneNumber: found.phones[0] || '',
    secondaryPhoneNumber: found.phones[1] || '',
    documentType: 'cc',
    identifier: found.identifier || '',
    payerId: '',
    dateOfBirth: found.birthDate || '',
  };
};
watch(() => props.messageContent, applyCandidates, { immediate: true });

calendarioPayersAPI.get().then(response => {
  payers.value = response.data;
});

const isSaving = ref(false);
const isFormInvalid = computed(
  () => !form.value.name.trim() || !form.value.identifier.trim()
);

const copyOriginalMessage = async () => {
  await copyTextToClipboard(props.messageContent);
  useAlert(t('CALENDARIO.CONTACT_FROM_MESSAGE.MESSAGE_COPIED'));
};

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  try {
    const contact = await store.dispatch('contacts/create', {
      name: form.value.name.trim(),
      phoneNumber: form.value.phoneNumber.trim(),
      secondaryPhoneNumber: form.value.secondaryPhoneNumber.trim(),
      documentType: form.value.documentType,
      identifier: form.value.identifier.trim(),
      payerId: form.value.payerId || null,
      customAttributes: form.value.dateOfBirth
        ? { date_of_birth: form.value.dateOfBirth }
        : {},
    });
    if (props.conversationId) {
      store.dispatch('createPendingMessageAndSend', {
        conversationId: props.conversationId,
        message: t('CALENDARIO.CONTACT_FROM_MESSAGE.PRIVATE_NOTE', {
          name: contact.name,
        }),
        private: true,
      });
    }
    useAlert(t('CALENDARIO.CONTACT_FROM_MESSAGE.CREATE_SUCCESS'));
    onClose();
  } catch (error) {
    useAlert(
      error?.message || t('CALENDARIO.CONTACT_FROM_MESSAGE.CREATE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="t('CALENDARIO.CONTACT_FROM_MESSAGE.TITLE')"
    />
    <div class="grid grid-cols-2 gap-4 px-4 pb-4 w-full !self-stretch">
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('CALENDARIO.CONTACT_FROM_MESSAGE.ORIGINAL_MESSAGE_LABEL') }}
          </label>
          <Button
            faded
            slate
            sm
            icon="i-lucide-clipboard"
            :label="t('CALENDARIO.CONTACT_FROM_MESSAGE.COPY_BUTTON')"
            @click="copyOriginalMessage"
          />
        </div>
        <p class="text-xs text-n-slate-10 -mt-1">
          {{ t('CALENDARIO.CONTACT_FROM_MESSAGE.ORIGINAL_MESSAGE_HINT') }}
        </p>
        <div
          class="text-sm whitespace-pre-wrap text-n-slate-12 bg-n-alpha-black2 rounded-lg p-3 select-text max-h-[28rem] overflow-y-auto"
        >
          {{ messageContent }}
        </div>
      </div>

      <form class="flex flex-col gap-3" @submit.prevent="submit">
        <Input
          v-model="form.name"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.NEW_CONTACT_NAME')"
        />
        <div class="flex gap-2">
          <div class="flex flex-col gap-1 w-1/3">
            <label class="text-sm font-medium text-n-slate-12">{{
              t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPE_LABEL')
            }}</label>
            <Select
              v-model="form.documentType"
              :options="DOCUMENT_TYPE_OPTIONS"
            />
          </div>
          <Input
            v-model="form.identifier"
            class="flex-1"
            :label="t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_NUMBER_LABEL')"
          />
        </div>
        <Input
          v-model="form.phoneNumber"
          :label="t('CALENDARIO.CONTACT_FROM_MESSAGE.AUTHORIZED_PHONE_LABEL')"
        />
        <Input
          v-model="form.secondaryPhoneNumber"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.SECONDARY_PHONE_LABEL')"
          :placeholder="
            t('CALENDARIO.APPOINTMENTS.FORM.SECONDARY_PHONE_PLACEHOLDER')
          "
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">{{
            t('CALENDARIO.CONTACT_FROM_MESSAGE.BIRTH_DATE_LABEL')
          }}</label>
          <input
            v-model="form.dateOfBirth"
            type="date"
            class="reset-base !mb-0"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">{{
            t('CALENDARIO.APPOINTMENTS.FORM.PAYER_LABEL')
          }}</label>
          <Select v-model="form.payerId" :options="payerOptions" />
        </div>

        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.CONTACT_FROM_MESSAGE.REVIEW_HINT') }}
        </p>

        <div class="flex items-center justify-end gap-2 mt-2">
          <Button
            faded
            slate
            type="button"
            :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
            @click="onClose"
          />
          <Button
            type="submit"
            :label="t('CALENDARIO.CONTACT_FROM_MESSAGE.CREATE_SUBMIT')"
            :is-loading="isSaving"
            :disabled="isFormInvalid"
          />
        </div>
      </form>
    </div>
  </div>
</template>
