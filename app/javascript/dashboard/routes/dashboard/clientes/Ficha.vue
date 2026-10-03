<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import ContactNoteItem from 'dashboard/components-next/Contacts/ContactsSidebar/components/ContactNoteItem.vue';
import clienteAPI from 'dashboard/api/cartera/clientes';
import facturaAPI from 'dashboard/api/cartera/facturas';
import FacturasTable from '../cartera-shared/FacturasTable.vue';
import MetricCard from '../cartera-shared/MetricCard.vue';
import Panel from '../cartera-shared/Panel.vue';
import { formatearCop, formatearFecha } from '../cartera-shared/format';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const isFetching = ref(false);
const cliente = ref(null);
const perfilPago = ref(null);
const pagosRecientes = ref([]);

const facturasAbiertas = ref([]);
const facturasPagadas = ref([]);
const facturasTab = ref('abiertas');
const isFetchingFacturas = ref(false);

const currentUser = useMapGetter('getCurrentUser');
const notesByContact = useMapGetter('contactNotes/getAllNotesByContactId');
const notesUiFlags = useMapGetter('contactNotes/getUIFlags');
const isFetchingNotes = computed(() => notesUiFlags.value.isFetching);
const isCreatingNote = computed(() => notesUiFlags.value.isCreating);
const noteState = reactive({ message: '' });

const contactId = computed(() => cliente.value?.contact_id);
const notes = computed(() =>
  contactId.value ? notesByContact.value(contactId.value) : []
);

const colorTramo = tramo => {
  if (!tramo || tramo === 'vigente') return 'text-n-teal-11';
  if (['d1_30', 'd31_60'].includes(tramo)) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const colorPuntajeRiesgo = valor => {
  if (valor === null || valor === undefined) return 'text-n-slate-10';
  if (valor >= 70) return 'text-n-ruby-11';
  if (valor >= 40) return 'text-n-slate-12';
  return 'text-n-teal-11';
};

const sinDato = t('CARTERA.CLIENTES.SIN_DATO');

const fetchFicha = async () => {
  isFetching.value = true;
  try {
    const { data } = await clienteAPI.show(route.params.clienteId);
    cliente.value = data.cliente;
    perfilPago.value = data.perfil_pago;
    pagosRecientes.value = data.pagos_recientes;
  } finally {
    isFetching.value = false;
  }
};

const fetchFacturas = async () => {
  isFetchingFacturas.value = true;
  try {
    const { data } = await facturaAPI.get({
      clienteId: route.params.clienteId,
      estado: facturasTab.value,
      pageSize: 100,
    });
    if (facturasTab.value === 'abiertas') {
      facturasAbiertas.value = data.items;
    } else {
      facturasPagadas.value = data.items;
    }
  } finally {
    isFetchingFacturas.value = false;
  }
};

watch(facturasTab, fetchFacturas);

watch(contactId, newContactId => {
  if (newContactId)
    store.dispatch('contactNotes/get', { contactId: newContactId });
});

const getWrittenBy = note => {
  const isCurrentUser = note?.user?.id === currentUser.value.id;
  return isCurrentUser
    ? t('CONTACTS_LAYOUT.SIDEBAR.NOTES.YOU')
    : note?.user?.name || 'Bot';
};

const onAddNote = content => {
  if (!content || !contactId.value) return;
  store.dispatch('contactNotes/create', {
    content,
    contactId: contactId.value,
  });
  noteState.message = '';
};

const onDeleteNote = noteId => {
  if (!noteId || !contactId.value) return;
  store.dispatch('contactNotes/delete', { noteId, contactId: contactId.value });
};

const volver = () => router.push({ name: 'cartera_clientes_view' });

onMounted(async () => {
  await fetchFicha();
  await fetchFacturas();
  if (contactId.value) {
    store.dispatch('contactNotes/get', { contactId: contactId.value });
  }
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <Button icon="i-lucide-arrow-left" ghost slate sm @click="volver" />
      <template v-if="cliente">
        <h1 class="text-base font-semibold text-n-slate-12">
          {{ cliente.nombre_cliente }}
        </h1>
        <span class="text-sm text-n-slate-10">{{
          cliente.identificacion
        }}</span>
        <span
          v-if="cliente.no_cobrar"
          class="rounded-full border border-n-ruby-6 bg-n-ruby-3 px-2 py-0.5 text-[10px] text-n-ruby-11"
        >
          {{ t('CARTERA.CLIENTES.NO_COBRAR') }}
        </span>
        <span
          v-if="cliente.es_estrategico"
          class="rounded-full border border-n-amber-6 bg-n-amber-3 px-2 py-0.5 text-[10px] text-n-amber-11"
        >
          {{ t('CARTERA.FICHA.ESTRATEGICO') }}
        </span>
      </template>
    </header>

    <div
      v-if="isFetching && !cliente"
      class="flex items-center justify-center py-20 text-body-main text-n-slate-11"
    >
      {{ t('CARTERA.FICHA.LOADING') }}
    </div>

    <div v-else-if="cliente" class="flex-1 overflow-y-auto p-6 space-y-4">
      <Panel :title="t('CARTERA.FICHA.PERFIL_TITLE')">
        <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <MetricCard
            :label="t('CARTERA.FICHA.SALDO_ABIERTO')"
            :value="formatearCop(cliente.saldo_abierto)"
          />
          <MetricCard
            :label="t('CARTERA.FICHA.PUNTAJE_RIESGO')"
            :value="
              cliente.puntaje_riesgo == null
                ? sinDato
                : `${cliente.puntaje_riesgo}/100`
            "
            :value-class="colorPuntajeRiesgo(cliente.puntaje_riesgo)"
          />
          <MetricCard
            :label="t('CARTERA.FICHA.SCORE_CREDITO')"
            :value="
              cliente.score_credito == null
                ? sinDato
                : `${cliente.score_credito}/100`
            "
          />
          <MetricCard
            :label="t('CARTERA.FICHA.MORA')"
            :value="
              cliente.tramo
                ? `${t(`CARTERA.TRAMOS.${cliente.tramo.toUpperCase()}`)} (${cliente.dias_vencido_max}d)`
                : sinDato
            "
            :value-class="colorTramo(cliente.tramo)"
          />
          <MetricCard
            :label="t('CARTERA.FICHA.DIAS_PROMEDIO_PAGO')"
            :value="
              perfilPago?.dias_promedio_pago_habil == null
                ? sinDato
                : `${perfilPago.dias_promedio_pago_habil}d`
            "
          />
          <MetricCard
            :label="t('CARTERA.FICHA.PORCENTAJE_TARDE')"
            :value="
              perfilPago?.porcentaje_pagadas_tarde_habil == null
                ? sinDato
                : `${perfilPago.porcentaje_pagadas_tarde_habil}%`
            "
          />
          <MetricCard
            :label="t('CARTERA.FICHA.CUPO_UTILIZADO')"
            :value="
              perfilPago?.cupo_utilizado_porcentaje == null
                ? sinDato
                : `${perfilPago.cupo_utilizado_porcentaje}%`
            "
          />
          <MetricCard
            :label="t('CARTERA.FICHA.ANTIGUEDAD_RELACION')"
            :value="
              perfilPago?.antiguedad_relacion_dias == null
                ? sinDato
                : t('CARTERA.FICHA.ANTIGUEDAD_RELACION_VALOR', {
                    dias: perfilPago.antiguedad_relacion_dias,
                  })
            "
          />
        </div>
        <div
          v-if="perfilPago"
          class="grid grid-cols-1 gap-4 mt-4 lg:grid-cols-2"
        >
          <div class="p-3 rounded-lg border border-n-weak">
            <span class="text-xs text-n-slate-10">
              {{ t('CARTERA.FICHA.TENDENCIA_6_MESES') }}
            </span>
            <p class="text-sm font-medium text-n-slate-12">
              {{
                perfilPago.tendencia_6_meses.porcentaje_pagadas_tarde == null
                  ? sinDato
                  : `${perfilPago.tendencia_6_meses.porcentaje_pagadas_tarde}%`
              }}
              {{
                t('CARTERA.FICHA.TENDENCIA_FACTURAS_SUFFIX', {
                  count: perfilPago.tendencia_6_meses.cantidad_facturas,
                })
              }}
            </p>
          </div>
          <div class="p-3 rounded-lg border border-n-weak">
            <span class="text-xs text-n-slate-10">
              {{ t('CARTERA.FICHA.TENDENCIA_12_MESES') }}
            </span>
            <p class="text-sm font-medium text-n-slate-12">
              {{
                perfilPago.tendencia_12_meses.porcentaje_pagadas_tarde == null
                  ? sinDato
                  : `${perfilPago.tendencia_12_meses.porcentaje_pagadas_tarde}%`
              }}
              {{
                t('CARTERA.FICHA.TENDENCIA_FACTURAS_SUFFIX', {
                  count: perfilPago.tendencia_12_meses.cantidad_facturas,
                })
              }}
            </p>
          </div>
        </div>
      </Panel>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel :title="t('CARTERA.FICHA.ACCIONES_TITLE')">
          <div class="flex flex-wrap items-center gap-3">
            <VoiceCallButton
              v-if="contactId"
              :contact-id="contactId"
              :phone="cliente.telefono_clasificado?.numero_para_llamar || ''"
              icon="i-lucide-phone"
              :label="t('CARTERA.FICHA.LLAMAR')"
            />
            <Button
              v-tooltip="t('CARTERA.FICHA.EXPORTAR_PDF_PROXIMAMENTE')"
              icon="i-lucide-file-down"
              slate
              faded
              disabled
              :label="t('CARTERA.FICHA.EXPORTAR_PDF')"
            />
          </div>
          <p v-if="!contactId" class="mt-3 text-xs text-n-slate-10">
            {{ t('CARTERA.FICHA.SIN_CONTACTO') }}
          </p>
        </Panel>

        <Panel :title="t('CARTERA.FICHA.INTERACCIONES_TITLE')">
          <template v-if="contactId">
            <Editor
              v-model="noteState.message"
              :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.PLACEHOLDER')"
              class="[&>div]:!border-n-weak"
            >
              <template #actions>
                <Button
                  variant="link"
                  color="blue"
                  size="sm"
                  :label="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.SAVE')"
                  :is-loading="isCreatingNote"
                  :disabled="!noteState.message || isCreatingNote"
                  @click="onAddNote(noteState.message)"
                />
              </template>
            </Editor>
            <div
              v-if="isFetchingNotes"
              class="flex items-center justify-center py-6"
            >
              <Spinner />
            </div>
            <div v-else-if="notes.length" class="mt-2 max-h-72 overflow-y-auto">
              <ContactNoteItem
                v-for="note in notes"
                :key="note.id"
                class="py-3"
                :note="note"
                :written-by="getWrittenBy(note)"
                allow-delete
                @delete="onDeleteNote"
              />
            </div>
            <p v-else class="py-4 text-sm text-center text-n-slate-11">
              {{ t('CONTACTS_LAYOUT.SIDEBAR.NOTES.EMPTY_STATE') }}
            </p>
          </template>
          <p v-else class="text-sm text-n-slate-11">
            {{ t('CARTERA.FICHA.SIN_CONTACTO') }}
          </p>
        </Panel>
      </div>

      <Panel :title="t('CARTERA.FICHA.FACTURAS_TITLE')">
        <template #actions>
          <div class="flex gap-1 p-1 rounded-lg bg-n-slate-2">
            <button
              type="button"
              class="px-3 py-1 text-xs rounded-md"
              :class="
                facturasTab === 'abiertas'
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="facturasTab = 'abiertas'"
            >
              {{ t('CARTERA.FICHA.FACTURAS_TAB_ABIERTAS') }}
            </button>
            <button
              type="button"
              class="px-3 py-1 text-xs rounded-md"
              :class="
                facturasTab === 'pagadas'
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="facturasTab = 'pagadas'"
            >
              {{ t('CARTERA.FICHA.FACTURAS_TAB_PAGADAS') }}
            </button>
          </div>
        </template>
        <FacturasTable
          hide-cliente-column
          :items="
            facturasTab === 'abiertas' ? facturasAbiertas : facturasPagadas
          "
          :loading="isFetchingFacturas"
          :empty-message="t('CARTERA.FACTURAS.EMPTY_STATE')"
        />
      </Panel>

      <Panel :title="t('CARTERA.FICHA.PAGOS_TITLE')">
        <BaseTable
          v-if="pagosRecientes.length"
          :headers="[
            t('CARTERA.FICHA.PAGOS_HEADERS.FECHA'),
            t('CARTERA.FICHA.PAGOS_HEADERS.VALOR'),
            t('CARTERA.FICHA.PAGOS_HEADERS.MEDIO_PAGO'),
          ]"
          :items="pagosRecientes"
        >
          <template #row="{ items: rows }">
            <BaseTableRow v-for="pago in rows" :key="pago.pago_id" :item="pago">
              <template #default>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ formatearFecha(pago.fecha) }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-12 tabular-nums">
                    {{ formatearCop(pago.valor) }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11 capitalize">
                    {{ pago.medio_pago || sinDato }}
                  </span>
                </BaseTableCell>
              </template>
            </BaseTableRow>
          </template>
        </BaseTable>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('CARTERA.FICHA.PAGOS_EMPTY') }}
        </p>
      </Panel>
    </div>
  </div>
</template>
