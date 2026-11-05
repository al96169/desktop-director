<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import FeatureBanner from './components/FeatureBanner.vue'
import ProductCard from './components/ProductCard.vue'

type Tab = 'home' | 'products' | 'about'
const hash = window.location.hash.replace('#', '') as Tab
const tab = ref<Tab>(['home', 'products', 'about'].includes(hash) ? hash : 'home')
const products = [
  { name: 'Orbit Lamp', price: 129, tag: 'NEW' },
  { name: 'Nebula Chair', price: 349, tag: 'BEST' },
  { name: 'Signal Speaker', price: 199, tag: 'SALE' },
]
const title = computed(() => ({ home: 'Home', products: 'Catalog', about: 'Studio' }[tab.value]))
watchEffect(() => { document.title = `Nova Store · ${title.value}` })
</script>

<template>
  <div class="shell">
    <header class="nav">
      <div class="brand">NOVA<span>·</span>STORE</div>
      <nav>
        <a :class="{ on: tab === 'home' }" href="#home">Home</a>
        <a :class="{ on: tab === 'products' }" href="#products">Products</a>
        <a :class="{ on: tab === 'about' }" href="#about">Studio</a>
      </nav>
      <div class="clock">OPEN 24/7</div>
    </header>

    <main>
      <FeatureBanner />
      <section class="grid" v-if="tab !== 'about'">
        <ProductCard v-for="p in products" :key="p.name" v-bind="p" />
      </section>
      <section class="about" v-else>
        <h2>Design studio for the space age</h2>
        <p>We build furniture and interfaces for people who live slightly ahead of time.</p>
      </section>
    </main>

    <footer>
      <span>{{ title }}</span>
      <span>Vue 3 · Vite · TypeScript</span>
    </footer>
  </div>
</template>
