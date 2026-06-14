<script setup>
import { computed } from 'vue';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import ModelDropdown from './ModelDropdown.vue';
import ModelInput from './ModelInput.vue';

const props = defineProps({
  featureKey: {
    type: String,
    required: true,
  },
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  isAllowed: {
    type: Boolean,
    required: true,
  },
});

const emit = defineEmits(['change']);

const captainConfigStore = useCaptainConfigStore();

// Check if the selected model for this feature is a self-hosted model
const isSelfHostedModel = computed(() => {
  const selectedModel = captainConfigStore.getSelectedModelForFeature(props.featureKey);
  if (!selectedModel) return false;
  const modelInfo = captainConfigStore.getModels[selectedModel];
  return modelInfo?.provider === 'self_hosted';
});

const handleModelChange = ({ feature, model }) => {
  emit('change', { feature, model });
};
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-weak bg-n-solid-1"
    :class="{ 'opacity-60 pointer-events-none relative': !isAllowed }"
  >
    <div class="flex-1 min-w-0">
      <h4 class="text-sm font-medium text-n-slate-12">
        {{ title }}
      </h4>
      <p class="text-sm text-n-slate-11 mt-0.5">{{ description }}</p>
    </div>
    <ModelInput
      v-if="isAllowed && isSelfHostedModel"
      :feature-key="featureKey"
      @change="handleModelChange"
    />
    <ModelDropdown
      v-else-if="isAllowed"
      :feature-key="featureKey"
      @change="handleModelChange"
    />
  </div>
</template>