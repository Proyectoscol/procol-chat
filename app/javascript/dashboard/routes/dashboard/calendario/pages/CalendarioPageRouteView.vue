<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();

const currentRole = useMapGetter('getCurrentRole');
const isAdministrator = computed(() => currentRole.value === 'administrator');

// Orden armonizado con el sidebar: lo operativo primero (agenda del dia,
// calendario, agendas por profesional), luego configuracion
// (profesionales/servicios/EPS, solo administracion), y estadisticas de
// ultimas -- no es una accion del dia a dia, es revision.
const tabs = computed(() => {
  const base = [
    { name: 'calendario_agenda_index', label: t('CALENDARIO.TABS.AGENDA') },
    { name: 'calendario_calendar_index', label: t('CALENDARIO.TABS.CALENDAR') },
    {
      name: 'calendario_schedules_index',
      label: t('CALENDARIO.TABS.SCHEDULES'),
    },
  ];
  if (!isAdministrator.value) {
    return [
      ...base,
      { name: 'calendario_stats_index', label: t('CALENDARIO.TABS.STATS') },
    ];
  }
  return [
    ...base,
    {
      name: 'calendario_specialties_index',
      label: t('CALENDARIO.TABS.SPECIALTIES'),
    },
    {
      name: 'calendario_professionals_index',
      label: t('CALENDARIO.TABS.PROFESSIONALS'),
    },
    { name: 'calendario_services_index', label: t('CALENDARIO.TABS.SERVICES') },
    { name: 'calendario_payers_index', label: t('CALENDARIO.TABS.PAYERS') },
    {
      name: 'calendario_notifications_index',
      label: t('CALENDARIO.TABS.TRIGGERS'),
    },
    {
      name: 'calendario_welcome_bot_flows_index',
      label: t('CALENDARIO.TABS.WELCOME_BOT'),
    },
    { name: 'calendario_stats_index', label: t('CALENDARIO.TABS.STATS') },
  ];
});

const isActive = name => route.name === name;

// Agendas (Schedules) es la unica pestana sin scroll de pagina a proposito
// -- el personal pidio explicitamente que todo (encabezado, selector de
// profesional, asistencia, la tarjeta de dias y el boton de abrir agenda)
// quepa en el alto de la pantalla, con solo la tarjeta de dias
// desplazandose internamente. El resto de pestanas (Agenda, Calendario,
// Profesionales, Servicios, EPS, Estadisticas) sigue con el flujo normal +
// scroll de pagina de siempre, por eso este ajuste es condicional y no un
// cambio del layout compartido.
const isFullHeightRoute = computed(
  () => route.name === 'calendario_schedules_index'
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6 border-b border-n-weak">
      <div class="w-full max-w-5xl mx-auto">
        <nav class="flex gap-4">
          <router-link
            v-for="tab in tabs"
            :key="tab.name"
            :to="accountScopedRoute(tab.name)"
            class="-mb-px px-1 py-3 text-sm font-medium border-b-2"
            :class="
              isActive(tab.name)
                ? 'text-n-blue-text border-n-blue-border'
                : 'text-n-slate-11 border-transparent hover:text-n-slate-12'
            "
          >
            {{ tab.label }}
          </router-link>
        </nav>
      </div>
    </header>
    <main
      class="flex-1 px-6"
      :class="isFullHeightRoute ? 'overflow-hidden' : 'overflow-y-auto'"
    >
      <div
        class="w-full max-w-5xl mx-auto py-6"
        :class="isFullHeightRoute ? 'h-full flex flex-col overflow-hidden' : ''"
      >
        <router-view />
      </div>
    </main>
  </section>
</template>
