<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import clienteAPI from 'dashboard/api/cartera/clientes';
import { formatearCop } from '../cartera-shared/format';

const { t } = useI18n();

const headers = [
  t('CARTERA.CLIENTES.HEADERS.CLIENTE'),
  t('CARTERA.CLIENTES.HEADERS.NIT'),
  t('CARTERA.CLIENTES.HEADERS.TELEFONO'),
  t('CARTERA.CLIENTES.HEADERS.SALDO_PENDIENTE'),
  t('CARTERA.CLIENTES.HEADERS.MORA'),
  t('CARTERA.CLIENTES.HEADERS.PUNTAJE_RIESGO'),
  t('CARTERA.CLIENTES.HEADERS.TOTAL_FACTURADO'),
  t('CARTERA.CLIENTES.HEADERS.FACTURAS_ABIERTAS'),
];

const colorTramo = tramo => {
  if (!tramo || tramo === 'vigente') return 'text-n-teal-11';
  if (['d1_30', 'd31_60'].includes(tramo)) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const items = ref([]);
const page = ref(1);
const total = ref(0);
const pageSize = ref(20);
const isFetching = ref(false);

const colorPuntajeRiesgo = valor => {
  if (valor === null) return 'text-n-slate-10';
  if (valor >= 70) return 'text-n-ruby-11';
  if (valor >= 40) return 'text-n-slate-12';
  return 'text-n-teal-11';
};

const fetchClientes = async () => {
  isFetching.value = true;
  try {
    const { data } = await clienteAPI.get({ page: page.value });
    items.value = data.items;
    total.value = data.total;
    pageSize.value = data.page_size;
  } finally {
    isFetching.value = false;
  }
};

const goToPage = newPage => {
  if (newPage < 1 || newPage > Math.ceil(total.value / pageSize.value)) return;
  page.value = newPage;
  fetchClientes();
};

onMounted(fetchClientes);
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <span class="i-lucide-users size-5 text-n-slate-11" />
      <h1 class="text-base font-semibold text-n-slate-12">
        {{ t('CARTERA.CLIENTES.TITLE') }}
      </h1>
    </header>

    <div class="flex-1 overflow-y-auto p-6">
      <BaseTable
        :headers="headers"
        :items="items"
        :loading="isFetching"
        :no-data-message="t('CARTERA.CLIENTES.EMPTY_STATE')"
      >
        <template #row="{ items: rows }">
          <BaseTableRow
            v-for="cliente in rows"
            :key="cliente.cliente_id"
            :item="cliente"
          >
            <template #default>
              <BaseTableCell>
                <div class="flex items-center gap-2 min-w-0">
                  <span class="text-body-main text-n-slate-12 truncate">
                    {{ cliente.nombre_cliente }}
                  </span>
                  <span
                    v-if="cliente.no_cobrar"
                    class="flex-shrink-0 rounded-full border border-n-ruby-6 bg-n-ruby-3 px-2 py-0.5 text-[10px] text-n-ruby-11"
                  >
                    {{ t('CARTERA.CLIENTES.NO_COBRAR') }}
                  </span>
                </div>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ cliente.identificacion }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{
                    cliente.telefono_clasificado?.numero_para_llamar ??
                    t('CARTERA.CLIENTES.SIN_DATO')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ formatearCop(cliente.saldo_abierto) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="text-body-main whitespace-nowrap"
                  :class="colorTramo(cliente.tramo)"
                >
                  {{
                    cliente.tramo
                      ? `${t(`CARTERA.TRAMOS.${cliente.tramo.toUpperCase()}`)} (${cliente.dias_vencido_max}d)`
                      : t('CARTERA.CLIENTES.SIN_DATO')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="text-body-main whitespace-nowrap"
                  :class="colorPuntajeRiesgo(cliente.puntaje_riesgo)"
                >
                  {{
                    cliente.puntaje_riesgo === null
                      ? t('CARTERA.CLIENTES.SIN_DATO')
                      : `${cliente.puntaje_riesgo}/100`
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ formatearCop(cliente.total_facturado_historico) }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <span class="text-body-main text-n-slate-12">
                  {{ cliente.facturas_abiertas_cantidad }}
                </span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>

      <div
        v-if="total > pageSize"
        class="flex items-center justify-between mt-4"
      >
        <p class="text-sm text-n-slate-11">
          {{
            t('CARTERA.PAGINATION', {
              page,
              totalPages: Math.ceil(total / pageSize),
            })
          }}
        </p>
        <div class="flex gap-2">
          <Button
            icon="i-lucide-chevron-left"
            ghost
            slate
            sm
            :disabled="page <= 1"
            @click="goToPage(page - 1)"
          />
          <Button
            icon="i-lucide-chevron-right"
            ghost
            slate
            sm
            :disabled="page >= Math.ceil(total / pageSize)"
            @click="goToPage(page + 1)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
