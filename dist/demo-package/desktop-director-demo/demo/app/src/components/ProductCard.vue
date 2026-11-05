<script setup lang="ts">
defineProps<{ name: string; price: number; tag: string }>()
</script>

<template>
  <article class="card">
    <div class="tag">{{ tag }}</div>
    <h3>{{ name }}</h3>
    <p class="price">${{ price }}</p>
    <button>Add to cart</button>
  </article>
</template>
