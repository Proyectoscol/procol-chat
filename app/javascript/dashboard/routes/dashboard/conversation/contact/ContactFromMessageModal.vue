<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import { extractContactCandidates } from './extractContactCandidates';

const props = defineProps({
  messageContent: { type: String, default: '' },
  conversationId: { type: [String, Number], default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const createContactFormRef = ref(null);
const form = ref(null);

const candidates = computed(() =>
  extractContactCandidates(props.messageContent)
);

// El primer numero detectado se asume el "WhatsApp autorizado" (el que se
// usa para confirmar la cita); si hay un segundo, se ofrece como telefono
// secundario -- pedido explicito: "el numero de confirmacion seria el del
// WhatsApp autorizado y el otro numero, si existe, quedaria como telefono
// secundario".
const applyCandidates = () => {
  form.value = null;
  const found = candidates.value;
  nextTick(() => {
    const formState = createContactFormRef.value?.state;
    if (!formState) return;
    formState.phoneNumber = found.phones[0] || '';
    formState.secondaryPhoneNumber = found.phones[1] || '';
    formState.identifier = found.identifier || '';
    formState.customAttributes.date_of_birth = found.birthDate || '';
  });
};
watch(() => props.messageContent, applyCandidates, { immediate: true });

const isSaving = ref(false);
const isFormInvalid = computed(
  () => !form.value || createContactFormRef.value?.isFormInvalid
);

const copyOriginalMessage = async () => {
  await copyTextToClipboard(props.messageContent);
  useAlert(t('CALENDARIO.CONTACT_FROM_MESSAGE.MESSAGE_COPIED'));
};

const onClose = () => emit('close');

const submit = async () => {
  if (!form.value) return;
  isSaving.value = true;
  try {
    const contact = await store.dispatch('contacts/create', form.value);
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
        <ContactsForm
          ref="createContactFormRef"
          is-new-contact
          @update="value => (form = value)"
        />

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
