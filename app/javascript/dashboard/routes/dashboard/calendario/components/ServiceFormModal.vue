<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  service: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');

const isEditMode = computed(() => !!props.service);

const name = ref('');
const durationMinutes = ref(30);
const color = ref('#1f93ff');
const active = ref(true);
const professionalIds = ref([]);
const kind = ref('consultation');
const basePrice = ref(0);
const includedSessions = ref(0);
const isSaving = ref(false);

const kindOptions = [
  {
    value: 'consultation',
    label: t('CALENDARIO.SERVICES.FORM.KIND_OPTIONS.CONSULTATION'),
  },
  {
    value: 'control',
    label: t('CALENDARIO.SERVICES.FORM.KIND_OPTIONS.CONTROL'),
  },
  {
    value: 'procedure',
    label: t('CALENDARIO.SERVICES.FORM.KIND_OPTIONS.PROCEDURE'),
  },
];

const setFormValues = () => {
  name.value = props.service?.name || '';
  durationMinutes.value = props.service?.duration_minutes || 30;
  color.value = props.service?.color || '#1f93ff';
  active.value = props.service ? props.service.active : true;
  professionalIds.value = [...(props.service?.professional_ids || [])];
  kind.value = props.service?.kind || 'consultation';
  basePrice.value = props.service?.base_price || 0;
  includedSessions.value = props.service?.included_sessions || 0;
};
watch(() => props.service, setFormValues, { immediate: true });

const toggleProfessional = id => {
  professionalIds.value = professionalIds.value.includes(id)
    ? professionalIds.value.filter(existing => existing !== id)
    : [...professionalIds.value, id];
};

const isFormInvalid = computed(
  () => !name.value.trim() || Number(durationMinutes.value) <= 0
);

const onClose = () => emit('close');

const submit = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  const payload = {
    name: name.value,
    duration_minutes: Number(durationMinutes.value),
    color: color.value,
    active: active.value,
    professional_ids: professionalIds.value,
    kind: kind.value,
    base_price: Number(basePrice.value) || 0,
    included_sessions: Number(includedSessions.value) || 0,
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioServices/update', {
        id: props.service.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.SERVICES.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioServices/create', payload);
      useAlert(t('CALENDARIO.SERVICES.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CALENDARIO.SERVICES.FORM.ERROR')
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
          ? t('CALENDARIO.SERVICES.FORM.EDIT_TITLE')
          : t('CALENDARIO.SERVICES.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="name"
        :label="t('CALENDARIO.SERVICES.FORM.NAME_LABEL')"
        :placeholder="t('CALENDARIO.SERVICES.FORM.NAME_PLACEHOLDER')"
      />
      <Input
        v-model="durationMinutes"
        type="number"
        min="1"
        :label="t('CALENDARIO.SERVICES.FORM.DURATION_LABEL')"
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.SERVICES.FORM.COLOR_LABEL') }}
        </label>
        <input
          v-model="color"
          type="color"
          class="w-16 h-8 rounded border border-n-weak"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.SERVICES.FORM.KIND_LABEL') }}
        </label>
        <select
          v-model="kind"
          class="w-full rounded border border-n-weak bg-transparent p-2"
        >
          <option
            v-for="option in kindOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
      <Input
        v-model="basePrice"
        type="number"
        min="0"
        :label="t('CALENDARIO.SERVICES.FORM.BASE_PRICE_LABEL')"
      />
      <Input
        v-if="kind === 'procedure'"
        v-model="includedSessions"
        type="number"
        min="0"
        :label="t('CALENDARIO.SERVICES.FORM.INCLUDED_SESSIONS_LABEL')"
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.SERVICES.FORM.PROFESSIONALS_LABEL') }}
        </label>
        <div class="flex flex-col gap-1 max-h-40 overflow-auto">
          <div
            v-for="professional in professionals"
            :key="professional.id"
            class="flex items-center gap-2"
          >
            <input
              :id="`service-professional-${professional.id}`"
              type="checkbox"
              :checked="professionalIds.includes(professional.id)"
              @change="toggleProfessional(professional.id)"
            />
            <label :for="`service-professional-${professional.id}`">{{
              professional.name
            }}</label>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <input id="service-active" v-model="active" type="checkbox" />
        <label for="service-active">{{
          t('CALENDARIO.SERVICES.FORM.ACTIVE_LABEL')
        }}</label>
      </div>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.SERVICES.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.SERVICES.FORM.SAVE')
              : t('CALENDARIO.SERVICES.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid || isSaving"
        />
      </div>
    </form>
  </div>
</template>
