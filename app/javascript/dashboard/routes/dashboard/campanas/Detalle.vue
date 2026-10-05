<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'shared/components/Spinner.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';
import InboxesAPI from 'dashboard/api/inboxes';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import campanaAPI from 'dashboard/api/cartera/campanas';
import plantillaEmailAPI from 'dashboard/api/cartera/plantillasEmail';

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();
const store = useStore();

const campanaId = computed(() => route.params.campanaId);

/* ---------- Datos generales ---------- */

const isLoading = ref(true);
const isSaving = ref(false);
const campana = ref(null);

const DIAS = [1, 2, 3, 4, 5, 6]; // lunes a sabado - domingo nunca se ofrece (Ley 2300)
const DIA_LABELS = {
  1: 'LUN',
  2: 'MAR',
  3: 'MIE',
  4: 'JUE',
  5: 'VIE',
  6: 'SAB',
};

const form = reactive({
  nombre: '',
  estado: 'borrador',
  inbox_whatsapp_id: null,
  inbox_email_id: null,
  captain_assistant_id: null,
  hora_inicio: '07:00',
  hora_fin: '19:00',
  dias_envio: [],
  autorizacion_fuente: '',
  autorizacion_detalle: '',
});

const inboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...inboxes.value
    .filter(
      inbox =>
        inbox.channel_type === INBOX_TYPES.WHATSAPP ||
        (inbox.channel_type === INBOX_TYPES.TWILIO &&
          inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
    )
    .map(inbox => ({ value: String(inbox.id), label: inbox.name })),
]);
const emailInboxOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...inboxes.value
    .filter(inbox => inbox.channel_type === INBOX_TYPES.EMAIL)
    .map(inbox => ({ value: String(inbox.id), label: inbox.name })),
]);

const assistants = useMapGetter('captainAssistants/getRecords');
const assistantOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...assistants.value.map(assistant => ({
    value: String(assistant.id),
    label: assistant.name,
  })),
]);

const fuenteOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  {
    value: 'politica_privacidad',
    label: t('CARTERA.CAMPANAS.FUENTES.POLITICA_PRIVACIDAD'),
  },
  {
    value: 'terminos_condiciones',
    label: t('CARTERA.CAMPANAS.FUENTES.TERMINOS_CONDICIONES'),
  },
  { value: 'contrato', label: t('CARTERA.CAMPANAS.FUENTES.CONTRATO') },
  { value: 'otro', label: t('CARTERA.CAMPANAS.FUENTES.OTRO') },
]);

const estadoOptions = computed(() => [
  { value: 'borrador', label: t('CARTERA.CAMPANAS.ESTADOS.BORRADOR') },
  { value: 'activa', label: t('CARTERA.CAMPANAS.ESTADOS.ACTIVA') },
  { value: 'pausada', label: t('CARTERA.CAMPANAS.ESTADOS.PAUSADA') },
  { value: 'archivada', label: t('CARTERA.CAMPANAS.ESTADOS.ARCHIVADA') },
]);

const diaChecked = dia => form.dias_envio.includes(dia);
const toggleDia = dia => {
  form.dias_envio = diaChecked(dia)
    ? form.dias_envio.filter(d => d !== dia)
    : [...form.dias_envio, dia].sort();
};

const loadForm = () => {
  form.nombre = campana.value.nombre;
  form.estado = campana.value.estado;
  form.inbox_whatsapp_id = campana.value.inbox_whatsapp_id
    ? String(campana.value.inbox_whatsapp_id)
    : '';
  form.inbox_email_id = campana.value.inbox_email_id
    ? String(campana.value.inbox_email_id)
    : '';
  form.captain_assistant_id = campana.value.captain_assistant_id
    ? String(campana.value.captain_assistant_id)
    : '';
  form.hora_inicio =
    (campana.value.hora_inicio || '').slice(11, 16) ||
    campana.value.hora_inicio;
  form.hora_fin =
    (campana.value.hora_fin || '').slice(11, 16) || campana.value.hora_fin;
  form.dias_envio = [...(campana.value.dias_envio || [])];
  form.autorizacion_fuente = campana.value.autorizacion_fuente || '';
  form.autorizacion_detalle = campana.value.autorizacion_detalle || '';
};

const fetchCampana = async () => {
  const { data } = await campanaAPI.show(campanaId.value);
  campana.value = data;
  loadForm();
};

const guardar = async () => {
  isSaving.value = true;
  try {
    const payload = {
      ...form,
      inbox_whatsapp_id: form.inbox_whatsapp_id || null,
      inbox_email_id: form.inbox_email_id || null,
      captain_assistant_id: form.captain_assistant_id || null,
    };
    const { data } = await campanaAPI.update(campanaId.value, payload);
    campana.value = data;
    loadForm();
    useAlert(t('CARTERA.CAMPANAS.GUARDADA_EXITOSA'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CARTERA.CAMPANAS.GUARDAR_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

/* ---------- Reglas ---------- */

const ATRIBUTOS = [
  'tramo',
  'dias_vencido_max',
  'puntaje_riesgo',
  'score_credito',
  'saldo_abierto',
  'antiguedad_relacion_dias',
  'tipo_deudor',
];
const OPERADORES = [
  'equal_to',
  'not_equal_to',
  'is_greater_than',
  'is_less_than',
  'is_present',
  'is_not_present',
];

const reglas = ref([]);
const isLoadingReglas = ref(false);
const fetchReglas = async () => {
  isLoadingReglas.value = true;
  try {
    const { data } = await campanaAPI.getReglas(campanaId.value);
    reglas.value = data;
  } finally {
    isLoadingReglas.value = false;
  }
};

const plantillasEmail = ref([]);
const fetchPlantillasEmail = async () => {
  const { data } = await plantillaEmailAPI.get();
  plantillasEmail.value = data;
};
const plantillaEmailOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...plantillasEmail.value.map(plantilla => ({
    value: String(plantilla.id),
    label: plantilla.nombre,
  })),
]);

const templatesWhatsapp = ref([]);
const fetchTemplatesWhatsapp = async () => {
  if (!form.inbox_whatsapp_id) {
    templatesWhatsapp.value = [];
    return;
  }
  const { data } = await InboxesAPI.getMessageTemplates(form.inbox_whatsapp_id);
  templatesWhatsapp.value = (data.payload || []).filter(
    template => (template.status || '').toLowerCase() === 'approved'
  );
};
const plantillaWhatsappOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...templatesWhatsapp.value.map(template => ({
    value: template.content_sid,
    label: template.name || template.friendly_name,
  })),
]);

const reglaDialogRef = ref(null);
const isSavingRegla = ref(false);
const editingReglaId = ref(null);
const reglaForm = reactive({
  orden: 1,
  accion: 'enviar',
  sinCondicion: true,
  attribute_key: 'tramo',
  filter_operator: 'equal_to',
  value: '',
  plantilla_whatsapp_content_sid: '',
  plantilla_email_id: '',
});

const abrirNuevaRegla = () => {
  editingReglaId.value = null;
  reglaForm.orden = reglas.value.length + 1;
  reglaForm.accion = 'enviar';
  reglaForm.sinCondicion = true;
  reglaForm.attribute_key = 'tramo';
  reglaForm.filter_operator = 'equal_to';
  reglaForm.value = '';
  reglaForm.plantilla_whatsapp_content_sid = '';
  reglaForm.plantilla_email_id = '';
  reglaDialogRef.value?.open();
};

const abrirEditarRegla = regla => {
  editingReglaId.value = regla.id;
  reglaForm.orden = regla.orden;
  reglaForm.accion = regla.accion;
  const condiciones = regla.condiciones || {};
  reglaForm.sinCondicion = !condiciones.attribute_key;
  reglaForm.attribute_key = condiciones.attribute_key || 'tramo';
  reglaForm.filter_operator = condiciones.filter_operator || 'equal_to';
  reglaForm.value = condiciones.values ? condiciones.values[0] : '';
  reglaForm.plantilla_whatsapp_content_sid =
    regla.plantilla_whatsapp_content_sid || '';
  reglaForm.plantilla_email_id = regla.plantilla_email_id
    ? String(regla.plantilla_email_id)
    : '';
  reglaDialogRef.value?.open();
};

const condicionesPayload = () => {
  if (reglaForm.sinCondicion) return {};
  const necesitaValor = !['is_present', 'is_not_present'].includes(
    reglaForm.filter_operator
  );
  return {
    attribute_key: reglaForm.attribute_key,
    filter_operator: reglaForm.filter_operator,
    values: necesitaValor ? [reglaForm.value] : [],
  };
};

const guardarRegla = async () => {
  isSavingRegla.value = true;
  const payload = {
    orden: reglaForm.orden,
    accion: reglaForm.accion,
    condiciones: condicionesPayload(),
    plantilla_whatsapp_content_sid:
      reglaForm.plantilla_whatsapp_content_sid || null,
    plantilla_email_id: reglaForm.plantilla_email_id || null,
  };
  try {
    if (editingReglaId.value) {
      await campanaAPI.updateRegla(
        campanaId.value,
        editingReglaId.value,
        payload
      );
    } else {
      await campanaAPI.createRegla(campanaId.value, payload);
    }
    useAlert(t('CARTERA.CAMPANAS.REGLAS.GUARDADA_EXITOSA'));
    reglaDialogRef.value?.close();
    await fetchReglas();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CARTERA.CAMPANAS.REGLAS.GUARDAR_ERROR')
    );
  } finally {
    isSavingRegla.value = false;
  }
};

const eliminarRegla = async regla => {
  try {
    await campanaAPI.deleteRegla(campanaId.value, regla.id);
    await fetchReglas();
  } catch {
    useAlert(t('CARTERA.CAMPANAS.REGLAS.ELIMINAR_ERROR'));
  }
};

const resumenPlantillas = regla => {
  const partes = [];
  if (regla.plantilla_whatsapp_content_sid) {
    partes.push(
      t('CARTERA.CAMPANAS.REGLAS.TIENE_WHATSAPP', {
        sid: regla.plantilla_whatsapp_content_sid,
      })
    );
  }
  if (regla.plantilla_email_id) {
    partes.push(t('CARTERA.CAMPANAS.REGLAS.TIENE_EMAIL'));
  }
  return partes.join(' · ');
};

const resumenCondicion = regla => {
  const condiciones = regla.condiciones || {};
  if (!condiciones.attribute_key) {
    return t('CARTERA.CAMPANAS.REGLAS.SIN_CONDICION');
  }
  const valor = condiciones.values?.[0];
  return `${condiciones.attribute_key} ${condiciones.filter_operator}${valor ? ` ${valor}` : ''}`;
};

/* ---------- Simulacion ---------- */

const isSimulating = ref(false);
const simulacion = ref(null);

const formatoMoneda = valor => `$${valor}`;
const textoPlantillaNoLista = computed(
  () => `· ${t('CARTERA.CAMPANAS.SIMULACION.PLANTILLA_NO_LISTA')}`
);
const resumenFila = fila =>
  [
    `#${fila.orden} (${fila.accion}) —`,
    `${fila.cantidad_clientes} ${t('CARTERA.CAMPANAS.SIMULACION.CLIENTES')},`,
    `${fila.cantidad_excluidos} ${t('CARTERA.CAMPANAS.SIMULACION.EXCLUIDOS')},`,
    formatoMoneda(fila.costo_estimado),
  ].join(' ');

const simular = async () => {
  isSimulating.value = true;
  try {
    const { data } = await campanaAPI.simular(campanaId.value);
    simulacion.value = data;
  } catch {
    useAlert(t('CARTERA.CAMPANAS.SIMULACION.ERROR'));
  } finally {
    isSimulating.value = false;
  }
};

/* ---------- Bitacora ---------- */

const envios = ref([]);
const isLoadingEnvios = ref(false);
const fetchEnvios = async () => {
  isLoadingEnvios.value = true;
  try {
    const { data } = await campanaAPI.getEnvios(campanaId.value);
    envios.value = data;
  } finally {
    isLoadingEnvios.value = false;
  }
};

onMounted(async () => {
  isLoading.value = true;
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('captainAssistants/get'),
      fetchCampana(),
      fetchPlantillasEmail(),
      fetchReglas(),
      fetchEnvios(),
    ]);
    await fetchTemplatesWhatsapp();
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div>
    <CarteraHeader
      :header-title="campana ? campana.nombre : ''"
      has-back-button
      :back-url="{ name: 'cartera_campanas_view' }"
    >
      <Button
        v-if="isAdmin"
        :label="t('CARTERA.CAMPANAS.GUARDAR')"
        size="sm"
        :is-loading="isSaving"
        @click="guardar"
      />
    </CarteraHeader>

    <div v-if="isLoading" class="flex items-center justify-center py-16">
      <Spinner />
    </div>

    <div v-else class="flex flex-col gap-6">
      <!-- Datos generales -->
      <TableCard>
        <div class="flex flex-col gap-4 p-5">
          <Input
            v-model="form.nombre"
            :label="t('CARTERA.CAMPANAS.FORM.NOMBRE')"
          />

          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.FORM.ESTADO') }}
            </label>
            <Select v-model="form.estado" :options="estadoOptions" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="flex flex-col gap-1">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.FORM.INBOX_WHATSAPP') }}
              </label>
              <Select
                v-model="form.inbox_whatsapp_id"
                :options="whatsappInboxOptions"
                @update:model-value="fetchTemplatesWhatsapp"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.FORM.INBOX_EMAIL') }}
              </label>
              <Select
                v-model="form.inbox_email_id"
                :options="emailInboxOptions"
              />
            </div>
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.FORM.CAPTAIN_ASSISTANT') }}
            </label>
            <Select
              v-model="form.captain_assistant_id"
              :options="assistantOptions"
            />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <Input
              v-model="form.hora_inicio"
              type="time"
              :label="t('CARTERA.CAMPANAS.FORM.HORA_INICIO')"
            />
            <Input
              v-model="form.hora_fin"
              type="time"
              :label="t('CARTERA.CAMPANAS.FORM.HORA_FIN')"
            />
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.FORM.DIAS_ENVIO') }}
            </label>
            <div class="flex items-center gap-4 flex-wrap">
              <label
                v-for="dia in DIAS"
                :key="dia"
                class="flex items-center gap-1.5 text-sm text-n-slate-12"
              >
                <Checkbox
                  :model-value="diaChecked(dia)"
                  @change="toggleDia(dia)"
                />
                {{ DIA_LABELS[dia] }}
              </label>
            </div>
            <p class="text-xs text-n-slate-10 mb-0">
              {{ t('CARTERA.CAMPANAS.FORM.DIAS_AYUDA') }}
            </p>
          </div>
        </div>
      </TableCard>

      <!-- Autorizacion -->
      <TableCard>
        <div class="flex flex-col gap-4 p-5">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.AUTORIZACION.TITLE') }}
          </h3>
          <div
            class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-11"
          >
            {{ t('CARTERA.CAMPANAS.AUTORIZACION.ALERTA_LEGAL') }}
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.AUTORIZACION.FUENTE') }}
            </label>
            <Select
              v-model="form.autorizacion_fuente"
              :options="fuenteOptions"
            />
          </div>
          <TextArea
            v-model="form.autorizacion_detalle"
            :label="t('CARTERA.CAMPANAS.AUTORIZACION.DETALLE')"
            auto-height
          />
          <p
            v-if="campana?.autorizacion_confirmada_at"
            class="text-xs text-n-slate-10 mb-0"
          >
            {{
              t('CARTERA.CAMPANAS.AUTORIZACION.CONFIRMADA', {
                fecha: new Date(
                  campana.autorizacion_confirmada_at
                ).toLocaleString(),
              })
            }}
          </p>
        </div>
      </TableCard>

      <!-- Reglas -->
      <div>
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.REGLAS.TITLE') }}
          </h3>
          <Button
            v-if="isAdmin"
            icon="i-lucide-plus"
            size="sm"
            slate
            faded
            :label="t('CARTERA.CAMPANAS.REGLAS.NUEVA')"
            @click="abrirNuevaRegla"
          />
        </div>
        <TableCard v-if="reglas.length">
          <div class="divide-y divide-n-weak">
            <div
              v-for="regla in reglas"
              :key="regla.id"
              class="flex items-center justify-between gap-4 py-3 px-5"
            >
              <div class="flex flex-col min-w-0 gap-1">
                <div class="flex items-center gap-2">
                  <span class="text-body-main font-medium text-n-slate-12">
                    #{{ regla.orden }}
                  </span>
                  <span
                    class="inline-block rounded-full border px-2 py-0.5 text-xs"
                    :class="
                      regla.accion === 'excluir'
                        ? 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11'
                        : 'border-n-teal-6 bg-n-teal-3 text-n-teal-11'
                    "
                  >
                    {{
                      t(
                        `CARTERA.CAMPANAS.REGLAS.ACCIONES.${regla.accion.toUpperCase()}`
                      )
                    }}
                  </span>
                </div>
                <span class="text-body-main text-n-slate-11">
                  {{ resumenCondicion(regla) }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ resumenPlantillas(regla) }}
                </span>
              </div>
              <div v-if="isAdmin" class="flex items-center gap-2 shrink-0">
                <Button
                  icon="i-lucide-pencil"
                  size="sm"
                  slate
                  faded
                  @click="abrirEditarRegla(regla)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  size="sm"
                  ruby
                  faded
                  @click="eliminarRegla(regla)"
                />
              </div>
            </div>
          </div>
        </TableCard>
        <p v-else-if="!isLoadingReglas" class="text-body-main text-n-slate-11">
          {{ t('CARTERA.CAMPANAS.REGLAS.EMPTY_STATE') }}
        </p>
      </div>

      <!-- Simulacion -->
      <div>
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.SIMULACION.TITLE') }}
          </h3>
          <Button
            icon="i-lucide-play"
            size="sm"
            slate
            faded
            :label="t('CARTERA.CAMPANAS.SIMULACION.SIMULAR')"
            :is-loading="isSimulating"
            @click="simular"
          />
        </div>
        <TableCard v-if="simulacion">
          <div class="flex flex-col gap-3 p-5">
            <p
              v-if="simulacion.advertencia_frecuencia"
              class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-11 mb-0"
            >
              {{ simulacion.advertencia_frecuencia }}
            </p>
            <div class="grid grid-cols-3 gap-4 text-center">
              <div>
                <p class="text-heading-1 text-n-slate-12 m-0">
                  {{ simulacion.resumen.total_casos_evaluados }}
                </p>
                <p class="text-xs text-n-slate-10 m-0">
                  {{ t('CARTERA.CAMPANAS.SIMULACION.EVALUADOS') }}
                </p>
              </div>
              <div>
                <p class="text-heading-1 text-n-teal-11 m-0">
                  {{ simulacion.resumen.total_a_enviar }}
                </p>
                <p class="text-xs text-n-slate-10 m-0">
                  {{ t('CARTERA.CAMPANAS.SIMULACION.A_ENVIAR') }}
                </p>
              </div>
              <div>
                <p class="text-heading-1 text-n-slate-12 m-0">
                  {{ formatoMoneda(simulacion.resumen.costo_total_estimado) }}
                </p>
                <p class="text-xs text-n-slate-10 m-0">
                  {{ t('CARTERA.CAMPANAS.SIMULACION.COSTO') }}
                </p>
              </div>
            </div>
            <div class="divide-y divide-n-weak border-t border-n-weak">
              <div
                v-for="fila in simulacion.por_regla"
                :key="fila.regla_id"
                class="py-2 text-sm text-n-slate-12"
              >
                {{ resumenFila(fila) }}
                <span
                  v-if="fila.plantilla_whatsapp_lista === false"
                  class="text-n-ruby-11"
                >
                  {{ textoPlantillaNoLista }}
                </span>
              </div>
            </div>
          </div>
        </TableCard>
      </div>

      <!-- Bitacora -->
      <div>
        <h3 class="text-heading-3 text-n-slate-12 mb-2">
          {{ t('CARTERA.CAMPANAS.BITACORA.TITLE') }}
        </h3>
        <TableCard v-if="envios.length">
          <div class="divide-y divide-n-weak">
            <div
              v-for="envio in envios"
              :key="envio.id"
              class="flex items-center justify-between gap-4 py-2 px-5 text-sm"
            >
              <span class="text-n-slate-12 truncate">{{
                envio.nombre_cliente
              }}</span>
              <span class="text-n-slate-11">{{ envio.canal || '—' }}</span>
              <span class="text-n-slate-11">{{ envio.estado }}</span>
              <span class="text-n-slate-10 truncate max-w-xs">{{
                envio.razon_omision || envio.resultado || ''
              }}</span>
              <span class="text-n-slate-10 shrink-0">{{
                new Date(envio.created_at).toLocaleString()
              }}</span>
            </div>
          </div>
        </TableCard>
        <p v-else-if="!isLoadingEnvios" class="text-body-main text-n-slate-11">
          {{ t('CARTERA.CAMPANAS.BITACORA.EMPTY_STATE') }}
        </p>
      </div>
    </div>

    <Dialog
      ref="reglaDialogRef"
      :title="t('CARTERA.CAMPANAS.REGLAS.NUEVA')"
      :confirm-button-label="t('CARTERA.CAMPANAS.GUARDAR')"
      :is-loading="isSavingRegla"
      @confirm="guardarRegla"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model.number="reglaForm.orden"
          type="number"
          :label="t('CARTERA.CAMPANAS.REGLAS.FORM.ORDEN')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{ t('CARTERA.CAMPANAS.REGLAS.FORM.ACCION') }}
          </label>
          <Select
            v-model="reglaForm.accion"
            :options="[
              {
                value: 'enviar',
                label: t('CARTERA.CAMPANAS.REGLAS.ACCIONES.ENVIAR'),
              },
              {
                value: 'excluir',
                label: t('CARTERA.CAMPANAS.REGLAS.ACCIONES.EXCLUIR'),
              },
            ]"
          />
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Checkbox v-model="reglaForm.sinCondicion" />
          {{ t('CARTERA.CAMPANAS.REGLAS.FORM.SIN_CONDICION') }}
        </label>

        <div
          v-if="!reglaForm.sinCondicion"
          class="flex flex-col gap-3 border-s-2 border-n-weak ps-3"
        >
          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.REGLAS.FORM.ATRIBUTO') }}
            </label>
            <Select
              v-model="reglaForm.attribute_key"
              :options="ATRIBUTOS.map(a => ({ value: a, label: a }))"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.REGLAS.FORM.OPERADOR') }}
            </label>
            <Select
              v-model="reglaForm.filter_operator"
              :options="OPERADORES.map(o => ({ value: o, label: o }))"
            />
          </div>
          <Input
            v-if="
              !['is_present', 'is_not_present'].includes(
                reglaForm.filter_operator
              )
            "
            v-model="reglaForm.value"
            :label="t('CARTERA.CAMPANAS.REGLAS.FORM.VALOR')"
          />
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{ t('CARTERA.CAMPANAS.REGLAS.FORM.PLANTILLA_WHATSAPP') }}
          </label>
          <Select
            v-model="reglaForm.plantilla_whatsapp_content_sid"
            :options="plantillaWhatsappOptions"
          />
          <p
            v-if="!templatesWhatsapp.length"
            class="text-xs text-n-slate-10 mb-0"
          >
            {{ t('CARTERA.CAMPANAS.REGLAS.FORM.SIN_PLANTILLAS_WHATSAPP') }}
          </p>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{ t('CARTERA.CAMPANAS.REGLAS.FORM.PLANTILLA_EMAIL') }}
          </label>
          <Select
            v-model="reglaForm.plantilla_email_id"
            :options="plantillaEmailOptions"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
