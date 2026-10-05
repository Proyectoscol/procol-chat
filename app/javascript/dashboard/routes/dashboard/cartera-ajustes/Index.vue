<!-- Pesos del algoritmo de puntaje de riesgo (Cartera::PesoRiesgo /
Cartera::PuntajeRiesgoService). Los 7 controles se manejan en puntos
porcentuales enteros (0-100) que siempre suman exactamente 100 - mover uno
reajusta los demas proporcionalmente - y solo se convierten a decimal
(/100) al guardar, evitando que el redondeo de punto flotante rompa la
validacion del backend de que los pesos sumen 1.0. -->
<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import pesosRiesgoAPI from 'dashboard/api/cartera/pesosRiesgo';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';

const DEFAULTS = {
  mora_actual: 20,
  pagos_tardios: 25,
  saldo_abierto: 20,
  cupo_utilizado: 10,
  antiguedad_relacion: 10,
  cartera_vencida_pct: 10,
  total_facturado: 5,
};

const FACTORES = Object.keys(DEFAULTS);

const { t } = useI18n();
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const isSaving = ref(false);
const porcentajes = reactive({ ...DEFAULTS });

const factorRows = computed(() =>
  FACTORES.map(factor => ({
    key: factor,
    label: t(`CARTERA.AJUSTES.FACTORES.${factor.toUpperCase()}`),
    ayuda: t(`CARTERA.AJUSTES.FACTORES_AYUDA.${factor.toUpperCase()}`),
    valor: porcentajes[factor],
  }))
);

const suma = computed(() =>
  FACTORES.reduce((total, factor) => total + porcentajes[factor], 0)
);

// Redistribuye lo que le resta a `remaining` entre `claves` en proporcion a
// su peso actual (o en partes iguales si todas pesan 0 hoy) - el ultimo
// factor se lleva el residuo del redondeo para que la suma final sea exacta.
const redistribuir = (claves, remaining) => {
  const pesoActual = claves.reduce((total, key) => total + porcentajes[key], 0);
  let asignado = 0;

  claves.forEach((key, index) => {
    const esUltimo = index === claves.length - 1;
    if (esUltimo) {
      porcentajes[key] = remaining - asignado;
      return;
    }

    const parte =
      pesoActual > 0
        ? (porcentajes[key] / pesoActual) * remaining
        : remaining / claves.length;
    const redondeado = Math.round(parte);
    porcentajes[key] = redondeado;
    asignado += redondeado;
  });
};

const ajustarFactor = (factor, nuevoValor) => {
  const clamped = Math.max(0, Math.min(100, Math.round(nuevoValor)));
  porcentajes[factor] = clamped;
  redistribuir(
    FACTORES.filter(key => key !== factor),
    100 - clamped
  );
};

const aplicarPesos = pesos => {
  FACTORES.forEach(factor => {
    porcentajes[factor] = Math.round((pesos[factor] || 0) * 100);
  });
};

const cargarPesos = async () => {
  isLoading.value = true;
  try {
    const { data } = await pesosRiesgoAPI.show();
    aplicarPesos(data);
  } catch {
    useAlert(t('CARTERA.AJUSTES.CARGAR_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const restablecer = () =>
  aplicarPesos(
    Object.fromEntries(FACTORES.map(factor => [factor, DEFAULTS[factor] / 100]))
  );

const guardar = async () => {
  isSaving.value = true;
  try {
    const pesos = Object.fromEntries(
      FACTORES.map(factor => [factor, porcentajes[factor] / 100])
    );
    const { data } = await pesosRiesgoAPI.update(pesos);
    aplicarPesos(data);
    useAlert(t('CARTERA.AJUSTES.GUARDADO_EXITOSO'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CARTERA.AJUSTES.GUARDAR_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(cargarPesos);
</script>

<template>
  <div>
    <CarteraHeader
      :header-title="t('CARTERA.AJUSTES.TITLE')"
      :header-description="t('CARTERA.AJUSTES.DESCRIPCION')"
    >
      <div v-if="isAdmin" class="flex items-center gap-2">
        <Button
          color="slate"
          size="sm"
          :label="t('CARTERA.AJUSTES.RESTABLECER')"
          :disabled="isSaving"
          @click="restablecer"
        />
        <Button
          size="sm"
          :label="t('CARTERA.AJUSTES.GUARDAR')"
          :is-loading="isSaving"
          @click="guardar"
        />
      </div>
    </CarteraHeader>

    <div v-if="isLoading" class="flex items-center justify-center py-16">
      <Spinner />
    </div>

    <TableCard v-else>
      <div
        class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
      >
        <span class="text-body-main text-n-slate-11">
          {{ t('CARTERA.AJUSTES.SUMA_LABEL', { porcentaje: suma }) }}
        </span>
        <span v-if="suma !== 100" class="text-body-main text-n-ruby-9">
          {{ t('CARTERA.AJUSTES.SUMA_INVALIDA') }}
        </span>
      </div>
      <div class="divide-y divide-n-weak">
        <div
          v-for="factor in factorRows"
          :key="factor.key"
          class="flex flex-col gap-2 px-5 py-4"
        >
          <div class="flex items-center justify-between gap-4">
            <label class="text-heading-3 text-n-slate-12">
              {{ factor.label }}
            </label>
            <span class="text-heading-3 text-n-slate-12 tabular-nums shrink-0">
              {{ factor.valor }}%
            </span>
          </div>
          <input
            type="range"
            min="0"
            max="100"
            :value="factor.valor"
            :disabled="!isAdmin"
            class="w-full h-1.5 rounded-full appearance-none cursor-pointer bg-n-slate-4 accent-n-brand-9 disabled:cursor-not-allowed [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:size-4 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-n-brand-9 [&::-moz-range-thumb]:appearance-none [&::-moz-range-thumb]:size-4 [&::-moz-range-thumb]:border-0 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-n-brand-9"
            @input="ajustarFactor(factor.key, $event.target.value)"
          />
          <p class="text-body-main text-n-slate-11 mb-0">
            {{ factor.ayuda }}
          </p>
        </div>
      </div>
    </TableCard>
  </div>
</template>
