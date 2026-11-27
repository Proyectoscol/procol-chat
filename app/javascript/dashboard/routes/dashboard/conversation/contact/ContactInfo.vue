<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import Avatar from 'next/avatar/Avatar.vue';
import EditContact from './EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ContactDeleteModal from 'dashboard/modules/contact/ContactDeleteModal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import AppointmentFormModal from 'dashboard/routes/dashboard/calendario/components/AppointmentFormModal.vue';
import WaitlistPanel from 'dashboard/routes/dashboard/calendario/components/WaitlistPanel.vue';

export default {
  components: {
    NextButton,
    ContactInfoRow,
    EditContact,
    Avatar,
    ContactMergeModal,
    ContactDeleteModal,
    VoiceCallButton,
    InlineInput,
    AppointmentFormModal,
    WaitlistPanel,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
    conversationId: {
      type: [Number, String],
      default: null,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      showEditModal: false,
      isEditingName: false,
      editName: '',
      showAppointmentModal: false,
      showWaitlistModal: false,
      // Pedido explicito del usuario 2026-11-27 (caso real: contacto sin
      // nombre ni EPS, se creo una cita manualmente y nunca salio ningun
      // mensaje -- fallo en silencio porque ningun disparador aplica sin
      // payer_kind). Guarda cual boton se intento abrir ('appointment' o
      // 'waitlist') mientras el contacto esta incompleto, para retomarlo
      // justo despues de guardar la edicion obligatoria.
      pendingAction: null,
      editingForCompletion: false,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    // Un nombre vacio o un simple placeholder (".", espacios) y la falta de
    // EPS/pagador hacen inviable el envio automatico de plantillas (ver
    // Calendario::AppointmentEventTrigger#applies_to? -- payer_kinds nunca
    // matchea un payer nulo). Agendar o agregar a lista de espera con el
    // contacto asi queda siempre en silencio, sin ningun mensaje real.
    contactIsIncomplete() {
      const name = (this.contact.name || '').trim();
      const hasRealName = name.length > 0 && !/^\.+$/.test(name);
      return !hasRealName || !this.contact.payer_id;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    dateOfBirth() {
      return this.contact.custom_attributes?.date_of_birth || '';
    },
    // Edad calculada a partir de la fecha de nacimiento -- pedido explicito
    // del usuario para verla de un vistazo en el panel, sin tener que
    // calcularla a mano cada vez.
    age() {
      if (!this.dateOfBirth) return '';
      const birthDate = new Date(this.dateOfBirth);
      if (Number.isNaN(birthDate.getTime())) return '';
      const today = new Date();
      let years = today.getFullYear() - birthDate.getFullYear();
      const hasHadBirthdayThisYear =
        today.getMonth() > birthDate.getMonth() ||
        (today.getMonth() === birthDate.getMonth() &&
          today.getDate() >= birthDate.getDate());
      if (!hasHadBirthdayThisYear) years -= 1;
      return years >= 0
        ? this.$t('CONTACT_PANEL.AGE_YEARS', { count: years })
        : '';
    },
    // Contactos importados sin telefono real pueden tener solo el username
    // de WhatsApp guardado (social_whatsapp_user_name) -- se usa para
    // identificar la conversacion, pero NO sirve para enviar mensajes
    // salientes por Twilio (exige un numero E.164 real). Mostrar un @ en
    // vez de "No Disponible" deja claro que es un username, no un telefono,
    // y que hay que pedirle el numero real al paciente.
    whatsappUsername() {
      return this.additionalAttributes.social_whatsapp_user_name || '';
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    dynamicTime,
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    toggleAppointmentModal() {
      this.showAppointmentModal = !this.showAppointmentModal;
    },
    // Bug real reportado por el usuario 2026-11-27: la X y Escape del
    // woot-modal no cerraban el modal de agendar cita. woot-modal ya pone
    // show en false por su cuenta (via v-model:show) antes de llamar a
    // on-close -- pasarle el mismo toggle usado para ABRIRLO lo volvia a
    // poner en true justo despues (false -> !false). on-close necesita un
    // cierre directo, no un toggle.
    closeAppointmentModal() {
      this.showAppointmentModal = false;
    },
    toggleWaitlistModal() {
      this.showWaitlistModal = !this.showWaitlistModal;
    },
    // Puntos de entrada reales de los botones "Agendar cita"/"Agregar a
    // lista de espera" -- si el contacto esta incompleto, se exige
    // completarlo primero (lateral de edicion, EPS obligatoria) en vez de
    // abrir el modal directo y terminar en una cita que nunca notifica a
    // nadie.
    openCreateAppointment() {
      if (this.contactIsIncomplete) {
        this.pendingAction = 'appointment';
        this.editingForCompletion = true;
        this.showEditModal = true;
        return;
      }
      this.showAppointmentModal = true;
    },
    openCreateWaitlist() {
      if (this.contactIsIncomplete) {
        this.pendingAction = 'waitlist';
        this.editingForCompletion = true;
        this.showEditModal = true;
        return;
      }
      this.showWaitlistModal = true;
    },
    onContactEditSaved() {
      this.showEditModal = false;
      if (this.pendingAction === 'appointment') {
        this.showAppointmentModal = true;
      } else if (this.pendingAction === 'waitlist') {
        this.showWaitlistModal = true;
      }
      this.pendingAction = null;
      this.editingForCompletion = false;
    },
    onContactEditCancelled() {
      this.pendingAction = null;
      this.editingForCompletion = false;
      this.toggleEditModal();
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    startEditingName() {
      this.editName = this.contact.name || '';
      this.isEditingName = true;
      this.$nextTick(() => {
        this.$refs.nameInput?.focus();
      });
    },
    saveNameEdit() {
      if (!this.isEditingName) return;
      this.isEditingName = false;
      const trimmed = this.editName.trim();
      if (trimmed && trimmed !== this.contact.name) {
        this.updateContactField({ name: trimmed });
      }
    },
    cancelNameEdit() {
      this.isEditingName = false;
    },
    async updateContactField(attrs) {
      const contactId = this.contact.id;
      try {
        await this.$store.dispatch('contacts/update', {
          id: contactId,
          ...attrs,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch('contacts/fetchContactableInbox', contactId);
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          const detail = error.contactErrorDetail;
          if (detail) {
            useAlert(detail);
          } else {
            const invalidAttrs = Array.isArray(error.data) ? error.data : [];
            if (invalidAttrs.includes('email')) {
              useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
            } else if (invalidAttrs.includes('phone_number')) {
              useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
            } else {
              useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
            }
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
  },
};
</script>

<template>
  <div class="relative items-center w-full p-4">
    <div class="flex flex-col w-full gap-2 text-left rtl:text-right">
      <div class="flex flex-row justify-between">
        <Avatar
          v-if="showAvatar"
          :src="contact.thumbnail"
          :name="contact.name"
          :status="contact.availability_status"
          :size="48"
          hide-offline-status
          rounded-full
        />
      </div>

      <div class="flex flex-col items-start gap-1.5 min-w-0 w-full">
        <div v-if="showAvatar" class="flex items-center w-full min-w-0 gap-3">
          <InlineInput
            v-if="isEditingName"
            ref="nameInput"
            v-model="editName"
            custom-input-class="!text-base !font-medium"
            class="!w-fit"
            @enter-press="saveNameEdit"
            @escape-press="cancelNameEdit"
            @blur="saveNameEdit"
          />
          <h3
            v-else
            class="group/name flex-shrink max-w-full min-w-0 my-0 text-base capitalize break-words text-n-slate-12 cursor-pointer hover:text-n-slate-12/80"
            :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
            @click="startEditingName"
          >
            {{ contact.name }}
            <span
              class="i-lucide-pencil text-xs text-n-slate-10 opacity-0 group-hover/name:opacity-100 transition-opacity ml-1 align-middle"
            />
          </h3>
          <div class="flex flex-row items-center gap-2">
            <span
              v-if="contact.created_at"
              v-tooltip.left="
                `${$t('CONTACT_PANEL.CREATED_AT_LABEL')} ${dynamicTime(
                  contact.created_at
                )}`
              "
              class="i-lucide-info text-sm text-n-slate-10"
            />
            <a
              :href="contactProfileLink"
              target="_blank"
              rel="noopener nofollow noreferrer"
              class="leading-3"
            >
              <span class="i-lucide-external-link text-sm text-n-slate-10" />
            </a>
          </div>
        </div>

        <div class="grid grid-cols-2 items-start w-full gap-x-3 gap-y-2">
          <ContactInfoRow
            class="col-span-2"
            :href="contact.email ? `mailto:${contact.email}` : ''"
            :value="contact.email"
            icon="mail"
            emoji="✉️"
            show-copy
            editable
            @edit-click="toggleEditModal"
          />
          <ContactInfoRow
            v-if="!contact.phone_number && whatsappUsername"
            class="col-span-2"
            :value="`@${whatsappUsername}`"
            icon="mention"
            emoji="🔖"
            show-copy
            editable
            @edit-click="toggleEditModal"
          />
          <ContactInfoRow
            v-else
            class="col-span-2"
            :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
            :value="contact.phone_number"
            icon="call"
            emoji="📞"
            show-copy
            editable
            @edit-click="toggleEditModal"
          />
          <ContactInfoRow
            :value="contact.identifier"
            icon="contact-identify"
            emoji="🪪"
          />
          <ContactInfoRow
            :value="contact.payer_name"
            icon="lock-shield"
            emoji="🏥"
          />
          <ContactInfoRow :value="dateOfBirth" icon="calendar" emoji="🎂" />
          <ContactInfoRow :value="age" icon="info" emoji="⏳" />
          <ContactInfoRow
            v-if="location || additionalAttributes.location"
            class="col-span-2"
            :value="location || additionalAttributes.location"
            icon="map"
            emoji="🌍"
          />
        </div>
      </div>
      <div class="flex items-center w-full mt-0.5 gap-2">
        <VoiceCallButton
          :phone="contact.phone_number"
          :contact-id="contact.id"
          :conversation-id="currentChat?.id"
          icon="i-lucide-phone"
          sm
          faded
          slate
          :tooltip-label="$t('CONTACT_PANEL.CALL')"
        />
        <NextButton
          v-tooltip.top-end="$t('EDIT_CONTACT.BUTTON_LABEL')"
          icon="i-ph-pencil-simple"
          slate
          faded
          sm
          @click="toggleEditModal"
        />
        <NextButton
          v-tooltip.top-end="$t('CONTACT_PANEL.NEW_APPOINTMENT')"
          icon="i-lucide-calendar-plus"
          slate
          faded
          sm
          @click="openCreateAppointment"
        />
        <NextButton
          v-tooltip.top-end="$t('CONTACT_PANEL.ADD_TO_WAITLIST')"
          icon="i-lucide-list-plus"
          slate
          faded
          sm
          @click="openCreateWaitlist"
        />
        <ContactMergeModal :primary-contact="contact">
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('CONTACT_PANEL.MERGE_CONTACT')"
              icon="i-ph-arrows-merge"
              slate
              faded
              sm
              :disabled="uiFlags.isMerging"
            />
          </template>
        </ContactMergeModal>
        <ContactDeleteModal
          v-if="isAdmin"
          :contact="contact"
          @deleted="$emit('panelClose')"
        >
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('DELETE_CONTACT.BUTTON_LABEL')"
              icon="i-ph-trash"
              slate
              faded
              sm
              ruby
              :disabled="uiFlags.isDeleting"
            />
          </template>
        </ContactDeleteModal>
      </div>
      <EditContact
        :show="showEditModal"
        :contact="contact"
        :require-payer="editingForCompletion"
        @cancel="onContactEditCancelled"
        @saved="onContactEditSaved"
      />
      <woot-modal
        v-model:show="showAppointmentModal"
        :on-close="closeAppointmentModal"
      >
        <AppointmentFormModal
          :preset-contact="contact"
          :preset-conversation-id="conversationId"
          @close="toggleAppointmentModal"
        />
      </woot-modal>
      <WaitlistPanel
        :show="showWaitlistModal"
        :preset-contact="contact"
        @close="toggleWaitlistModal"
      />
    </div>
  </div>
</template>
