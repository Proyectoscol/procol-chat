<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// presetKey presente = se esta agregando una version nueva a una key que ya
// existe (el campo de key queda fijo, no editable); ausente = se esta
// creando una key totalmente nueva. prefill trae el contenido de la ultima
// version como punto de partida -- el usuario edita a partir de ahi en vez
// de empezar en blanco.
const props = defineProps({
  presetKey: { type: String, default: '' },
  prefillLabel: { type: String, default: '' },
  prefillBody: { type: String, default: '' },
  prefillQuickReplies: { type: Array, default: () => [] },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const key = ref(props.presetKey);
const label = ref(props.prefillLabel);
const body = ref(props.prefillBody);
const quickRepliesText = ref(props.prefillQuickReplies.join('\n'));
const notes = ref('');
const isSaving = ref(false);

const isNewKey = computed(() => !props.presetKey);

const isFormInvalid = computed(
  () => !key.value.trim() || !label.value.trim() || !body.value.trim()
);

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  try {
    await store.dispatch('calendarioMessageTemplates/create', {
      key: key.value.trim(),
      label: label.value.trim(),
      body: body.value.trim(),
      quick_replies: quickRepliesText.value
        .split('\n')
        .map(line => line.trim())
        .filter(Boolean),
      notes: notes.value.trim(),
    });
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.FORM.CREATE_SUCCESS'));
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('CALENDARIO.TEMPLATE_LIBRARY.FORM.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="
        isNewKey
          ? t('CALENDARIO.TEMPLATE_LIBRARY.FORM.CREATE_TITLE')
          : t('CALENDARIO.TEMPLATE_LIBRARY.FORM.NEW_VERSION_TITLE', {
              label: prefillLabel,
            })
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <div class="flex flex-col gap-1">
        <Input
          v-model="key"
          :disabled="!isNewKey"
          :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.KEY_LABEL')"
          :placeholder="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.KEY_PLACEHOLDER')"
        />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TEMPLATE_LIBRARY.FORM.KEY_HINT') }}
        </p>
      </div>

      <Input
        v-model="label"
        :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.LABEL_LABEL')"
        :placeholder="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.LABEL_PLACEHOLDER')"
      />

      <TextArea
        v-model="body"
        :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.BODY_LABEL')"
        rows="8"
      />

      <TextArea
        v-model="quickRepliesText"
        :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.QUICK_REPLIES_LABEL')"
        rows="3"
      />

      <TextArea
        v-model="notes"
        :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.NOTES_LABEL')"
        rows="2"
      />

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="t('CALENDARIO.TEMPLATE_LIBRARY.FORM.CREATE')"
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
