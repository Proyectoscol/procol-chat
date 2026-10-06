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
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import campanaAPI from 'dashboard/api/cartera/campanas';
import plantillaEmailAPI from 'dashboard/api/cartera/plantillasEmail';

const { t } = useI18n();
const route = useRoute();
const { isAdmin } = useAdmin();
const store = useStore();

const campanaId = computed(() => route.params.campanaId);

/* ---------- Pestanas ---------- */

const TAB_VALUES = [
  'datos',
  'canales',
  'bandas',
  'autorizacion',
  'simulacion',
  'pruebas',
  'bitacora',
  'estadisticas',
];
const activeTab = ref('datos');
const tabs = computed(() =>
  TAB_VALUES.map(value => ({
    value,
    label: t(`CARTERA.CAMPANAS.TABS.${value.toUpperCase()}`),
  }))
);
const activeTabIndex = computed(() => TAB_VALUES.indexOf(activeTab.value));
const handleTabChange = tab => {
  activeTab.value = tab.value;
};

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
  dias_envio: [],
  // Hora exacta de envio por dia de la semana (clave = dia, '1'..'6') -
  // reemplaza el viejo rango unico hora_inicio/hora_fin, que no dejaba
  // claro a que momento se mandaba el mensaje.
  horas_envio: {},
  autorizacion_fuente: '',
  autorizacion_detalle: '',
});
const HORA_POR_DEFECTO = '08:00';

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

// Que canales explicar en Autorizacion - nunca se usan los dos a la vez
// (ver Cartera::Campanas::CorridaService#resolver_canal): WhatsApp primero,
// correo solo si el cliente no tiene WhatsApp clasificable o esta
// bloqueado.
const resumenCanalesKey = computed(() => {
  const tieneWhatsapp = Boolean(form.inbox_whatsapp_id);
  const tieneEmail = Boolean(form.inbox_email_id);
  if (tieneWhatsapp && tieneEmail) return 'CON_FALLBACK';
  if (tieneWhatsapp) return 'SOLO_WHATSAPP';
  if (tieneEmail) return 'SOLO_EMAIL';
  return 'SIN_CANALES';
});

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
  if (!diaChecked(dia) && !form.horas_envio[dia]) {
    form.horas_envio[dia] = HORA_POR_DEFECTO;
  }
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
  form.dias_envio = [...(campana.value.dias_envio || [])];
  form.horas_envio = { ...(campana.value.horas_envio || {}) };
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
      // Solo los dias activos - una hora que quedo guardada de un dia que
      // el usuario desmarco (por si lo reactiva sin perder lo que escribio)
      // nunca debe llegar al backend como si siguiera activa.
      horas_envio: Object.fromEntries(
        form.dias_envio
          .filter(dia => form.horas_envio[dia])
          .map(dia => [dia, form.horas_envio[dia]])
      ),
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
// Valores enum de Cartera::AgingCalculator::TRAMOS y Cartera::Cliente#tipo_deudor
// - los mismos que guarda el backend en condiciones.values, para que el
// selector de valor nunca dependa de que el usuario teclee el nombre interno.
const TRAMO_VALUES = [
  'vigente',
  'd1_30',
  'd31_60',
  'd61_90',
  'd91_180',
  'd181_360',
  'mas_360',
];
const TIPO_DEUDOR_VALUES = ['persona_natural', 'empresa', 'mixto'];

const atributoOptions = computed(() =>
  ATRIBUTOS.map(atributo => ({
    value: atributo,
    label: t(
      `CARTERA.CAMPANAS.REGLAS.FORM.ATRIBUTOS.${atributo.toUpperCase()}`
    ),
  }))
);
const operadorOptions = computed(() =>
  OPERADORES.map(operador => ({
    value: operador,
    label: t(`FILTER.OPERATOR_LABELS.${operador}`),
  }))
);
const tramoValorOptions = computed(() =>
  TRAMO_VALUES.map(valor => ({
    value: valor,
    label: t(`CARTERA.TRAMOS.${valor.toUpperCase()}`),
  }))
);
const tipoDeudorValorOptions = computed(() =>
  TIPO_DEUDOR_VALUES.map(valor => ({
    value: valor,
    label: t(
      `CARTERA.CAMPANAS.REGLAS.FORM.TIPO_DEUDOR_VALORES.${valor.toUpperCase()}`
    ),
  }))
);

const atributoLabel = atributo =>
  t(`CARTERA.CAMPANAS.REGLAS.FORM.ATRIBUTOS.${atributo.toUpperCase()}`);
const valorLabel = (atributo, valor) => {
  if (!valor) return '';
  if (atributo === 'tramo') return t(`CARTERA.TRAMOS.${valor.toUpperCase()}`);
  if (atributo === 'tipo_deudor') {
    return t(
      `CARTERA.CAMPANAS.REGLAS.FORM.TIPO_DEUDOR_VALORES.${valor.toUpperCase()}`
    );
  }
  return valor;
};

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
  try {
    const { data } = await InboxesAPI.getMessageTemplates(
      form.inbox_whatsapp_id
    );
    templatesWhatsapp.value = (data.payload || []).filter(
      template => (template.status || '').toLowerCase() === 'approved'
    );
  } catch {
    // La bandeja elegida puede no ser un canal de WhatsApp real (ej. datos
    // demo que simulan WhatsApp con un canal API) - sin plantillas para
    // elegir en vez de romper la carga de toda la pagina.
    templatesWhatsapp.value = [];
  }
};
const plantillaWhatsappOptions = computed(() => [
  { value: '', label: t('CARTERA.CAMPANAS.FORM.SIN_SELECCION') },
  ...templatesWhatsapp.value.map(template => ({
    value: template.content_sid,
    label: template.name || template.friendly_name,
  })),
]);

// Una "banda de riesgo" es el caso de uso real de una regla de campana - un
// rango del puntaje de riesgo (0-100) con su plantilla sugerida - expresado
// como un grupo AND de dos condiciones sobre puntaje_riesgo que
// Cartera::Campanas::ReglaMatcher ya sabe evaluar (no es un concepto nuevo
// en el backend, solo una forma mas simple de armar el mismo JSON). El
// modo "personalizada" deja el selector de atributo/operador/valor de
// toda la vida para los casos que no son una banda de puntaje.
const MODO_BANDA = 'banda';
const MODO_PERSONALIZADA = 'personalizada';
const BANDA_ATRIBUTO = 'puntaje_riesgo';

const bandaCondiciones = (min, max) => ({
  operator: 'and',
  conditions: [
    {
      attribute_key: BANDA_ATRIBUTO,
      filter_operator: 'is_greater_than',
      values: [String(min - 1)],
    },
    {
      attribute_key: BANDA_ATRIBUTO,
      filter_operator: 'is_less_than',
      values: [String(max + 1)],
    },
  ],
});

// null si `condiciones` no tiene exactamente esta forma - una regla creada
// a mano con el modo "personalizada" (o con un AND que no es sobre
// puntaje_riesgo) nunca se confunde con una banda.
const bandaDesdeCondiciones = condiciones => {
  const grupo = condiciones?.conditions;
  if (!condiciones?.operator || grupo?.length !== 2) return null;
  if (condiciones.operator.toLowerCase() !== 'and') return null;

  const mayor = grupo.find(
    c =>
      c.attribute_key === BANDA_ATRIBUTO &&
      c.filter_operator === 'is_greater_than'
  );
  const menor = grupo.find(
    c =>
      c.attribute_key === BANDA_ATRIBUTO && c.filter_operator === 'is_less_than'
  );
  if (!mayor || !menor) return null;

  return { min: Number(mayor.values[0]) + 1, max: Number(menor.values[0]) - 1 };
};

// Etiqueta automatica ("Riesgo alto"...) a partir del punto medio del rango -
// los 4 cortes de BANDAS_ARRANQUE son el punto de partida sugerido, pero una
// banda puede tener cualquier rango, asi que la etiqueta usa el punto medio
// en vez de exigir que el rango calce exacto con un corte predefinido.
const severidadBanda = (min, max) => {
  const medio = (min + max) / 2;
  if (medio >= 90) return 'muy_alto';
  if (medio >= 70) return 'alto';
  if (medio >= 40) return 'medio';
  return 'bajo';
};
const severidadLabel = (min, max) =>
  t(
    `CARTERA.CAMPANAS.REGLAS.FORM.SEVERIDAD.${severidadBanda(min, max).toUpperCase()}`
  );
const SEVERIDAD_CLASES = {
  muy_alto: 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11',
  alto: 'border-n-amber-6 bg-n-amber-3 text-n-amber-11',
  medio: 'border-n-slate-6 bg-n-slate-3 text-n-slate-11',
  bajo: 'border-n-teal-6 bg-n-teal-3 text-n-teal-11',
};
const severidadClase = severidad => SEVERIDAD_CLASES[severidad];

// Las 4 bandas de arranque sugeridas (ver seccion 3.2 del plan): cada una
// busca su plantilla de WhatsApp aprobada por coincidencia de nombre contra
// las plantillas de arranque sembradas por db/seeds/
// cartera_plantillas_arranque_seed.rb (prefijo "arranque_") - si la cuenta
// nunca corrio ese seed, o la plantilla aun no fue aprobada por Twilio,
// simplemente no aparece en `templatesWhatsapp` y la banda queda sin
// plantilla preasignada (el usuario la completa a mano).
const BANDAS_ARRANQUE = [
  { min: 90, max: 100, nombrePlantilla: 'prejuridico' },
  { min: 70, max: 89, nombrePlantilla: 'mora_media' },
  { min: 40, max: 69, nombrePlantilla: 'mora_corta' },
  { min: 0, max: 39, nombrePlantilla: null },
];
const buscarPlantillaPorNombre = nombre => {
  if (!nombre) return '';
  const match = templatesWhatsapp.value.find(template =>
    (template.name || '').toLowerCase().includes(nombre)
  );
  return match?.content_sid || '';
};

const reglaDialogRef = ref(null);
const isSavingRegla = ref(false);
const editingReglaId = ref(null);
const reglaForm = reactive({
  orden: 1,
  accion: 'enviar',
  sinCondicion: true,
  modoCondicion: MODO_BANDA,
  puntajeMin: 70,
  puntajeMax: 100,
  attribute_key: 'tramo',
  filter_operator: 'equal_to',
  value: '',
  plantilla_whatsapp_content_sid: '',
  plantilla_email_id: '',
});
const modoCondicionOptions = computed(() => [
  { value: MODO_BANDA, label: t('CARTERA.CAMPANAS.REGLAS.FORM.MODO_BANDA') },
  {
    value: MODO_PERSONALIZADA,
    label: t('CARTERA.CAMPANAS.REGLAS.FORM.MODO_PERSONALIZADA'),
  },
]);

// Aviso (no bloqueo) cuando el rango que se esta editando se solapa con una
// banda de orden MENOR ya guardada - ReglaMatcher.primera_coincidencia solo
// usa la primera regla que hace match por orden, asi que una banda
// solapada con una de orden menor nunca va a aplicar (ver seccion 2 del
// plan "Claridad de campanas y Agente IA").
const bandaQueBloquea = computed(() => {
  if (reglaForm.modoCondicion !== MODO_BANDA || reglaForm.sinCondicion)
    return null;

  const min = Math.min(reglaForm.puntajeMin, reglaForm.puntajeMax);
  const max = Math.max(reglaForm.puntajeMin, reglaForm.puntajeMax);

  return (
    reglas.value
      .filter(
        regla =>
          regla.id !== editingReglaId.value && regla.orden < reglaForm.orden
      )
      .map(regla => ({
        regla,
        banda: bandaDesdeCondiciones(regla.condiciones || {}),
      }))
      .find(({ banda }) => banda && banda.min <= max && min <= banda.max) ||
    null
  );
});

// El selector de valor es un Select (no texto libre) para tramo/tipo_deudor,
// asi que su v-model necesita arrancar en una opcion real del enum - un '' no
// coincide con ninguna y el Select se ve vacio aunque el backend lo trate
// como "sin valor". Solo se reasigna cuando el usuario cambia el atributo a
// mano (ver onAtributoChange) - abrirEditarRegla ya pone el valor guardado.
const valorPorDefectoPara = atributo => {
  if (atributo === 'tramo') return TRAMO_VALUES[0];
  if (atributo === 'tipo_deudor') return TIPO_DEUDOR_VALUES[0];
  return '';
};
const onAtributoChange = atributo => {
  reglaForm.attribute_key = atributo;
  reglaForm.value = valorPorDefectoPara(atributo);
};

const abrirNuevaRegla = () => {
  editingReglaId.value = null;
  reglaForm.orden = reglas.value.length + 1;
  reglaForm.accion = 'enviar';
  reglaForm.sinCondicion = true;
  reglaForm.modoCondicion = MODO_BANDA;
  reglaForm.puntajeMin = 70;
  reglaForm.puntajeMax = 100;
  reglaForm.attribute_key = 'tramo';
  reglaForm.filter_operator = 'equal_to';
  reglaForm.value = valorPorDefectoPara('tramo');
  reglaForm.plantilla_whatsapp_content_sid = '';
  reglaForm.plantilla_email_id = '';
  reglaDialogRef.value?.open();
};

const abrirEditarRegla = regla => {
  editingReglaId.value = regla.id;
  reglaForm.orden = regla.orden;
  reglaForm.accion = regla.accion;
  const condiciones = regla.condiciones || {};
  const banda = bandaDesdeCondiciones(condiciones);
  reglaForm.sinCondicion = !banda && !condiciones.attribute_key;
  reglaForm.modoCondicion = banda ? MODO_BANDA : MODO_PERSONALIZADA;
  reglaForm.puntajeMin = banda?.min ?? 70;
  reglaForm.puntajeMax = banda?.max ?? 100;
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
  if (reglaForm.modoCondicion === MODO_BANDA) {
    const min = Math.min(reglaForm.puntajeMin, reglaForm.puntajeMax);
    const max = Math.max(reglaForm.puntajeMin, reglaForm.puntajeMax);
    return bandaCondiciones(min, max);
  }
  const necesitaValor = !['is_present', 'is_not_present'].includes(
    reglaForm.filter_operator
  );
  return {
    attribute_key: reglaForm.attribute_key,
    filter_operator: reglaForm.filter_operator,
    values: necesitaValor ? [reglaForm.value] : [],
  };
};

const isCreandoBandasArranque = ref(false);
// El orden debe quedar 1,2,3,4 segun se crean - encadena las 4 llamadas en
// vez de dispararlas en paralelo con Promise.all.
const crearRegla = (banda, orden) =>
  campanaAPI.createRegla(campanaId.value, {
    orden,
    accion: 'enviar',
    condiciones: bandaCondiciones(banda.min, banda.max),
    plantilla_whatsapp_content_sid:
      buscarPlantillaPorNombre(banda.nombrePlantilla) || null,
    plantilla_email_id: null,
  });
const crearBandasArranque = async () => {
  isCreandoBandasArranque.value = true;
  try {
    await BANDAS_ARRANQUE.reduce(
      (promesa, banda, index) =>
        promesa.then(() => crearRegla(banda, index + 1)),
      Promise.resolve()
    );
    useAlert(t('CARTERA.CAMPANAS.REGLAS.BANDAS_ARRANQUE_EXITOSA'));
    await fetchReglas();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CARTERA.CAMPANAS.REGLAS.BANDAS_ARRANQUE_ERROR')
    );
    await fetchReglas();
  } finally {
    isCreandoBandasArranque.value = false;
  }
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
  const banda = bandaDesdeCondiciones(condiciones);
  if (banda) {
    return t('CARTERA.CAMPANAS.REGLAS.RESUMEN_BANDA', {
      ...banda,
      severidad: severidadLabel(banda.min, banda.max),
    });
  }
  if (!condiciones.attribute_key) {
    return t('CARTERA.CAMPANAS.REGLAS.SIN_CONDICION');
  }
  const valor = valorLabel(condiciones.attribute_key, condiciones.values?.[0]);
  return [
    atributoLabel(condiciones.attribute_key),
    t(`FILTER.OPERATOR_LABELS.${condiciones.filter_operator}`),
    valor,
  ]
    .filter(Boolean)
    .join(' ');
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

/* ---------- Entorno de pruebas ---------- */

const isProbando = ref(false);
const resultadoPrueba = ref(null);

const probar = async () => {
  isProbando.value = true;
  resultadoPrueba.value = null;
  try {
    const { data } = await campanaAPI.probar(campanaId.value);
    resultadoPrueba.value = data;
    await fetchEnvios();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CARTERA.CAMPANAS.PRUEBA.ERROR')
    );
  } finally {
    isProbando.value = false;
  }
};

/* ---------- Estadisticas ---------- */

const estadisticas = ref(null);
const isLoadingEstadisticas = ref(false);
const fetchEstadisticas = async () => {
  isLoadingEstadisticas.value = true;
  try {
    const { data } = await campanaAPI.getEstadisticas(campanaId.value);
    estadisticas.value = data;
  } finally {
    isLoadingEstadisticas.value = false;
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
      fetchEstadisticas(),
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

    <template v-else>
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        class="mb-6"
        @tab-changed="handleTabChange"
      />

      <!-- Estadisticas -->
      <div v-if="activeTab === 'estadisticas'">
        <div v-if="estadisticas">
          <h3 class="text-heading-3 text-n-slate-12 mb-2">
            {{ t('CARTERA.CAMPANAS.ESTADISTICAS.TITLE') }}
          </h3>
          <TableCard>
            <div class="flex flex-col gap-3 p-5">
              <p
                v-if="estadisticas.semanas_activa !== null"
                class="text-sm text-n-slate-11 mb-0"
              >
                {{
                  t('CARTERA.CAMPANAS.ESTADISTICAS.ACTIVA_DESDE', {
                    semanas: estadisticas.semanas_activa,
                  })
                }}
              </p>
              <p v-else class="text-sm text-n-slate-11 mb-0">
                {{ t('CARTERA.CAMPANAS.ESTADISTICAS.NUNCA_ACTIVADA') }}
              </p>
              <div class="grid grid-cols-3 sm:grid-cols-7 gap-4 text-center">
                <div>
                  <p class="text-heading-1 text-n-teal-11 m-0">
                    {{ estadisticas.mensajes_enviados }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.ENVIADOS') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-slate-12 m-0">
                    {{ estadisticas.mensajes_leidos }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.LEIDOS') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-slate-12 m-0">
                    {{ estadisticas.clientes_alcanzados }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.CLIENTES') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-ruby-11 m-0">
                    {{ estadisticas.total_errores }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.ERRORES') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-slate-12 m-0">
                    {{ estadisticas.conversaciones_contestadas }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.CONTESTARON') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-slate-12 m-0">
                    {{ estadisticas.interacciones_ia_nuevas }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.INTERACCIONES_IA') }}
                  </p>
                </div>
                <div>
                  <p class="text-heading-1 text-n-amber-11 m-0">
                    {{ estadisticas.escalamientos }}
                  </p>
                  <p class="text-xs text-n-slate-10 m-0">
                    {{ t('CARTERA.CAMPANAS.ESTADISTICAS.ESCALAMIENTOS') }}
                  </p>
                </div>
              </div>
              <div
                v-if="estadisticas.errores.length"
                class="flex flex-col gap-1 border-t border-n-weak pt-3"
              >
                <p
                  v-for="error in estadisticas.errores"
                  :key="error.envio_id"
                  class="text-sm text-n-ruby-11 mb-0"
                >
                  {{ error.nombre_cliente }} ({{ error.canal }}):
                  {{
                    error.error ||
                    t('CARTERA.CAMPANAS.ESTADISTICAS.ERROR_SIN_DETALLE')
                  }}
                </p>
              </div>
            </div>
          </TableCard>
        </div>
        <div
          v-else-if="isLoadingEstadisticas"
          class="flex items-center justify-center py-4"
        >
          <Spinner />
        </div>
      </div>

      <!-- Datos basicos -->
      <TableCard v-if="activeTab === 'datos'">
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

          <div class="flex flex-col gap-2">
            <label class="text-sm text-n-slate-12">
              {{ t('CARTERA.CAMPANAS.FORM.DIAS_ENVIO') }}
            </label>
            <p class="text-xs text-n-slate-10 mb-0">
              {{ t('CARTERA.CAMPANAS.FORM.DIAS_AYUDA') }}
            </p>
            <div class="flex flex-col gap-2">
              <div
                v-for="dia in DIAS"
                :key="dia"
                class="flex items-center gap-3"
              >
                <label
                  class="flex items-center gap-1.5 text-sm text-n-slate-12 w-14 shrink-0"
                >
                  <Checkbox
                    :model-value="diaChecked(dia)"
                    @change="toggleDia(dia)"
                  />
                  {{ DIA_LABELS[dia] }}
                </label>
                <input
                  v-if="diaChecked(dia)"
                  type="time"
                  :value="form.horas_envio[dia]"
                  class="rounded-lg border border-n-weak bg-n-alpha-black2 px-2.5 py-1.5 text-sm text-n-slate-12"
                  @input="form.horas_envio[dia] = $event.target.value"
                />
                <span v-else class="text-xs text-n-slate-10">
                  {{ t('CARTERA.CAMPANAS.FORM.DIA_INACTIVO') }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </TableCard>

      <!-- Canales -->
      <TableCard v-if="activeTab === 'canales'">
        <div class="flex flex-col gap-4 p-5">
          <div class="flex flex-col gap-1">
            <div class="flex items-center justify-between gap-2">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.FORM.INBOX_WHATSAPP') }}
              </label>
              <router-link
                :to="{ name: 'settings_inbox_new' }"
                target="_blank"
                class="text-xs text-n-blue-text hover:underline shrink-0"
              >
                {{ t('CARTERA.CAMPANAS.FORM.CREAR_INBOX') }}
              </router-link>
            </div>
            <Select
              v-model="form.inbox_whatsapp_id"
              :options="whatsappInboxOptions"
              @update:model-value="fetchTemplatesWhatsapp"
            />
          </div>
          <div class="flex flex-col gap-1">
            <div class="flex items-center justify-between gap-2">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.FORM.INBOX_EMAIL') }}
              </label>
              <router-link
                :to="{ name: 'settings_inbox_new' }"
                target="_blank"
                class="text-xs text-n-blue-text hover:underline shrink-0"
              >
                {{ t('CARTERA.CAMPANAS.FORM.CREAR_INBOX') }}
              </router-link>
            </div>
            <Select
              v-model="form.inbox_email_id"
              :options="emailInboxOptions"
            />
          </div>
          <div class="flex flex-col gap-1">
            <div class="flex items-center justify-between gap-2">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.FORM.CAPTAIN_ASSISTANT') }}
              </label>
              <router-link
                :to="{ name: 'captain_assistants_create_index' }"
                target="_blank"
                class="text-xs text-n-blue-text hover:underline shrink-0"
              >
                {{ t('CARTERA.CAMPANAS.FORM.CREAR_ASISTENTE') }}
              </router-link>
            </div>
            <Select
              v-model="form.captain_assistant_id"
              :options="assistantOptions"
            />
          </div>
        </div>
      </TableCard>

      <!-- Autorizacion -->
      <TableCard v-if="activeTab === 'autorizacion'">
        <div class="flex flex-col gap-4 p-5">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.AUTORIZACION.TITLE') }}
          </h3>
          <div
            class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-11"
          >
            {{ t('CARTERA.CAMPANAS.AUTORIZACION.ALERTA_LEGAL') }}
          </div>
          <div
            class="rounded-lg border border-n-blue-6 bg-n-blue-3 p-3 text-sm text-n-blue-11"
          >
            {{
              t(`CARTERA.CAMPANAS.AUTORIZACION.CANALES.${resumenCanalesKey}`)
            }}
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
            :placeholder="
              t('CARTERA.CAMPANAS.AUTORIZACION.DETALLE_PLACEHOLDER')
            "
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

      <!-- Reglas (Bandas de riesgo) -->
      <div v-if="activeTab === 'bandas'">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.REGLAS.TITLE') }}
          </h3>
          <div class="flex items-center gap-2">
            <Button
              v-if="isAdmin && !reglas.length && !isLoadingReglas"
              icon="i-lucide-sparkles"
              size="sm"
              slate
              faded
              :label="t('CARTERA.CAMPANAS.REGLAS.BANDAS_ARRANQUE')"
              :is-loading="isCreandoBandasArranque"
              @click="crearBandasArranque"
            />
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
      <div v-if="activeTab === 'simulacion'">
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
        <p class="text-body-main text-n-slate-11">
          {{ t('CARTERA.CAMPANAS.SIMULACION.DESCRIPCION') }}
        </p>
        <TableCard v-if="simulacion">
          <p class="text-xs text-n-slate-10 px-5 pt-4 mb-0">
            {{ t('CARTERA.CAMPANAS.SIMULACION.COSTO_CERO_AYUDA') }}
          </p>
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

      <!-- Entorno de pruebas -->
      <div v-if="activeTab === 'pruebas'">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-heading-3 text-n-slate-12 m-0">
            {{ t('CARTERA.CAMPANAS.PRUEBA.TITLE') }}
          </h3>
          <Button
            icon="i-lucide-flask-conical"
            size="sm"
            slate
            faded
            :label="t('CARTERA.CAMPANAS.PRUEBA.PROBAR')"
            :is-loading="isProbando"
            @click="probar"
          />
        </div>
        <p class="text-body-main text-n-slate-11">
          {{ t('CARTERA.CAMPANAS.PRUEBA.DESCRIPCION') }}
        </p>
        <TableCard v-if="resultadoPrueba">
          <div class="flex flex-col gap-3 p-5">
            <div class="grid grid-cols-2 gap-4 text-center">
              <div>
                <p class="text-heading-1 text-n-teal-11 m-0">
                  {{ resultadoPrueba.casos_enviados }}
                </p>
                <p class="text-xs text-n-slate-10 m-0">
                  {{ t('CARTERA.CAMPANAS.PRUEBA.ENVIADOS') }}
                </p>
              </div>
              <div>
                <p class="text-heading-1 text-n-slate-12 m-0">
                  {{ resultadoPrueba.casos_omitidos }}
                </p>
                <p class="text-xs text-n-slate-10 m-0">
                  {{ t('CARTERA.CAMPANAS.PRUEBA.OMITIDOS') }}
                </p>
              </div>
            </div>
            <div
              v-if="resultadoPrueba.errores.length"
              class="flex flex-col gap-1 border-t border-n-weak pt-3"
            >
              <p
                v-for="(error, index) in resultadoPrueba.errores"
                :key="index"
                class="text-sm text-n-ruby-11 mb-0"
              >
                {{ error }}
              </p>
            </div>
          </div>
        </TableCard>
      </div>

      <!-- Bitacora -->
      <div v-if="activeTab === 'bitacora'">
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
              <span
                v-if="envio.modo_prueba"
                class="inline-block shrink-0 rounded-full border border-n-amber-6 bg-n-amber-3 text-n-amber-11 px-2 py-0.5 text-xs"
              >
                {{ t('CARTERA.CAMPANAS.PRUEBA.BADGE') }}
              </span>
              <span class="text-n-slate-11">{{ envio.canal || '—' }}</span>
              <span class="text-n-slate-11">{{ envio.estado }}</span>
              <span class="text-n-slate-10 truncate max-w-xs">{{
                envio.razon_omision || envio.resultado || ''
              }}</span>
              <span class="text-n-slate-10 shrink-0">{{
                new Date(envio.created_at).toLocaleString()
              }}</span>
              <router-link
                v-if="envio.conversation_id"
                :to="{
                  name: 'inbox_conversation',
                  params: { conversation_id: envio.conversation_id },
                }"
                class="text-n-blue-text shrink-0 hover:underline"
              >
                {{ t('CARTERA.CAMPANAS.BITACORA.VER_CONVERSACION') }}
              </router-link>
            </div>
          </div>
        </TableCard>
        <p v-else-if="!isLoadingEnvios" class="text-body-main text-n-slate-11">
          {{ t('CARTERA.CAMPANAS.BITACORA.EMPTY_STATE') }}
        </p>
      </div>
    </template>

    <Dialog
      ref="reglaDialogRef"
      :title="
        editingReglaId
          ? t('CARTERA.CAMPANAS.REGLAS.EDITAR')
          : t('CARTERA.CAMPANAS.REGLAS.NUEVA')
      "
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
              {{ t('CARTERA.CAMPANAS.REGLAS.FORM.MODO_CONDICION') }}
            </label>
            <Select
              v-model="reglaForm.modoCondicion"
              :options="modoCondicionOptions"
            />
          </div>

          <div
            v-if="reglaForm.modoCondicion === 'banda'"
            class="flex flex-col gap-2"
          >
            <p class="text-body-main text-n-slate-11 mb-0">
              {{ t('CARTERA.CAMPANAS.REGLAS.FORM.MODO_BANDA_AYUDA') }}
            </p>
            <div class="flex items-center gap-3">
              <Input
                v-model.number="reglaForm.puntajeMin"
                type="number"
                min="0"
                max="100"
                :label="t('CARTERA.CAMPANAS.REGLAS.FORM.PUNTAJE_MIN')"
              />
              <Input
                v-model.number="reglaForm.puntajeMax"
                type="number"
                min="0"
                max="100"
                :label="t('CARTERA.CAMPANAS.REGLAS.FORM.PUNTAJE_MAX')"
              />
              <span
                class="inline-block shrink-0 rounded-full border px-2 py-0.5 text-xs whitespace-nowrap self-end mb-1.5"
                :class="
                  severidadClase(
                    severidadBanda(reglaForm.puntajeMin, reglaForm.puntajeMax)
                  )
                "
              >
                {{ severidadLabel(reglaForm.puntajeMin, reglaForm.puntajeMax) }}
              </span>
            </div>
            <p
              v-if="bandaQueBloquea"
              class="text-body-main text-n-amber-11 mb-0"
            >
              {{
                t('CARTERA.CAMPANAS.REGLAS.FORM.BANDA_SOLAPADA', {
                  orden: bandaQueBloquea.regla.orden,
                })
              }}
            </p>
          </div>

          <template v-else>
            <div class="flex flex-col gap-1">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.REGLAS.FORM.ATRIBUTO') }}
              </label>
              <Select
                :model-value="reglaForm.attribute_key"
                :options="atributoOptions"
                @update:model-value="onAtributoChange"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.REGLAS.FORM.OPERADOR') }}
              </label>
              <Select
                v-model="reglaForm.filter_operator"
                :options="operadorOptions"
              />
            </div>
            <div
              v-if="
                !['is_present', 'is_not_present'].includes(
                  reglaForm.filter_operator
                )
              "
              class="flex flex-col gap-1"
            >
              <label class="text-sm text-n-slate-12">
                {{ t('CARTERA.CAMPANAS.REGLAS.FORM.VALOR') }}
              </label>
              <Select
                v-if="reglaForm.attribute_key === 'tramo'"
                v-model="reglaForm.value"
                :options="tramoValorOptions"
              />
              <Select
                v-else-if="reglaForm.attribute_key === 'tipo_deudor'"
                v-model="reglaForm.value"
                :options="tipoDeudorValorOptions"
              />
              <Input v-else v-model="reglaForm.value" type="number" />
            </div>
          </template>
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
