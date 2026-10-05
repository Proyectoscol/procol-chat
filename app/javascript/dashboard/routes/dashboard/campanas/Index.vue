<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import campanaAPI from 'dashboard/api/cartera/campanas';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';

const { t } = useI18n();
const router = useRouter();
const { isAdmin } = useAdmin();

const DIA_LABELS = {
  0: 'DOM',
  1: 'LUN',
  2: 'MAR',
  3: 'MIE',
  4: 'JUE',
  5: 'VIE',
  6: 'SAB',
};

const items = ref([]);
const isFetching = ref(false);
const isCreating = ref(false);

const fetchCampanas = async () => {
  isFetching.value = true;
  try {
    const { data } = await campanaAPI.get();
    items.value = data;
  } finally {
    isFetching.value = false;
  }
};

const estadoBadgeClass = estado => {
  if (estado === 'activa') return 'border-n-teal-6 bg-n-teal-3 text-n-teal-11';
  if (estado === 'pausada')
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-11';
  if (estado === 'archivada')
    return 'border-n-slate-6 bg-n-slate-3 text-n-slate-11';
  return 'border-n-blue-6 bg-n-blue-3 text-n-blue-11';
};

const diasResumen = dias =>
  [...(dias || [])]
    .sort()
    .map(dia => DIA_LABELS[dia])
    .join(' ');

const resumenHorario = campana =>
  `${campana.hora_inicio} - ${campana.hora_fin} · ${diasResumen(campana.dias_envio)}`;

const abrirDetalle = campana => {
  router.push({
    name: 'cartera_campana_detail_view',
    params: { campanaId: campana.id },
  });
};

const crearCampana = async () => {
  isCreating.value = true;
  try {
    const { data } = await campanaAPI.create({
      nombre: t('CARTERA.CAMPANAS.NOMBRE_POR_DEFECTO'),
      hora_inicio: '07:00',
      hora_fin: '19:00',
      dias_envio: [1, 2, 3, 4, 5],
    });
    router.push({
      name: 'cartera_campana_detail_view',
      params: { campanaId: data.id },
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CARTERA.CAMPANAS.CREAR_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

const hasItems = computed(() => items.value.length > 0);

onMounted(fetchCampanas);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.CAMPANAS.TITLE')">
      <Button
        v-if="isAdmin"
        icon="i-lucide-plus"
        size="sm"
        :label="t('CARTERA.CAMPANAS.NUEVA')"
        :is-loading="isCreating"
        @click="crearCampana"
      />
    </CarteraHeader>

    <TableCard v-if="hasItems">
      <div class="divide-y divide-n-weak">
        <div
          v-for="campana in items"
          :key="campana.id"
          role="button"
          tabindex="0"
          class="flex items-center justify-between gap-4 py-4 px-5 cursor-pointer hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
          @click="abrirDetalle(campana)"
          @keydown.enter="abrirDetalle(campana)"
        >
          <div class="flex flex-col min-w-0 gap-1">
            <div class="flex items-center gap-2 min-w-0">
              <span class="truncate text-heading-3 text-n-slate-12">
                {{ campana.nombre }}
              </span>
              <span
                class="inline-block shrink-0 rounded-full border px-2 py-0.5 text-xs whitespace-nowrap"
                :class="estadoBadgeClass(campana.estado)"
              >
                {{
                  t(`CARTERA.CAMPANAS.ESTADOS.${campana.estado.toUpperCase()}`)
                }}
              </span>
            </div>
            <span class="text-body-main text-n-slate-11">
              {{ resumenHorario(campana) }}
            </span>
          </div>
        </div>
      </div>
    </TableCard>

    <div
      v-if="isFetching && !items.length"
      class="flex items-center justify-center py-16"
    >
      <Spinner />
    </div>
    <EmptyState
      v-else-if="!isFetching && !items.length"
      :title="t('CARTERA.CAMPANAS.EMPTY_STATE')"
    />
  </div>
</template>
