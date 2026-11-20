<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import calendarioWaitlistEntriesAPI from 'dashboard/api/calendarioWaitlistEntries';

const props = defineProps({
  show: { type: Boolean, default: false },
  // Modo "inline": se usa cuando Agendas esta expandida y este panel vive
  // al lado de la tarjeta de dias en vez de como drawer superpuesto -- el
  // contenido es el mismo, solo cambian las clases del wrapper.
  inline: { type: Boolean, default: false },
  // Solo en modo inline: acota la lista a un profesional (el de la pestana
  // activa en Agendas) -- en modo drawer sigue mostrando todos.
  professionalId: { type: [Number, String], default: null },
  // Solo en modo inline: el filtro de servicio pasa a ser compartido con
  // Agendas (ver effectiveServiceId mas abajo) en vez del ref interno.
  serviceId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'book', 'update:serviceId']);

const { t } = useI18n();
const store = useStore();

const rawEntries = useMapGetter('calendarioWaitlistEntries/getWaitlistEntries');
const uiFlags = useMapGetter('calendarioWaitlistEntries/getUIFlags');
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const services = useMapGetter('calendarioServices/getServices');
const contactResults = useMapGetter('contacts/getContacts');

const showDeletePopup = ref(false);
const removingEntry = ref(null);

// --- Filtro y orden -------------------------------------------------------
// Antiguedad por defecto (mas dias esperando primero) -- es el caso de uso
// que el personal describio: priorizar a quien lleva mas tiempo, sobre todo
// a quienes volvieron por una cancelacion.
const filterOrigin = ref('');
const localServiceId = ref('');
const sortBy = ref('oldest');

// En modo inline el filtro de servicio vive en el padre (Agendas) y se
// comparte en ambos sentidos -- cambiar aca o alla actualiza el otro lado.
// En modo drawer sigue siendo un filtro interno normal.
const effectiveServiceId = computed({
  get: () => (props.inline ? props.serviceId || '' : localServiceId.value),
  set: value => {
    if (props.inline) emit('update:serviceId', value);
    else localServiceId.value = value;
  },
});

const originFilterOptions = computed(() => [
  { value: '', label: t('CALENDARIO.WAITLIST.FILTERS.ORIGIN_ALL') },
  { value: 'manual', label: t('CALENDARIO.WAITLIST.FILTERS.ORIGIN_MANUAL') },
  {
    value: 'cancellation',
    label: t('CALENDARIO.WAITLIST.FILTERS.ORIGIN_CANCELLATION'),
  },
]);
const serviceFilterOptions = computed(() => [
  { value: '', label: t('CALENDARIO.WAITLIST.FILTERS.SERVICE_ALL') },
  ...services.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);
const sortOptions = computed(() => [
  { value: 'oldest', label: t('CALENDARIO.WAITLIST.FILTERS.SORT_OLDEST') },
  { value: 'newest', label: t('CALENDARIO.WAITLIST.FILTERS.SORT_NEWEST') },
  { value: 'service', label: t('CALENDARIO.WAITLIST.FILTERS.SORT_SERVICE') },
]);

const daysWaiting = entry =>
  Math.max(
    0,
    Math.floor((Date.now() - new Date(entry.created_at).getTime()) / 86400000)
  );

const daysWaitingLabel = entry => {
  const count = daysWaiting(entry);
  return count === 1
    ? t('CALENDARIO.WAITLIST.DAYS_WAITING_ONE', { count })
    : t('CALENDARIO.WAITLIST.DAYS_WAITING_OTHER', { count });
};

const entries = computed(() => {
  let list = [...rawEntries.value];
  if (props.professionalId) {
    list = list.filter(entry => entry.professional_id === props.professionalId);
  }
  if (filterOrigin.value) {
    list = list.filter(entry => entry.origin === filterOrigin.value);
  }
  if (effectiveServiceId.value) {
    list = list.filter(entry => entry.service_id === effectiveServiceId.value);
  }
  if (sortBy.value === 'service') {
    list.sort((a, b) => a.service_name.localeCompare(b.service_name, 'es'));
  } else {
    list.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
    if (sortBy.value === 'newest') list.reverse();
  }
  return list;
});

const fetchEntries = () => store.dispatch('calendarioWaitlistEntries/get');

// Se recarga cada vez que el panel se abre -- una cita creada desde otra
// pestana pudo haber cumplido (fulfilled) una entrada mientras el panel
// estaba cerrado.
watch(
  () => props.show,
  show => {
    if (show) fetchEntries();
  }
);

onMounted(() => {
  if (props.show) fetchEntries();
});

const book = entry => emit('book', entry);

const confirmRemove = entry => {
  removingEntry.value = entry;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  try {
    await store.dispatch(
      'calendarioWaitlistEntries/delete',
      removingEntry.value.id
    );
  } catch (error) {
    useAlert(t('CALENDARIO.WAITLIST.DELETE_ERROR'));
  } finally {
    closeDeletePopup();
  }
};

// --- Agregar/editar una entrada de la lista de espera --------------------
// Un mismo formulario sirve para crear y editar -- editingEntryId null
// significa "creando", con un id significa "editando esa entrada" (el
// contacto no se puede cambiar al editar, solo servicio/profesional/notas:
// cambiar de paciente seria mas bien borrar y crear una entrada nueva).
const showAddForm = ref(false);
const editingEntryId = ref(null);
const contactQuery = ref('');
const selectedContactId = ref('');
const selectedContactName = ref('');
const newEntryServiceId = ref('');
const newEntryProfessionalId = ref('');
const newEntryNotes = ref('');
const isCreatingEntry = ref(false);
const isDuplicate = ref(false);
let searchTimeout = null;

const serviceOptions = computed(() => [
  { value: '', label: t('CALENDARIO.WAITLIST.ADD_FORM.SERVICE_PLACEHOLDER') },
  ...services.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);
const professionalOptions = computed(() => [
  {
    value: '',
    label: t('CALENDARIO.WAITLIST.ADD_FORM.PROFESSIONAL_PLACEHOLDER'),
  },
  // Un profesional archivado no deberia recibir entradas nuevas de lista de
  // espera -- mismo criterio que AppointmentFormContent.
  ...professionals.value
    .filter(professional => professional.active)
    .map(professional => ({
      value: professional.id,
      label: professional.name,
    })),
]);

const resetAddForm = () => {
  editingEntryId.value = null;
  contactQuery.value = '';
  selectedContactId.value = '';
  selectedContactName.value = '';
  newEntryServiceId.value = '';
  newEntryProfessionalId.value = '';
  newEntryNotes.value = '';
  isDuplicate.value = false;
};

const toggleAddForm = () => {
  showAddForm.value = !showAddForm.value;
  if (showAddForm.value) resetAddForm();
};
const closeAddForm = () => {
  showAddForm.value = false;
  resetAddForm();
};

const openEditForm = entry => {
  editingEntryId.value = entry.id;
  selectedContactId.value = entry.contact_id;
  selectedContactName.value = entry.contact_name;
  contactQuery.value = entry.contact_name;
  newEntryServiceId.value = entry.service_id;
  newEntryProfessionalId.value = entry.professional_id;
  newEntryNotes.value = entry.notes || '';
  showAddForm.value = true;
};

const onContactQueryInput = () => {
  selectedContactId.value = '';
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    if (contactQuery.value.trim().length < 2) return;
    store.dispatch('contacts/search', { search: contactQuery.value, page: 1 });
  }, 300);
};

const selectContact = contact => {
  selectedContactId.value = contact.id;
  selectedContactName.value = contact.name;
  contactQuery.value = contact.name;
};

const isAddFormInvalid = computed(
  () =>
    !selectedContactId.value ||
    !newEntryServiceId.value ||
    !newEntryProfessionalId.value
);

// Alerta de duplicado -- pedido explicito: "si una persona estaba en lista
// de espera, y la segunda vez que me lo indique, como una etiqueta".
// Mismo contacto + mismo profesional + mismo servicio (decision confirmada
// con el usuario), contando CUALQUIER estado historico (no solo pending --
// ver Api::V1::Accounts::Calendario::WaitlistEntriesController#check_duplicate).
// No aplica mientras se esta EDITANDO una entrada existente: esa entrada
// misma siempre "matchearia" contra si misma, lo cual no es util.
const checkForDuplicate = async () => {
  if (
    editingEntryId.value ||
    !selectedContactId.value ||
    !newEntryServiceId.value ||
    !newEntryProfessionalId.value
  ) {
    isDuplicate.value = false;
    return;
  }
  try {
    const response = await calendarioWaitlistEntriesAPI.checkDuplicate({
      contactId: selectedContactId.value,
      professionalId: newEntryProfessionalId.value,
      serviceId: newEntryServiceId.value,
    });
    isDuplicate.value = response.data.exists;
  } catch (error) {
    isDuplicate.value = false;
  }
};
watch(
  [selectedContactId, newEntryServiceId, newEntryProfessionalId],
  checkForDuplicate
);

const submitAddEntry = async () => {
  isCreatingEntry.value = true;
  try {
    if (editingEntryId.value) {
      await store.dispatch('calendarioWaitlistEntries/update', {
        id: editingEntryId.value,
        service_id: newEntryServiceId.value,
        professional_id: newEntryProfessionalId.value,
        notes: newEntryNotes.value,
      });
      useAlert(t('CALENDARIO.WAITLIST.ADD_FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioWaitlistEntries/create', {
        contact_id: selectedContactId.value,
        service_id: newEntryServiceId.value,
        professional_id: newEntryProfessionalId.value,
        notes: newEntryNotes.value,
      });
      useAlert(t('CALENDARIO.WAITLIST.ADD_FORM.SUCCESS'));
    }
    resetAddForm();
    showAddForm.value = false;
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.WAITLIST.ADD_FORM.ERROR')
    );
  } finally {
    isCreatingEntry.value = false;
  }
};

// El padre lo usa en modo inline para refrescar la lista justo despues de
// un quick-book (ahi no hay un `show` que pase de false a true para
// disparar el watch de arriba).
defineExpose({ fetchEntries });
</script>

<template>
  <div
    class="transition-opacity duration-200"
    :class="
      inline
        ? ''
        : `fixed inset-0 z-40 ${
            show
              ? 'bg-n-alpha-black2 backdrop-blur-[2px]'
              : 'pointer-events-none opacity-0'
          }`
    "
    @click.self="!inline && $emit('close')"
  >
    <div
      class="flex flex-col bg-n-solid-1"
      :class="
        inline
          ? 'h-full w-full sm:w-[380px] border border-n-weak rounded-xl overflow-hidden'
          : `fixed top-0 bottom-0 right-0 z-50 w-full sm:w-[420px] border-l border-n-weak shadow-2xl transition-transform duration-200 ease-in-out ${
              show ? 'translate-x-0' : 'translate-x-full pointer-events-none'
            }`
      "
    >
      <div
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <div class="flex items-center gap-2">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('CALENDARIO.WAITLIST.TITLE') }}
          </h3>
          <!-- Contador -- pedido explicito del usuario: "que diga la
          cantidad de personas que están en lista de espera", en rojo para
          que resalte. entries ya viene filtrado por profesional/origen/
          servicio, asi que el numero coincide con lo que se ve abajo. -->
          <span
            v-if="entries.length"
            class="flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full bg-n-ruby-9 text-white text-xs font-medium leading-none"
          >
            {{ entries.length }}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <Button
            size="sm"
            variant="faded"
            slate
            icon="i-lucide-plus"
            :label="t('CALENDARIO.WAITLIST.ADD_BUTTON')"
            @click="toggleAddForm"
          />
          <button
            v-if="!inline"
            type="button"
            class="i-lucide-x size-5 text-n-slate-10 hover:text-n-slate-12"
            @click="$emit('close')"
          />
        </div>
      </div>

      <div class="flex flex-wrap items-end gap-2 p-4 border-b border-n-weak">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('CALENDARIO.WAITLIST.FILTERS.ORIGIN_LABEL')
          }}</label>
          <Select v-model="filterOrigin" :options="originFilterOptions" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('CALENDARIO.WAITLIST.FILTERS.SERVICE_LABEL')
          }}</label>
          <Select
            v-model="effectiveServiceId"
            :options="serviceFilterOptions"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('CALENDARIO.WAITLIST.FILTERS.SORT_LABEL')
          }}</label>
          <Select v-model="sortBy" :options="sortOptions" />
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <div v-if="uiFlags.isFetching" class="flex justify-center py-8">
          <Spinner />
        </div>
        <p
          v-else-if="!entries.length"
          class="text-sm text-n-slate-10 text-center py-8"
        >
          {{ t('CALENDARIO.WAITLIST.EMPTY') }}
        </p>
        <div v-else class="flex flex-col gap-2">
          <div
            v-for="entry in entries"
            :key="entry.id"
            class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
          >
            <div class="flex items-start justify-between gap-2">
              <div>
                <div class="flex items-center gap-1.5">
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ entry.contact_name }}
                  </p>
                  <span
                    class="text-[10px] font-medium rounded px-1.5 py-0.5"
                    :class="
                      entry.origin === 'cancellation'
                        ? 'bg-n-amber-3 text-n-amber-11'
                        : 'bg-n-slate-3 text-n-slate-11'
                    "
                  >
                    {{
                      entry.origin === 'cancellation'
                        ? t('CALENDARIO.WAITLIST.ORIGIN_CANCELLATION_BADGE')
                        : t('CALENDARIO.WAITLIST.ORIGIN_MANUAL_BADGE')
                    }}
                  </span>
                </div>
                <p class="text-xs text-n-slate-10">
                  {{ entry.contact_phone_number }}
                </p>
                <p class="text-xs text-n-slate-10">
                  {{ daysWaitingLabel(entry) }}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  class="i-lucide-pencil size-4 text-n-slate-10 hover:text-n-slate-12"
                  @click="openEditForm(entry)"
                />
                <button
                  type="button"
                  class="i-lucide-x size-4 text-n-slate-10 hover:text-n-ruby-9"
                  @click="confirmRemove(entry)"
                />
              </div>
            </div>
            <p class="text-xs text-n-slate-11">
              {{ entry.service_name }} · {{ entry.professional_name }}
            </p>
            <p v-if="entry.notes" class="text-xs text-n-slate-10">
              {{ entry.notes }}
            </p>
            <Button
              size="sm"
              :label="t('CALENDARIO.WAITLIST.BOOK_BUTTON')"
              @click="book(entry)"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- Modal, no expansion inline -- pedido explicito del usuario: antes
    esto se renderizaba en flujo normal dentro del panel y empujaba hacia
    abajo los filtros (Origen/Servicio/Ordenar por) cada vez que se editaba
    una entrada, moviendo la pantalla justo cuando el personal esta en medio
    de una operacion. -->
    <woot-modal v-model:show="showAddForm" :on-close="closeAddForm">
      <div class="flex flex-col gap-2 p-4">
        <p class="text-sm font-medium text-n-slate-12">
          {{
            editingEntryId
              ? t('CALENDARIO.WAITLIST.ADD_FORM.EDIT_TITLE')
              : t('CALENDARIO.WAITLIST.ADD_FORM.CREATE_TITLE')
          }}
        </p>

        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.WAITLIST.ADD_FORM.CONTACT_LABEL')
        }}</label>
        <input
          v-model="contactQuery"
          :disabled="!!editingEntryId"
          :placeholder="t('CALENDARIO.WAITLIST.ADD_FORM.CONTACT_PLACEHOLDER')"
          class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm disabled:opacity-60"
          @input="onContactQueryInput"
        />
        <ul
          v-if="
            !editingEntryId &&
            contactQuery.trim().length >= 2 &&
            !selectedContactId &&
            contactResults.length
          "
          class="flex flex-col gap-0.5 max-h-32 overflow-auto border border-n-weak rounded-lg bg-n-solid-1 p-1"
        >
          <li v-for="contact in contactResults" :key="contact.id">
            <button
              type="button"
              class="w-full text-left text-sm px-2 py-1 rounded hover:bg-n-alpha-1"
              @click="selectContact(contact)"
            >
              {{ contact.name }}
              <span class="text-n-slate-10">{{ contact.phone_number }}</span>
            </button>
          </li>
        </ul>

        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.WAITLIST.ADD_FORM.SERVICE_LABEL')
        }}</label>
        <Select v-model="newEntryServiceId" :options="serviceOptions" />

        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.WAITLIST.ADD_FORM.PROFESSIONAL_LABEL')
        }}</label>
        <Select
          v-model="newEntryProfessionalId"
          :options="professionalOptions"
        />

        <!-- Alerta de duplicado -- pedido explicito del usuario. -->
        <p
          v-if="isDuplicate"
          class="flex items-center gap-1.5 text-xs font-medium text-n-ruby-11 bg-n-ruby-3 rounded-lg px-2.5 py-2"
        >
          <span class="i-lucide-alert-triangle size-3.5 flex-shrink-0" />
          {{ t('CALENDARIO.WAITLIST.ADD_FORM.DUPLICATE_WARNING') }}
        </p>

        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.WAITLIST.ADD_FORM.NOTES_LABEL')
        }}</label>
        <textarea
          v-model="newEntryNotes"
          rows="2"
          class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm"
        />

        <div class="flex items-center justify-end gap-2 mt-1">
          <Button
            faded
            slate
            size="sm"
            type="button"
            :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
            @click="closeAddForm"
          />
          <Button
            size="sm"
            :label="
              editingEntryId
                ? t('CALENDARIO.WAITLIST.ADD_FORM.SAVE')
                : t('CALENDARIO.WAITLIST.ADD_FORM.SUBMIT')
            "
            :is-loading="isCreatingEntry"
            :disabled="isAddFormInvalid"
            @click="submitAddEntry"
          />
        </div>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.WAITLIST.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.WAITLIST.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.WAITLIST.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.WAITLIST.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
