<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  appointment: { type: Object, required: true },
});
const emit = defineEmits(['close', 'cancelled']);

const { t } = useI18n();
const store = useStore();

const notes = ref('');
const isSaving = ref(false);
// Sin default a proposito -- un clic apurado no debe reactivar (o dejar sin
// reactivar) una entrada de waitlist silenciosamente. Obliga a elegir.
const cancellationType = ref('');

const isFormInvalid = computed(
  () => !notes.value.trim() || !cancellationType.value
);

const onClose = () => emit('close');

const submit = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    // Nunca pisar las notas existentes de la cita -- el motivo de
    // cancelacion se agrega, no las reemplaza.
    const combinedNotes = [props.appointment.notes, notes.value]
      .filter(note => note && note.trim())
      .join('\n\n');
    const updated = await store.dispatch('calendarioAppointments/update', {
      id: props.appointment.id,
      status: 'cancelled',
      notes: combinedNotes,
      cancellation_type: cancellationType.value,
    });
    useAlert(t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.SUCCESS'));
    emit('cancelled', updated);
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form class="flex flex-col gap-4 w-full" @submit.prevent="submit">
    <fieldset class="flex flex-col gap-2">
      <legend class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TYPE_LABEL') }}
      </legend>
      <label class="flex items-start gap-2 text-sm">
        <input
          v-model="cancellationType"
          type="radio"
          value="definitiva"
          class="mt-1"
        />
        <span>
          <span class="font-medium text-n-slate-12">{{
            t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TYPE_DEFINITIVE')
          }}</span>
          <span class="block text-n-slate-10">{{
            t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TYPE_DEFINITIVE_HINT')
          }}</span>
        </span>
      </label>
      <label class="flex items-start gap-2 text-sm">
        <input
          v-model="cancellationType"
          type="radio"
          value="temporal"
          class="mt-1"
        />
        <span>
          <span class="font-medium text-n-slate-12">{{
            t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TYPE_TEMPORARY')
          }}</span>
          <span class="block text-n-slate-10">{{
            t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TYPE_TEMPORARY_HINT')
          }}</span>
        </span>
      </label>
    </fieldset>

    <TextArea
      v-model="notes"
      :label="t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.NOTES_LABEL')"
      :placeholder="
        t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.NOTES_PLACEHOLDER')
      "
      :max-length="500"
    />

    <div class="flex items-center justify-end gap-2">
      <Button
        faded
        slate
        type="button"
        :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
        @click="onClose"
      />
      <Button
        ruby
        type="submit"
        :label="t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.SUBMIT')"
        :is-loading="isSaving"
        :disabled="isFormInvalid || isSaving"
      />
    </div>
  </form>
</template>
