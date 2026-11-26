<script>
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import countries from 'shared/constants/countries.js';
import { isPhoneNumberValid } from 'shared/helpers/Validators';
import parsePhoneNumber from 'libphonenumber-js';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import calendarioPayersAPI from 'dashboard/api/calendarioPayers';

// Colombia por defecto -- la inmensa mayoria de los pacientes son de aqui,
// y asi el selector de pais no queda vacio al crear un contacto nuevo.
const DEFAULT_COUNTRY = { id: 'CO', name: 'Colombia' };

export default {
  components: {
    NextButton,
    ComboBox,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    inProgress: {
      type: Boolean,
      default: false,
    },
    onSubmit: {
      type: Function,
      default: () => {},
    },
  },
  emits: ['cancel', 'success'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      countries: countries,
      email: '',
      name: '',
      phoneNumber: '',
      activeDialCode: '',
      // Documento, telefono secundario, fecha/lugar de nacimiento y EPS son
      // datos del paciente (no de la cita) -- se editan aqui, en el
      // formulario general de contacto, para que sean consistentes sin
      // importar desde donde se editen.
      documentType: 'cc',
      identifier: '',
      secondaryPhoneNumber: '',
      dateOfBirth: '',
      payerId: '',
      payers: [],
      country: {
        id: DEFAULT_COUNTRY.id,
        name: DEFAULT_COUNTRY.name,
      },
      city: '',
    };
  },
  validations: {
    name: {
      required,
    },
    email: {
      email,
    },
    phoneNumber: {},
  },
  computed: {
    documentTypeOptions() {
      return [
        {
          value: 'cc',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CC'),
        },
        {
          value: 'ti',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.TI'),
        },
        {
          value: 'ce',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.CE'),
        },
        {
          value: 'pa',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PA'),
        },
        {
          value: 'rc',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.RC'),
        },
        {
          value: 'pep',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PEP'),
        },
        {
          value: 'ppt',
          label: this.$t('CALENDARIO.APPOINTMENTS.FORM.DOCUMENT_TYPES.PPT'),
        },
      ];
    },
    payerOptions() {
      return [...this.payers]
        .sort((a, b) => a.name.localeCompare(b.name, 'es'))
        .map(payer => ({ value: payer.id, label: payer.name }));
    },
    parsePhoneNumber() {
      return parsePhoneNumber(this.phoneNumber);
    },
    isPhoneNumberNotValid() {
      if (this.phoneNumber !== '') {
        return (
          !isPhoneNumberValid(this.phoneNumber, this.activeDialCode) ||
          (this.phoneNumber !== '' ? this.activeDialCode === '' : false)
        );
      }
      return false;
    },
    phoneNumberError() {
      if (this.activeDialCode === '') {
        return this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DIAL_CODE_ERROR');
      }
      if (!isPhoneNumberValid(this.phoneNumber, this.activeDialCode)) {
        return this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.ERROR');
      }
      return '';
    },
    setPhoneNumber() {
      if (this.parsePhoneNumber && this.parsePhoneNumber.countryCallingCode) {
        return this.phoneNumber;
      }
      if (this.phoneNumber === '' && this.activeDialCode !== '') {
        return '';
      }
      return this.activeDialCode
        ? `${this.activeDialCode}${this.phoneNumber}`
        : '';
    },
  },
  watch: {
    contact() {
      this.setContactObject();
    },
  },
  async mounted() {
    this.setContactObject();
    this.setDialCode();
    const response = await calendarioPayersAPI.get();
    this.payers = response.data;
  },
  methods: {
    onCancel() {
      this.$emit('cancel');
    },
    onSuccess() {
      this.$emit('success');
    },
    countryNameWithCode({ name, id }) {
      if (!id) return name;
      if (!name && !id) return '';
      return `${name} (${id})`;
    },
    onCountryChange(value) {
      const selected = this.countries.find(c => c.id === value);
      this.country = selected
        ? { id: selected.id, name: selected.name }
        : { id: '', name: '' };
    },
    setDialCode() {
      if (
        this.phoneNumber !== '' &&
        this.parsePhoneNumber &&
        this.parsePhoneNumber.countryCallingCode
      ) {
        const dialCode = this.parsePhoneNumber.countryCallingCode;
        this.activeDialCode = `+${dialCode}`;
      }
    },
    setContactObject() {
      const {
        email: emailAddress,
        phone_number: phoneNumber,
        name,
      } = this.contact;
      const additionalAttributes = this.contact.additional_attributes || {};
      const customAttributes = this.contact.custom_attributes || {};
      const isNewContact = !this.contact.id;

      this.name = name || '';
      this.email = emailAddress || '';
      this.phoneNumber = phoneNumber || '';
      this.documentType = this.contact.document_type || 'cc';
      this.identifier = this.contact.identifier || '';
      this.secondaryPhoneNumber = this.contact.secondary_phone_number || '';
      this.dateOfBirth = customAttributes.date_of_birth || '';
      this.payerId = this.contact.payer_id || '';
      this.country = isNewContact
        ? { id: DEFAULT_COUNTRY.id, name: DEFAULT_COUNTRY.name }
        : {
            id: additionalAttributes.country_code || '',
            name:
              additionalAttributes.country ||
              this.$t('CONTACT_FORM.FORM.COUNTRY.SELECT_COUNTRY'),
          };
      this.city = additionalAttributes.city || '';
    },
    getContactObject() {
      if (this.country === null) {
        this.country = {
          id: '',
          name: '',
        };
      }
      const contactObject = {
        id: this.contact.id,
        name: this.name,
        email: this.email,
        phone_number: this.setPhoneNumber,
        document_type: this.documentType,
        identifier: this.identifier,
        secondary_phone_number: this.secondaryPhoneNumber,
        payer_id: this.payerId || null,
        custom_attributes: {
          ...this.contact.custom_attributes,
          date_of_birth: this.dateOfBirth,
        },
        additional_attributes: {
          ...this.contact.additional_attributes,
          country_code: this.country.id,
          country:
            this.country.name ===
            this.$t('CONTACT_FORM.FORM.COUNTRY.SELECT_COUNTRY')
              ? ''
              : this.country.name,
          city: this.city,
        },
      };
      return contactObject;
    },
    setPhoneCode(code) {
      if (this.phoneNumber !== '' && this.parsePhoneNumber) {
        const dialCode = this.parsePhoneNumber.countryCallingCode;
        if (dialCode === code) {
          return;
        }
        this.activeDialCode = `+${dialCode}`;
        const newPhoneNumber = this.phoneNumber.replace(
          `+${dialCode}`,
          `${code}`
        );
        this.phoneNumber = newPhoneNumber;
      } else {
        this.activeDialCode = code;
      }
    },
    async handleSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid || this.isPhoneNumberNotValid) {
        return;
      }
      try {
        await this.onSubmit(this.getContactObject());
        this.onSuccess();
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          if (error.data.includes('email')) {
            useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
          } else if (error.data.includes('phone_number')) {
            useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
  },
};
</script>

<template>
  <form
    class="w-full px-8 pt-6 pb-8 contact--form"
    @submit.prevent="handleSubmit"
  >
    <div>
      <div class="w-full">
        <label :class="{ error: v$.name.$error }">
          {{ $t('CONTACT_FORM.FORM.NAME.LABEL') }}
          <input
            v-model="name"
            type="text"
            :placeholder="$t('CONTACT_FORM.FORM.NAME.PLACEHOLDER')"
            @input="v$.name.$touch"
          />
        </label>

        <label :class="{ error: v$.email.$error }">
          {{ $t('CONTACT_FORM.FORM.EMAIL_ADDRESS.LABEL') }}
          <input
            v-model="email"
            type="text"
            :placeholder="$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.PLACEHOLDER')"
            @input="v$.email.$touch"
          />
          <span v-if="v$.email.$error" class="message">
            {{ $t('CONTACT_FORM.FORM.EMAIL_ADDRESS.ERROR') }}
          </span>
        </label>
      </div>
    </div>
    <div>
      <div class="w-full">
        <label
          :class="{
            error: isPhoneNumberNotValid,
          }"
        >
          {{ $t('CONTACT_FORM.FORM.PHONE_NUMBER.LABEL') }}
          <woot-phone-input
            v-model="phoneNumber"
            :value="phoneNumber"
            :error="isPhoneNumberNotValid"
            :placeholder="$t('CONTACT_FORM.FORM.PHONE_NUMBER.PLACEHOLDER')"
            @blur="v$.phoneNumber.$touch"
            @set-code="setPhoneCode"
          />
          <span v-if="isPhoneNumberNotValid" class="message">
            {{ phoneNumberError }}
          </span>
        </label>
        <div
          v-if="isPhoneNumberNotValid || !phoneNumber"
          class="relative mx-0 mt-0 mb-2.5 p-2 rounded-md text-sm border border-solid border-n-amber-5 text-n-amber-12 bg-n-amber-3"
        >
          {{ $t('CONTACT_FORM.FORM.PHONE_NUMBER.HELP') }}
        </div>
      </div>
    </div>
    <woot-input
      v-model="secondaryPhoneNumber"
      class="w-full"
      :label="$t('CONTACT_FORM.FORM.SECONDARY_PHONE_NUMBER.LABEL')"
      :placeholder="$t('CONTACT_FORM.FORM.SECONDARY_PHONE_NUMBER.PLACEHOLDER')"
    />
    <div class="flex gap-2 w-full">
      <label class="w-1/3">
        {{ $t('CONTACT_FORM.FORM.DOCUMENT_TYPE.LABEL') }}
        <select v-model="documentType" class="mb-4">
          <option
            v-for="option in documentTypeOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </label>
      <woot-input
        v-model="identifier"
        class="w-2/3"
        :label="$t('CONTACT_FORM.FORM.DOCUMENT_NUMBER.LABEL')"
        :placeholder="$t('CONTACT_FORM.FORM.DOCUMENT_NUMBER.PLACEHOLDER')"
      />
    </div>
    <div class="w-full mb-4">
      <label>
        {{ $t('CONTACT_FORM.FORM.PAYER.LABEL') }}
      </label>
      <select v-model="payerId" class="mb-0">
        <option value="">
          {{ $t('CONTACT_FORM.FORM.PAYER.PLACEHOLDER') }}
        </option>
        <option
          v-for="option in payerOptions"
          :key="option.value"
          :value="option.value"
        >
          {{ option.label }}
        </option>
      </select>
    </div>
    <div class="w-full mb-4">
      <label>
        {{ $t('CONTACT_FORM.FORM.BIRTH_DATE.LABEL') }}
        <input v-model="dateOfBirth" type="date" class="reset-base !mb-0" />
      </label>
    </div>
    <woot-input
      v-model="city"
      class="w-full"
      :label="$t('CONTACT_FORM.FORM.CITY.LABEL')"
      :placeholder="$t('CONTACT_FORM.FORM.CITY.PLACEHOLDER')"
    />
    <div class="w-full mb-4">
      <label>
        {{ $t('CONTACT_FORM.FORM.COUNTRY.LABEL') }}
      </label>
      <ComboBox
        :model-value="country.id"
        :options="
          countries.map(c => ({
            value: c.id,
            label: countryNameWithCode(c),
          }))
        "
        class="[&>div>button]:!bg-n-alpha-black2"
        :placeholder="$t('CONTACT_FORM.FORM.COUNTRY.PLACEHOLDER')"
        :search-placeholder="$t('CONTACT_FORM.FORM.COUNTRY.SELECT_PLACEHOLDER')"
        @update:model-value="onCountryChange"
      />
    </div>
    <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
      <NextButton
        type="submit"
        :label="$t('CONTACT_FORM.FORM.SUBMIT')"
        :is-loading="inProgress"
      />
      <NextButton
        faded
        slate
        type="reset"
        :label="$t('CONTACT_FORM.FORM.CANCEL')"
        @click.prevent="onCancel"
      />
    </div>
  </form>
</template>
