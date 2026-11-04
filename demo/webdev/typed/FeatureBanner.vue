<script setup lang="ts">
const features = [
  { k: '01', t: 'Zero-gravity comfort' },
  { k: '02', t: 'Signal-grade materials' },
  { k: '03', t: 'Built to outlive trends' },
]
</script>

<template>
  <section class="banner">
    <span class="eyebrow">AUTUMN DROP · 2026</span>
    <h1>Furniture for the next orbit.</h1>
    <p>Every piece is prototyped in our studio, tested for a decade, and shipped flat.</p>
    <ul class="feats">
      <li v-for="f in features" :key="f.k"><b>{{ f.k }}</b>{{ f.t }}</li>
    </ul>
  </section>
</template>

<style scoped>
.eyebrow { color: var(--amber); font-size: 11px; letter-spacing: 3px; }
.banner h1 { margin: 10px 0 12px; font-size: 38px; letter-spacing: 1px; }
.feats { list-style: none; display: flex; gap: 28px; padding: 18px 0 0; margin: 0; }
.feats li { color: var(--dim); font-size: 12px; letter-spacing: 1px; }
.feats b { color: var(--accent); margin-right: 8px; }
</style>
