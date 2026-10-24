<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import AuditoriaSentimentChart from './components/AuditoriaSentimentChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const { t } = useI18n();
const store = useStore();

// Mismos tonos ya usados en ReportDrilldownCard (badge de sentimiento por
// tarjeta) -- el lenguaje visual de "positivo/neutral/negativo" se repite
// en todo el reporte, no una paleta nueva por pantalla.
const SENTIMENT_SUMMARY_CLASS = {
  positive: 'bg-n-teal-2 outline-n-teal-6 text-n-teal-11',
  neutral: 'bg-n-slate-2 outline-n-slate-6 text-n-slate-11',
  negative: 'bg-n-ruby-2 outline-n-ruby-6 text-n-ruby-11',
};

// Cada rama llama a t() con una clave literal a proposito (regla
// no-dynamic-keys) -- el lookup por sentiment pasa por el objeto, nunca
// por una clave armada en runtime.
const SENTIMENT_LABELS = {
  positive: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.POSITIVE'),
  neutral: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.NEUTRAL'),
  negative: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.NEGATIVE'),
};
const sentimentLabel = sentiment =>
  SENTIMENT_LABELS[sentiment]?.() || sentiment;

// Forma de adjetivo plural femenino ("positivas", no "Positivo") para
// cuando el sentimiento va DENTRO de una frase ("conversaciones
// positivas") en vez de como etiqueta suelta (chip, leyenda, titulo del
// drawer) -- en espanol el genero/numero no calza con el singular
// masculino que usa sentimentLabel.
const SENTIMENT_PLURAL_LABELS = {
  positive: () =>
    t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT_PLURAL.POSITIVE'),
  neutral: () =>
    t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT_PLURAL.NEUTRAL'),
  negative: () =>
    t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT_PLURAL.NEGATIVE'),
};
const sentimentPlural = sentiment =>
  SENTIMENT_PLURAL_LABELS[sentiment]?.() || sentiment;

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
const selectedUserId = ref('');
const selectedTeamId = ref('');

// isPending (no el flag de Vuex isFetchingAuditoriaSentimentTimeseries) es
// la fuente de verdad de carga aqui: ese flag es compartido por tipo en el
// store y su `finally` lo apaga sin saber si lo esta pisando una respuesta
// MAS VIEJA que ya fue cancelada -- con cancelacion real (ver
// runFetchTimeseries abajo) eso casi garantiza una carrera donde la
// cancelada apaga el flag mientras la peticion vigente sigue en curso.
// isPending del composable solo refleja la ULTIMA peticion disparada por
// este componente, sin esa carrera.
const { run: runFetchTimeseries, isPending: isLoading } = useAbortableRequest();
const hasFetchError = ref(false);

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const timeseries = useMapGetter(
  'summaryReports/getAuditoriaSentimentTimeseries'
);
const timeseriesBucket = useMapGetter(
  'summaryReports/getAuditoriaSentimentTimeseriesBucket'
);

// auditoria_source_user_id puede resolver a cualquier account_user que haya
// respondido, no solo rol "agent" -- mismo criterio que el resumen diario
// por asesor, para no esconder casos de administradores que tambien
// atendieron conversaciones.
const advisorOptions = computed(() =>
  [...agents.value].sort((a, b) => a.name.localeCompare(b.name))
);

// hasFetchError queda prendido hasta el proximo fetch exitoso, para no
// dejar al usuario mirando datos de un filtro anterior sin ningun aviso
// mas alla del toast transitorio. runFetchTimeseries ya cancela el fetch
// anterior si uno nuevo arranca antes de que responda (ver arriba).
const fetchTimeseries = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    userId: selectedUserId.value || undefined,
    teamId: selectedTeamId.value || undefined,
  };
  try {
    await runFetchTimeseries(signal =>
      store.dispatch('summaryReports/fetchAuditoriaSentimentTimeseries', {
        ...params,
        signal,
      })
    );
    hasFetchError.value = false;
  } catch {
    hasFetchError.value = true;
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  fetchTimeseries();
});

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  fetchTimeseries();
};

const onInboxChange = () => fetchTimeseries();

// Asesor y equipo son mutuamente excluyentes a proposito -- el backend
// (ver V2::Reports::Concerns::AuditoriaSentimentScoping#target_user_ids)
// le da prioridad al asesor cuando ambos llegan, ignorando el equipo por
// completo. Elegir uno aqui limpia el otro para que la UI nunca muestre
// los dos selects "activos" con un filtro que en realidad no esta
// aplicando.
const onAdvisorChange = () => {
  if (selectedUserId.value) selectedTeamId.value = '';
  fetchTimeseries();
};
const onTeamChange = () => {
  if (selectedTeamId.value) selectedUserId.value = '';
  fetchTimeseries();
};

const hasActiveFilters = computed(
  () =>
    !!selectedInboxId.value || !!selectedUserId.value || !!selectedTeamId.value
);
const resetFilters = () => {
  selectedInboxId.value = '';
  selectedUserId.value = '';
  selectedTeamId.value = '';
  fetchTimeseries();
};

// Totales del rango completo (sumando todos los buckets ya cargados, sin
// pedir nada nuevo al backend) -- responde directo "cuantas conversaciones
// de cada sentimiento hubo en todo el periodo", y cada total es clicable
// (ver openSentimentDrawer) para ver el listado completo de esa sola
// categoria, no solo mezclado por dia como el clic en la grafica.
const SENTIMENTS = ['positive', 'neutral', 'negative'];
const totalsBySentiment = computed(() => {
  const totals = { positive: 0, neutral: 0, negative: 0 };
  timeseries.value.forEach(s => {
    totals[s.sentiment] = (s.points || []).reduce((sum, p) => sum + p.count, 0);
  });
  return totals;
});
const grandTotal = computed(() =>
  SENTIMENTS.reduce((sum, s) => sum + totalsBySentiment.value[s], 0)
);
const percentFor = sentiment => {
  if (!grandTotal.value) return 0;
  return Math.round(
    (totalsBySentiment.value[sentiment] / grandTotal.value) * 100
  );
};

// Dos formas de abrir el mismo drawer generico: clic en un punto de la
// grafica (un dia/semana/mes puntual, mezcla los 3 sentimientos) o clic en
// un total (TODO el rango visible, un solo sentimiento). drawerContext
// unifica ambas para no duplicar el wiring del drawer.
const drawerContext = ref(null);
const isDrawerOpen = computed(() => !!drawerContext.value);
const openBucketDrawer = ({ since, until, counts }) => {
  drawerContext.value = { type: 'bucket', since, until, counts };
};
const openSentimentDrawer = sentiment => {
  if (!totalsBySentiment.value[sentiment]) return;
  drawerContext.value = { type: 'sentiment', sentiment };
};
const closeDrawer = () => {
  drawerContext.value = null;
};
const fetchDrawerConversations = params =>
  SummaryReportsAPI.getAuditoriaSentimentConversations(params);

const drawerTitle = computed(() => {
  if (!drawerContext.value) return '';

  if (drawerContext.value.type === 'bucket') {
    const { since, until } = drawerContext.value;
    const start = format(fromUnixTime(since), 'd MMM yyyy');
    const end = format(fromUnixTime(until), 'd MMM yyyy');
    return start === end ? start : `${start} - ${end}`;
  }

  return sentimentLabel(drawerContext.value.sentiment);
});

// Desglose "N positivas · N neutras · N negativas" para que el drawer de
// un dia puntual se explique solo -- los mismos numeros que ya vio en el
// tooltip al pasar el mouse, no una cifra nueva sin contexto.
const bucketBreakdownText = computed(() => {
  if (drawerContext.value?.type !== 'bucket') return '';

  const { counts } = drawerContext.value;
  return SENTIMENTS.filter(s => counts[s])
    .map(s => `${counts[s]} ${sentimentPlural(s)}`)
    .join(' · ');
});

const drawerDescription = computed(() => {
  if (!drawerContext.value) return '';

  if (drawerContext.value.type === 'bucket') {
    return bucketBreakdownText.value
      ? t(
          'AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION_BUCKET',
          { breakdown: bucketBreakdownText.value }
        )
      : t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION');
  }

  return t(
    'AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION_SENTIMENT',
    { sentimentPlural: sentimentPlural(drawerContext.value.sentiment) }
  );
});

const drawerFilterParams = computed(() => {
  if (!drawerContext.value) return {};

  const base = {
    inboxId: selectedInboxId.value || undefined,
    userId: selectedUserId.value || undefined,
    teamId: selectedTeamId.value || undefined,
  };

  if (drawerContext.value.type === 'bucket') {
    return {
      ...base,
      since: drawerContext.value.since,
      until: drawerContext.value.until,
    };
  }

  return {
    ...base,
    since: from.value,
    until: to.value,
    sentiment: drawerContext.value.sentiment,
  };
});
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_SENTIMENT_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_SENTIMENT_REPORTS.DESCRIPTION')"
  />

  <div class="flex flex-col justify-between gap-3 md:flex-row">
    <OverviewReportFilters
      :disabled="isLoading"
      hide-business-hours
      @filter-change="onFilterChange"
    />
    <div
      class="flex flex-wrap items-center gap-4"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <div class="flex items-center gap-2">
        <label
          for="auditoria-sentiment-advisor-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.ADVISOR_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-advisor-filter"
          v-model="selectedUserId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onAdvisorChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.ADVISOR_FILTER_ALL') }}
          </option>
          <option
            v-for="advisor in advisorOptions"
            :key="advisor.id"
            :value="advisor.id"
          >
            {{ advisor.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="auditoria-sentiment-team-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.TEAM_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-team-filter"
          v-model="selectedTeamId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onTeamChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.TEAM_FILTER_ALL') }}
          </option>
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="auditoria-sentiment-inbox-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.INBOX_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-inbox-filter"
          v-model="selectedInboxId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onInboxChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.INBOX_FILTER_ALL') }}
          </option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </div>
      <button
        v-if="hasActiveFilters"
        type="button"
        class="text-sm text-n-blue-text hover:underline whitespace-nowrap"
        :disabled="isLoading"
        @click="resetFilters"
      >
        {{ $t('AUDITORIA_SENTIMENT_REPORTS.RESET_FILTERS') }}
      </button>
    </div>
  </div>

  <!--
    El toast de REPORT.SUMMARY_FETCHING_FAILED es transitorio -- sin este
    aviso persistente, un error de red deja la grafica mostrando datos de
    un filtro que ya no es el vigente, sin ninguna pista despues de que el
    toast desaparece.
  -->
  <div
    v-if="hasFetchError"
    class="mt-5 rounded-lg bg-n-ruby-2 outline-1 outline outline-n-ruby-6 px-3 py-2 text-sm text-n-ruby-11"
  >
    {{ $t('AUDITORIA_SENTIMENT_REPORTS.STALE_DATA_WARNING') }}
  </div>

  <div
    class="relative mt-5 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <AuditoriaSentimentChart
      :series="timeseries"
      :since="from"
      :until="to"
      :bucket="timeseriesBucket"
      @select-bucket="openBucketDrawer"
    />
    <div
      v-if="isLoading"
      class="absolute inset-0 flex items-center justify-center rounded-xl bg-n-solid-1/70"
    >
      <Spinner :size="32" class="text-n-brand" />
    </div>
  </div>

  <!--
    Totales de TODO el rango visible, uno por sentimiento -- responde
    directo "cuantas negativas hubo en total" sin tener que sumar picos de
    la grafica a ojo. Cada total es un boton: abre el listado completo de
    esa sola categoria (no mezclado por dia como el clic en la grafica).
  -->
  <div
    v-if="grandTotal"
    class="flex flex-wrap items-center gap-3 mt-3"
    :class="{ 'pointer-events-none opacity-50': isLoading }"
  >
    <button
      v-for="sentiment in SENTIMENTS"
      :key="sentiment"
      type="button"
      class="flex-1 min-w-[160px] flex items-center justify-between gap-2 rounded-xl p-3 text-start outline-1 outline shadow-sm hover:opacity-80"
      :class="SENTIMENT_SUMMARY_CLASS[sentiment]"
      :disabled="isLoading"
      @click="openSentimentDrawer(sentiment)"
    >
      <span class="text-sm font-medium">{{ sentimentLabel(sentiment) }}</span>
      <span class="flex items-baseline gap-1">
        <span class="text-lg font-semibold">
          {{ totalsBySentiment[sentiment] }}
        </span>
        <span class="text-xs opacity-80">
          {{
            $t('AUDITORIA_SENTIMENT_REPORTS.SUMMARY_PERCENT', {
              percent: percentFor(sentiment),
            })
          }}
        </span>
      </span>
    </button>
  </div>

  <AuditoriaReportConversationsDrawer
    :open="isDrawerOpen"
    :title="drawerTitle"
    :description="drawerDescription"
    :empty-text="$t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.EMPTY')"
    :error-text="$t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.ERROR')"
    :filter-params="drawerFilterParams"
    :fetcher="fetchDrawerConversations"
    @close="closeDrawer"
  />
</template>
