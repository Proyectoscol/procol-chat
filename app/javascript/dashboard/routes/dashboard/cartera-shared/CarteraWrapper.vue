<!-- Mismo patron que settings/reports/components/ReportsWrapper.vue: ancho
maximo centrado en vez de un layout de altura completa pegado al sidebar,
para que Resumen/Clientes/Facturas tengan el mismo margen que Informes. -->
<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-5xl mx-auto pb-12">
      <router-view />
    </div>
  </div>
</template>
