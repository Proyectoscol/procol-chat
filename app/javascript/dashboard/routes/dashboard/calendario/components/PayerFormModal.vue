<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  payer: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const isEditMode = computed(() => !!props.payer);

const name = ref('');
const kind = ref('eps');
const active = ref(true);
const isSaving = ref(false);

const kindOptions = [
  { value: 'particular', label: t('CALENDARIO.PAYERS.KIND_VALUES.PARTICULAR') },
  { value: 'eps', label: t('CALENDARIO.PAYERS.KIND_VALUES.EPS') },
  {
    value: 'plan_complementario',
    label: t('CALENDARIO.PAYERS.KIND_VALUES.PLAN_COMPLEMENTARIO'),
  },
  { value: 'prepagada', label: t('CALENDARIO.PAYERS.KIND_VALUES.PREPAGADA') },
  { value: 'poliza', label: t('CALENDARIO.PAYERS.KIND_VALUES.POLIZA') },
];

const setFormValues = () => {
  name.value = props.payer?.name || '';
  kind.value = props.payer?.kind || 'eps';
  active.value = props.payer ? props.payer.active : true;
};
watch(() => props.payer, setFormValues, { immediate: true });

const isFormInvalid = computed(() => !name.value.trim());

const onClose = () => emit('close');

const submit = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  const payload = { name: name.value, kind: kind.value, active: active.value };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioPayers/update', {
        id: props.payer.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.PAYERS.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioPayers/create', payload);
      useAlert(t('CALENDARIO.PAYERS.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CALENDARIO.PAYERS.FORM.ERROR')
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
        isEditMode
          ? t('CALENDARIO.PAYERS.FORM.EDIT_TITLE')
          : t('CALENDARIO.PAYERS.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="name"
        :label="t('CALENDARIO.PAYERS.FORM.NAME_LABEL')"
        :placeholder="t('CALENDARIO.PAYERS.FORM.NAME_PLACEHOLDER')"
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.PAYERS.FORM.KIND_LABEL') }}
        </label>
        <Select v-model="kind" :options="kindOptions" />
      </div>
      <div class="flex items-center gap-2">
        <input id="payer-active" v-model="active" type="checkbox" />
        <label for="payer-active">{{
          t('CALENDARIO.PAYERS.FORM.ACTIVE_LABEL')
        }}</label>
      </div>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.PAYERS.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.PAYERS.FORM.SAVE')
              : t('CALENDARIO.PAYERS.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid || isSaving"
        />
      </div>
    </form>
  </div>
</template>
