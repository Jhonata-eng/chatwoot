<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CaptainLocalModelsAPI from 'dashboard/api/captain/localModels';

const props = defineProps({
  featureKey: {
    type: String,
    required: true,
  },
  modelValue: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue', 'change']);

const { t } = useI18n();
const inputValue = ref(props.modelValue);
const discoveredModels = ref([]);
const isLoadingModels = ref(false);
const discoveryError = ref('');
const showSuggestions = ref(false);

watch(
  () => props.modelValue,
  newVal => {
    inputValue.value = newVal;
  }
);

const filteredSuggestions = computed(() => {
  if (!inputValue.value) return discoveredModels.value;
  const lower = inputValue.value.toLowerCase();
  return discoveredModels.value.filter(m =>
    m.id.toLowerCase().includes(lower)
  );
});

async function discoverModels() {
  isLoadingModels.value = true;
  discoveryError.value = '';
  try {
    const response = await CaptainLocalModelsAPI.get();
    discoveredModels.value = response.data.models || [];
    if (discoveredModels.value.length === 0 && response.data.error) {
      discoveryError.value = response.data.error;
    }
    showSuggestions.value = true;
  } catch (error) {
    discoveryError.value = error.message || 'Failed to discover models';
  } finally {
    isLoadingModels.value = false;
  }
}

function selectModel(modelId) {
  inputValue.value = modelId;
  showSuggestions.value = false;
  emit('update:modelValue', modelId);
  emit('change', { feature: props.featureKey, model: modelId });
}

function onInputChange() {
  showSuggestions.value = false;
  emit('update:modelValue', inputValue.value);
  emit('change', { feature: props.featureKey, model: inputValue.value });
}

function onInputFocus() {
  if (discoveredModels.value.length > 0) {
    showSuggestions.value = true;
  }
}

function onInputBlur() {
  // Delay to allow click on suggestion
  setTimeout(() => {
    showSuggestions.value = false;
  }, 200);
}
</script>

<template>
  <div class="flex flex-col gap-1 w-full">
    <div class="flex gap-2 items-center">
      <input
        v-model="inputValue"
        type="text"
        class="w-full px-3 py-2 text-sm border rounded-lg border-n-weak dark:bg-n-solid-2 bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-iris-6"
        :placeholder="t('CAPTAIN_SETTINGS.MODEL_CONFIG.ENTER_MODEL_NAME')"
        @change="onInputChange"
        @focus="onInputFocus"
        @blur="onInputBlur"
      />
      <button
        type="button"
        class="flex items-center gap-1 px-3 py-2 text-sm border rounded-lg border-n-weak dark:bg-n-solid-2 bg-n-alpha-2 hover:bg-n-alpha-1 whitespace-nowrap"
        :disabled="isLoadingModels"
        @click="discoverModels"
      >
        <Icon
          icon="i-lucide-refresh-cw"
          class="size-3.5"
          :class="{ 'animate-spin': isLoadingModels }"
        />
        {{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.DISCOVER') }}
      </button>
    </div>
    <!-- Discovery error -->
    <p v-if="discoveryError" class="text-xs text-n-ruby-11">
      {{ discoveryError }}
    </p>
    <!-- Suggestions dropdown -->
    <div
      v-if="showSuggestions && filteredSuggestions.length > 0"
      class="border rounded-lg border-n-weak dark:bg-n-solid-2 bg-n-alpha-2 max-h-48 overflow-y-auto"
    >
      <button
        v-for="model in filteredSuggestions"
        :key="model.id"
        type="button"
        class="w-full px-3 py-2 text-sm text-left hover:bg-n-alpha-1 dark:hover:bg-n-solid-3 flex items-center gap-2"
        @mousedown.prevent="selectModel(model.id)"
      >
        <Icon icon="i-ri-server-line" class="size-4 flex-shrink-0 text-n-slate-11" />
        <span class="text-n-slate-12">{{ model.display_name || model.id }}</span>
      </button>
    </div>
    <!-- No models found -->
    <p
      v-if="showSuggestions && filteredSuggestions.length === 0 && !discoveryError && !isLoadingModels && discoveredModels.length === 0"
      class="text-xs text-n-slate-11"
    >
      {{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.NO_MODELS_FOUND') }}
    </p>
  </div>
</template>