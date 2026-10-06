<!-- Pesos del algoritmo de puntaje de riesgo (Cartera::PesoRiesgo /
Cartera::PuntajeRiesgoService). Los 7 campos son independientes - escribir
en uno NO reajusta los demas (el deslizador con reajuste automatico que
tenia esta pantalla resultó confuso: "no se ve", "no es intuitivo"). La
suma se valida solo al hacer clic en Guardar, con el detalle exacto de
cuanto falta o sobra - mientras tanto el usuario puede pasarse o quedarse
corto sin que la pantalla se lo impida. -->
<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import pesosRiesgoAPI from 'dashboard/api/cartera/pesosRiesgo';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
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
const SUMA_ESPERADA = 100;

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
  }))
);

const suma = computed(() =>
  FACTORES.reduce((total, factor) => total + (porcentajes[factor] || 0), 0)
);
const diferencia = computed(() => suma.value - SUMA_ESPERADA);
const sumaValida = computed(() => diferencia.value === 0);

const actualizarFactor = (factor, valorTexto) => {
  const valor = Number(valorTexto);
  porcentajes[factor] = Number.isFinite(valor)
    ? Math.max(0, Math.min(100, Math.round(valor)))
    : 0;
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
  if (!sumaValida.value) return;

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
          :disabled="!sumaValida"
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
        :class="sumaValida ? '' : 'bg-n-ruby-2 dark:bg-n-ruby-3'"
      >
        <span class="text-body-main font-medium text-n-slate-12">
          {{ t('CARTERA.AJUSTES.SUMA_LABEL', { porcentaje: suma }) }}
        </span>
        <span v-if="!sumaValida" class="text-body-main text-n-ruby-11">
          {{
            diferencia > 0
              ? t('CARTERA.AJUSTES.SUMA_SOBRA', { exceso: diferencia })
              : t('CARTERA.AJUSTES.SUMA_FALTA', { faltante: -diferencia })
          }}
        </span>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-5 p-5">
        <div
          v-for="factor in factorRows"
          :key="factor.key"
          class="flex flex-col gap-1.5"
        >
          <label class="text-body-main font-medium text-n-slate-12">
            {{ factor.label }}
          </label>
          <div class="flex items-center gap-2">
            <Input
              type="number"
              min="0"
              max="100"
              :model-value="porcentajes[factor.key]"
              :disabled="!isAdmin"
              class="w-24 [&>input]:text-right tabular-nums"
              @update:model-value="valor => actualizarFactor(factor.key, valor)"
            />
            <span class="text-body-main text-n-slate-11">%</span>
          </div>
          <p class="text-xs text-n-slate-10 mb-0">
            {{ factor.ayuda }}
          </p>
        </div>
      </div>
    </TableCard>
  </div>
</template>
