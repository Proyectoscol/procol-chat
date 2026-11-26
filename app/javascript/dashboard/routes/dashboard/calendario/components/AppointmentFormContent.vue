<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import calendarioPayersAPI from 'dashboard/api/calendarioPayers';
import DatePicker from 'vue-datepicker-next';
import { dateKeyInColombia } from '../helpers/calendarioDateTime';
import { appointmentWarningMessage } from '../helpers/appointmentWarningMessage';
import { ES_DATEPICKER_LANG } from '../helpers/datepickerLang';
import { classifyContactQuery } from '../helpers/classifyContactQuery';
import { splitName } from '@chatwoot/utils';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactForm from 'dashboard/routes/dashboard/conversation/contact/ContactForm.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';

const props = defineProps({
  // Precarga el contacto cuando se abre esto desde una conversacion, o desde
  // una fila de la lista de espera -- en la pagina de Atendimientos llega
  // null y el usuario busca.
  presetContact: { type: Object, default: null },
  presetConversationId: { type: [Number, String], default: null },
  presetStartsAt: { type: Date, default: null },
  presetServiceId: { type: [Number, String], default: null },
  presetProfessionalId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();

const services = useMapGetter('calendarioServices/getServices');
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const contactSearchResults = useMapGetter('contacts/getContacts');
const getContactById = useMapGetter('contacts/getContact');
const contactUiFlags = useMapGetter('contacts/getUIFlags');
const openDays = useMapGetter('calendarioOpenDays/getOpenDays');

const contactQuery = ref(props.presetContact?.name || '');
const selectedContactId = ref(props.presetContact?.id || '');
const serviceId = ref(props.presetServiceId || '');
const professionalId = ref(props.presetProfessionalId || '');
const startsAt = ref(props.presetStartsAt || null);
const notes = ref('');
const amountToCollect = ref('');
const isSaving = ref(false);
const appointmentWarnings = ref([]);
let searchTimeout = null;

// --- Combobox accesible (ARIA) -------------------------------------------
// Antes este dropdown no tenia ningun soporte de teclado -- solo @click. Se
// agrega el patron estandar role="combobox" + role="listbox"/"option" para
// que la asistente pueda buscar y seleccionar sin mouse.
const comboboxId = `calendario-contact-combobox-${Math.random().toString(36).slice(2)}`;
const listboxId = `${comboboxId}-listbox`;
const isResultsOpen = ref(false);
const activeResultIndex = ref(-1);
const showCreateForm = ref(false);
const createContactFormRef = ref(null);
const newContact = ref(null);
const isCreatingContact = ref(false);
const isEditingContact = ref(false);

const activeOptionId = computed(() =>
  activeResultIndex.value >= 0
    ? `${listboxId}-option-${activeResultIndex.value}`
    : undefined
);

const documentTypeOptions = [
  { value: 'cc', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CC') },
  { value: 'ti', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.TI') },
  { value: 'ce', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CE') },
  { value: 'pa', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PA') },
  { value: 'rc', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.RC') },
  { value: 'pep', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PEP') },
  { value: 'ppt', label: t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PPT') },
];

// Dias con agenda ya abierta para el profesional elegido -- se marcan en el
// date picker (color mas vivo) para que la asistente vea de un vistazo donde
// ya hay agenda antes de escoger fecha/hora (pedido explicito: "esta agenda
// no esta abierta" es una sorpresa que se puede evitar mostrandolo antes).
watch(
  professionalId,
  id => {
    if (id) store.dispatch('calendarioOpenDays/get', { professionalId: id });
  },
  { immediate: true }
);
const openDayDates = computed(() => new Set(openDays.value.map(d => d.date)));
const getDayClasses = (value, _innerValue, classes) =>
  openDayDates.value.has(dateKeyInColombia(value))
    ? `${classes} has-open-day`.trim()
    : classes;

const payers = ref([]);

onMounted(async () => {
  const response = await calendarioPayersAPI.get();
  payers.value = response.data;

  // El contacto puede llegar preseleccionado (desde una conversacion o la
  // lista de espera) sin su registro completo en el store -- se trae antes
  // de mostrar el panel de "ver/editar contacto". Si ya esta completo (ej.
  // se abrio desde la propia pagina de Contactos, que ya lo cargo entero),
  // nos saltamos el fetch: dispatch('contacts/show') prende el ui flag
  // GLOBAL `isFetchingItem` del modulo contacts, y esa pagina lo usa para
  // ocultar/remontar todo el panel mientras esta en true -- re-disparandolo
  // aqui sin necesidad cerraba este mismo modal apenas se abria.
  if (
    selectedContactId.value &&
    getContactById.value(selectedContactId.value)?.payer_id === undefined
  ) {
    await store.dispatch('contacts/show', { id: selectedContactId.value });
  }
});

// La EPS/entidad es un dato del CONTACTO, no de la cita -- se ve/edita aqui
// junto al resto de sus datos, nunca como campo de Calendario::Appointment
// (ver migracion MoveCalendarioPayerFromAppointmentsToContacts).
const selectedContact = computed(() =>
  selectedContactId.value ? getContactById.value(selectedContactId.value) : null
);

const documentTypeLabel = documentType =>
  documentTypeOptions.find(option => option.value === documentType)?.label;

const onContactFormSubmit = async contactItem => {
  await store.dispatch('contacts/update', contactItem);
};

const warningMessage = warning => appointmentWarningMessage(t, warning);

const hasOpenDayMissingWarning = computed(() =>
  appointmentWarnings.value.some(warning => warning.type === 'open_day_missing')
);
const isSendingToWaitlist = ref(false);

// Salida rapida cuando el motivo de la advertencia es "no hay agenda
// abierta" -- en vez de forzar la cita (que abre el dia), la asistente
// puede mandar a lista de espera el MISMO contacto/servicio/profesional/
// notas que ya escribio, sin tener que volver a capturarlos en otra
// pantalla (pedido explicito del usuario).
const sendToWaitlistInstead = async () => {
  isSendingToWaitlist.value = true;
  try {
    await store.dispatch('calendarioWaitlistEntries/create', {
      contact_id: selectedContactId.value,
      service_id: serviceId.value,
      professional_id: professionalId.value,
      notes: notes.value,
    });
    useAlert(t('CALENDARIO.WAITLIST.ADD_FORM.SUCCESS'));
    emit('close');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.WAITLIST.ADD_FORM.ERROR')
    );
  } finally {
    isSendingToWaitlist.value = false;
  }
};

// Cualquier cambio a los campos que definen el horario invalida las
// advertencias que el usuario ya vio -- sin esto, cambiar la hora despues de
// confirmar un choque viejo crearia la cita nueva con force:true sin haber
// mostrado nunca el aviso para ese horario.
watch([serviceId, professionalId, startsAt], () => {
  appointmentWarnings.value = [];
});

const serviceOptions = computed(() => [
  { value: '', label: t('CALENDARIO.APPOINTMENTS.FORM.SERVICE_PLACEHOLDER') },
  ...services.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);

const professionalOptions = computed(() => {
  // Un profesional archivado (active: false) no debe poder recibir citas
  // NUEVAS -- sigue existiendo para conservar el historial de sus citas
  // pasadas, pero no aparece aqui como opcion.
  const activeProfessionals = professionals.value.filter(
    professional => professional.active
  );
  const eligible = serviceId.value
    ? activeProfessionals.filter(professional =>
        services.value
          .find(service => service.id === serviceId.value)
          ?.professional_ids?.includes(professional.id)
      )
    : activeProfessionals;
  return [
    {
      value: '',
      label: t('CALENDARIO.APPOINTMENTS.FORM.PROFESSIONAL_PLACEHOLDER'),
    },
    ...eligible.map(professional => ({
      value: professional.id,
      label: professional.name,
    })),
  ];
});

watch(serviceId, () => {
  if (
    !professionalOptions.value.some(
      option => option.value === professionalId.value
    )
  ) {
    professionalId.value = '';
  }
});

const onContactQueryInput = () => {
  selectedContactId.value = '';
  showCreateForm.value = false;
  activeResultIndex.value = -1;
  isResultsOpen.value = true;
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    if (contactQuery.value.trim().length < 2) return;
    store.dispatch('contacts/search', { search: contactQuery.value, page: 1 });
  }, 300);
};

const selectContact = contact => {
  selectedContactId.value = contact.id;
  contactQuery.value = contact.name;
  isResultsOpen.value = false;
  activeResultIndex.value = -1;
  isEditingContact.value = false;
};

const closeResults = () => {
  isResultsOpen.value = false;
  activeResultIndex.value = -1;
};

const onContactKeydown = event => {
  if (!isResultsOpen.value || !contactSearchResults.value.length) return;
  if (event.key === 'ArrowDown') {
    event.preventDefault();
    activeResultIndex.value =
      (activeResultIndex.value + 1) % contactSearchResults.value.length;
  } else if (event.key === 'ArrowUp') {
    event.preventDefault();
    activeResultIndex.value =
      (activeResultIndex.value - 1 + contactSearchResults.value.length) %
      contactSearchResults.value.length;
  } else if (event.key === 'Enter' && activeResultIndex.value >= 0) {
    event.preventDefault();
    selectContact(contactSearchResults.value[activeResultIndex.value]);
  } else if (event.key === 'Escape') {
    closeResults();
  }
};

const openCreateForm = () => {
  const classified = classifyContactQuery(contactQuery.value);
  newContact.value = null;
  showCreateForm.value = true;
  closeResults();
  // ContactsForm (el mismo componente de "nuevo contacto" de la pagina de
  // Contactos) ya trae sus propios defaults (documento cedula, pais
  // Colombia) -- aqui solo se precargan los datos que ya se detectaron en
  // la busqueda, y el pagador "particular" (default especifico de este
  // flujo de agendamiento, sembrado en toda cuenta).
  nextTick(() => {
    const formState = createContactFormRef.value?.state;
    if (!formState) return;
    // ContactsForm separa nombre/apellido internamente (`state.name` es
    // derivado, no editable directo) -- hay que precargar ambos para que
    // el nombre detectado en la busqueda se vea reflejado en los inputs.
    const { firstName, lastName } = splitName(classified.name || '');
    formState.firstName = firstName;
    formState.lastName = lastName;
    formState.name = classified.name || '';
    formState.phoneNumber = classified.phoneNumber || '';
    formState.identifier = classified.identifier || '';
    const particular = payers.value.find(payer => payer.kind === 'particular');
    if (particular) formState.payerId = particular.id;
  });
};

const isNewContactInvalid = computed(
  () => !newContact.value || createContactFormRef.value?.isFormInvalid
);

const createContactInline = async () => {
  if (!newContact.value) return;
  isCreatingContact.value = true;
  try {
    const contact = await store.dispatch('contacts/create', newContact.value);
    selectContact(contact);
    showCreateForm.value = false;
  } catch (error) {
    // Alertar en vez de crear un duplicado -- si ya existe por documento o
    // telefono, el backend devuelve 422 con el contacto existente.
    useAlert(
      error?.message || t('CALENDARIO.APPOINTMENTS.FORM.CREATE_CONTACT_ERROR')
    );
  } finally {
    isCreatingContact.value = false;
  }
};

const isFormInvalid = computed(
  () =>
    !selectedContactId.value ||
    !serviceId.value ||
    !professionalId.value ||
    !startsAt.value
);

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = {
    contact_id: selectedContactId.value,
    service_id: serviceId.value,
    professional_id: professionalId.value,
    starts_at: startsAt.value.toISOString(),
    notes: notes.value,
    amount_to_collect: amountToCollect.value || null,
    conversation_id: props.presetConversationId,
    // Si ya se mostraron las advertencias para este mismo horario, este
    // intento es la confirmacion del usuario -- crear igual.
    force: appointmentWarnings.value.length > 0,
  };
  try {
    const appointment = await store.dispatch(
      'calendarioAppointments/create',
      payload
    );
    useAlert(t('CALENDARIO.APPOINTMENTS.FORM.CREATE_SUCCESS'));
    emit('created', appointment);
    onClose();
  } catch (error) {
    if (error?.response?.status === 409 && error?.response?.data?.warnings) {
      appointmentWarnings.value = error.response.data.warnings;
    } else {
      useAlert(
        error?.response?.data?.error ||
          error?.response?.data?.message ||
          t('CALENDARIO.APPOINTMENTS.FORM.ERROR')
      );
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form class="flex flex-col gap-4 w-full" @submit.prevent="submit">
    <div class="flex flex-col gap-1 relative">
      <label :for="comboboxId" class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.CONTACT_LABEL') }}
      </label>
      <input
        :id="comboboxId"
        v-model="contactQuery"
        role="combobox"
        :aria-expanded="isResultsOpen && !!contactSearchResults.length"
        aria-autocomplete="list"
        :aria-controls="listboxId"
        :aria-activedescendant="activeOptionId"
        autocomplete="off"
        :disabled="!!presetContact"
        :placeholder="t('CALENDARIO.APPOINTMENTS.FORM.CONTACT_PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm disabled:opacity-60"
        @input="onContactQueryInput"
        @keydown="onContactKeydown"
        @focus="isResultsOpen = true"
      />
      <!-- Flota sobre el contenido (position: absolute) en vez de empujarlo
      -- antes este panel vivia en flujo normal y corria el resto del
      formulario hacia abajo. -->
      <ul
        v-if="!presetContact && isResultsOpen && contactSearchResults.length"
        :id="listboxId"
        role="listbox"
        class="absolute left-0 top-full z-20 mt-1 flex w-full flex-col gap-0.5 max-h-40 overflow-auto border border-n-weak rounded-lg bg-n-solid-1 p-1 shadow-lg"
      >
        <li
          v-for="(contact, index) in contactSearchResults"
          :id="`${listboxId}-option-${index}`"
          :key="contact.id"
          role="option"
          :aria-selected="index === activeResultIndex"
        >
          <button
            type="button"
            class="w-full text-left text-sm px-2 py-1 rounded hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-1': index === activeResultIndex }"
            @click="selectContact(contact)"
          >
            {{ contact.name }}
            <span class="text-n-slate-10">{{
              contact.identifier || contact.phone_number || contact.email
            }}</span>
          </button>
        </li>
      </ul>
      <!-- Mas llamativo a proposito -- pedido explicito del usuario: antes
      era un enlace de texto chiquito, facil de no ver cuando el contacto
      (cedula/nombre) no existe todavia y es justo lo que hay que hacer.
      Solo aparece si la busqueda NO encontro nada -- si ya hay resultados,
      es porque si existe, y este boton no deberia verse (pedido explicito). -->
      <button
        v-if="
          !presetContact &&
          !selectedContactId &&
          contactQuery.trim().length >= 2 &&
          !contactSearchResults.length &&
          !showCreateForm
        "
        type="button"
        class="flex items-center gap-2 w-full text-left text-sm font-medium text-n-blue-text bg-n-blue-2 hover:bg-n-blue-3 border border-n-blue-6 rounded-lg px-3 py-2 transition-colors"
        @click="openCreateForm"
      >
        <span class="i-lucide-user-plus size-4 flex-shrink-0" />
        {{
          t('CALENDARIO.APPOINTMENTS.FORM.CREATE_CONTACT_LINK', {
            query: contactQuery,
          })
        }}
      </button>
    </div>

    <!-- Al seleccionar un contacto existente, se puede confirmar/editar sus
    datos (documento, telefonos, EPS) aqui mismo -- estos son datos del
    PACIENTE, no de la cita, pero conviene revisarlos justo antes de agendar. -->
    <div
      v-if="selectedContact && selectedContact.id"
      class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
    >
      <ContactForm
        v-if="isEditingContact"
        :contact="selectedContact"
        :in-progress="contactUiFlags.isUpdating"
        :on-submit="onContactFormSubmit"
        @success="isEditingContact = false"
        @cancel="isEditingContact = false"
      />
      <div v-else class="flex items-start justify-between gap-2">
        <div class="flex flex-col gap-0.5 text-xs text-n-slate-11">
          <span v-if="selectedContact.identifier">
            {{ documentTypeLabel(selectedContact.document_type) }}:
            {{ selectedContact.identifier }}
          </span>
          <span v-if="selectedContact.phone_number">{{
            selectedContact.phone_number
          }}</span>
          <span v-if="selectedContact.secondary_phone_number">
            {{ t('CALENDARIO.APPOINTMENTS.FORM.SECONDARY_PHONE_LABEL') }}:
            {{ selectedContact.secondary_phone_number }}
          </span>
          <span v-if="selectedContact.payer_name">{{
            selectedContact.payer_name
          }}</span>
          <span
            v-if="!selectedContact.identifier && !selectedContact.payer_name"
            class="italic"
          >
            {{ t('CALENDARIO.APPOINTMENTS.FORM.CONTACT_DATA_INCOMPLETE') }}
          </span>
        </div>
        <Button
          faded
          slate
          size="sm"
          icon="i-woot-edit-pen"
          type="button"
          @click="isEditingContact = true"
        />
      </div>
    </div>

    <div
      v-if="showCreateForm"
      class="flex flex-col gap-3 rounded-lg border border-n-weak p-3"
    >
      <p class="text-xs text-n-slate-11">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.CREATE_CONTACT_TITLE') }}
      </p>
      <ContactsForm
        ref="createContactFormRef"
        is-new-contact
        @update="value => (newContact = value)"
      />
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          size="sm"
          type="button"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
          @click="showCreateForm = false"
        />
        <Button
          size="sm"
          type="button"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.CREATE_CONTACT_SUBMIT')"
          :is-loading="isCreatingContact"
          :disabled="isNewContactInvalid"
          @click="createContactInline"
        />
      </div>
    </div>

    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.SERVICE_LABEL') }}
      </label>
      <Select v-model="serviceId" :options="serviceOptions" />
    </div>

    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.PROFESSIONAL_LABEL') }}
      </label>
      <Select v-model="professionalId" :options="professionalOptions" />
    </div>

    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.STARTS_AT_LABEL') }}
      </label>
      <DatePicker
        v-model:value="startsAt"
        type="datetime"
        :lang="ES_DATEPICKER_LANG"
        format="DD/MM/YYYY hh:mm A"
        use12h
        :minute-step="10"
        confirm
        confirm-text="OK"
        :get-classes="getDayClasses"
        input-class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm"
      />
      <p v-if="professionalId" class="text-xs text-n-slate-10">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.OPEN_DAY_HINT') }}
      </p>
    </div>

    <TextArea
      v-model="notes"
      :label="t('CALENDARIO.APPOINTMENTS.FORM.NOTES_LABEL')"
      :max-length="500"
    />

    <div class="flex flex-col gap-1">
      <Input
        v-model="amountToCollect"
        type="number"
        :label="t('CALENDARIO.APPOINTMENTS.FORM.AMOUNT_TO_COLLECT_LABEL')"
        :placeholder="
          t('CALENDARIO.APPOINTMENTS.FORM.AMOUNT_TO_COLLECT_PLACEHOLDER')
        "
      />
      <p class="text-xs text-n-slate-10">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.AMOUNT_TO_COLLECT_HINT') }}
      </p>
    </div>

    <div
      v-if="appointmentWarnings.length"
      class="flex flex-col gap-2 text-sm text-n-amber-11 bg-n-amber-3 rounded-lg p-3"
    >
      <p v-for="(warning, index) in appointmentWarnings" :key="index">
        {{ warningMessage(warning) }}
      </p>
      <div v-if="hasOpenDayMissingWarning" class="flex justify-end">
        <Button
          faded
          amber
          size="sm"
          type="button"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.SEND_TO_WAITLIST_BUTTON')"
          :is-loading="isSendingToWaitlist"
          @click="sendToWaitlistInstead"
        />
      </div>
    </div>

    <div class="flex items-center justify-end gap-2">
      <Button
        faded
        slate
        type="button"
        :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
        @click="onClose"
      />
      <Button
        type="submit"
        :label="
          appointmentWarnings.length
            ? t('CALENDARIO.APPOINTMENTS.FORM.CONFIRM_ANYWAY')
            : t('CALENDARIO.APPOINTMENTS.FORM.CREATE')
        "
        :is-loading="isSaving"
        :disabled="isFormInvalid"
      />
    </div>
  </form>
</template>

<style>
/* vue-datepicker-next monta su popup como hijo directo de <body> (fuera del
arbol del componente) -- un estilo "scoped" normal nunca llegaria porque
depende de un ancestro con el atributo data-v-*, asi que esta regla queda
global a proposito. El nombre de clase es especifico de este feature para
evitar colisiones. */
td.cell.has-open-day {
  @apply bg-n-teal-9 text-white rounded-full font-semibold;
}
</style>
