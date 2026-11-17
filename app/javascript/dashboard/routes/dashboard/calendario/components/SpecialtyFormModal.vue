<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  specialty: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const isEditMode = computed(() => !!props.specialty);

const name = ref('');
const active = ref(true);
const isSaving = ref(false);

const setFormValues = () => {
  name.value = props.specialty?.name || '';
  active.value = props.specialty ? props.specialty.active : true;
};
watch(() => props.specialty, setFormValues, { immediate: true });

const isFormInvalid = computed(() => !name.value.trim());

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = { name: name.value, active: active.value };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioSpecialties/update', {
        id: props.specialty.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.SPECIALTIES.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioSpecialties/create', payload);
      useAlert(t('CALENDARIO.SPECIALTIES.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CALENDARIO.SPECIALTIES.FORM.ERROR')
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
          ? t('CALENDARIO.SPECIALTIES.FORM.EDIT_TITLE')
          : t('CALENDARIO.SPECIALTIES.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="name"
        :label="t('CALENDARIO.SPECIALTIES.FORM.NAME_LABEL')"
        :placeholder="t('CALENDARIO.SPECIALTIES.FORM.NAME_PLACEHOLDER')"
      />
      <div class="flex items-center gap-2">
        <input id="specialty-active" v-model="active" type="checkbox" />
        <label for="specialty-active">{{
          t('CALENDARIO.SPECIALTIES.FORM.ACTIVE_LABEL')
        }}</label>
      </div>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.SPECIALTIES.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.SPECIALTIES.FORM.SAVE')
              : t('CALENDARIO.SPECIALTIES.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
