<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();

// Reusa las paginas ya existentes de Calendario (CalendarioSpecialtiesPage,
// etc.) -- solo cambia donde viven en la navegacion (antes pestanas sueltas
// bajo /calendario, ahora agrupadas aqui como "IPS"), nunca su logica.
const tabs = computed(() => [
  { name: 'ips_specialties_index', label: t('CALENDARIO.TABS.SPECIALTIES') },
  {
    name: 'ips_professionals_index',
    label: t('CALENDARIO.TABS.PROFESSIONALS'),
  },
  { name: 'ips_services_index', label: t('CALENDARIO.TABS.SERVICES') },
  { name: 'ips_payers_index', label: t('CALENDARIO.TABS.PAYERS') },
]);

const isActive = name => route.name === name;
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
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto py-6">
        <router-view />
      </div>
    </main>
  </section>
</template>
