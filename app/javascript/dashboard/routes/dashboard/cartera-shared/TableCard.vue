<!-- Misma tarjeta (sombra + outline + fondo) que envuelve las tablas de
Informes (ej. settings/reports/components/SummaryReports.vue, CsatTable.vue). -->
<template>
  <div
    class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 overflow-hidden"
  >
    <div class="overflow-x-auto">
      <slot />
    </div>
    <div v-if="$slots.footer" class="px-6 py-4 border-t border-n-weak">
      <slot name="footer" />
    </div>
  </div>
</template>
