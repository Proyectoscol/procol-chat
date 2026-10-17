<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';

const {
  content,
  attachments,
  contentAttributes,
  additionalAttributes,
  messageType,
  inReplyTo,
} = useMessageContext();

const templateName = computed(
  () => additionalAttributes.value?.templateParams?.name ?? null
);

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return contentAttributes.value?.auditoriaDisplayContent ?? content.value;
});

// Cuando un reply de Auditoria no se pudo enlazar a un mensaje real (ver
// Auditoria::MessageAnnotatorService), no hay inReplyTo resuelto para que
// Base.vue muestre su cuadrito nativo con scroll-to -- mostramos el texto
// citado como cita estatica, sin link, en su lugar.
const staticQuotePreview = computed(() => {
  if (inReplyTo?.value) return '';

  const quotedText = contentAttributes.value?.auditoriaQuotedText;
  return quotedText ? new MessageFormatter(quotedText).formattedMessage : '';
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty && !templateName" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <span v-if="isEmpty && templateName" class="text-n-slate-11 italic">{{
        templateName
      }}</span>
      <div
        v-if="staticQuotePreview"
        class="p-2 -mx-1 rounded-lg bg-n-alpha-black1"
      >
        <div
          v-dompurify-html="staticQuotePreview"
          class="prose prose-bubble line-clamp-2"
        />
      </div>
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <TranslationToggle
        v-if="hasTranslations"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
