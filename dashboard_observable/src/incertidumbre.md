---
toc: false
---
<p class="page-kicker">ANÁLISIS · 03</p>

# Incertidumbre

## ¿Qué tan firme es el 2043?

La simulación Monte Carlo combina supuestos variables de fecundidad, mortalidad y migración. Los resultados describen incertidumbre condicionada al modelo, no una proyección oficial.

```js
import * as Plot from "npm:@observablehq/plot";
import {html} from "htl";
```

```js
const bandasFuente = await FileAttachment("data/montecarlo_bandas.csv").csv({typed: true});
const resumenMontecarloFuente = await FileAttachment("data/montecarlo_resumen.csv").csv({typed: true});
const picosFuente = await FileAttachment("data/montecarlo_pico.csv").csv({typed: true});
```

```js
const bandasValidas = bandasFuente.filter(d =>
  Number.isFinite(d.anio) && Number.isFinite(d.p5) && Number.isFinite(d.p50) &&
  Number.isFinite(d.p95) && Number.isFinite(d.dane)
).map(d => ({
  ...d,
  p5_millones: d.p5 / 1e6,
  p50_millones: d.p50 / 1e6,
  p95_millones: d.p95 / 1e6,
  dane_millones: d.dane / 1e6
})).sort((a, b) => a.anio - b.anio);
const bandasSimuladas = bandasValidas.map(d => ({
  anio: d.anio,
  p5_millones: d.p5_millones,
  p50_millones: d.p50_millones,
  p95_millones: d.p95_millones
}));
const daneReferencia = bandasValidas.map(d => ({anio: d.anio, dane_millones: d.dane_millones}));
const resumenMontecarlo = resumenMontecarloFuente[0];
const picosValidos = picosFuente.filter(d => Number.isFinite(d.anio_pico));
if (!bandasValidas.length || !resumenMontecarlo || !picosValidos.length) throw new Error("Faltan datos válidos para resumir la incertidumbre.");
const formatoPorcentaje = new Intl.NumberFormat("es-CO", {style: "percent", maximumFractionDigits: 1});
const formatoMillones = new Intl.NumberFormat("es-CO", {minimumFractionDigits: 2, maximumFractionDigits: 2});
const serieFrecuenciaPico = [...new Set(picosValidos.map(d => d.anio_pico))].sort((a, b) => a - b).map(anio => ({
  anio_pico: anio,
  simulaciones: picosValidos.filter(d => d.anio_pico === anio).length
}));
```

<div class="editorial-section" aria-label="Indicadores de incertidumbre">
  <p class="section-kicker">DISTRIBUCIÓN DEL AÑO DEL MÁXIMO POBLACIONAL · ${resumenMontecarlo.n} SIMULACIONES</p>
  <div class="section-grid" style="grid-template-columns: repeat(auto-fit, minmax(175px, 1fr));">
    <article class="section-card"><span class="card-index">ANTES DE 2043</span><h3>${formatoPorcentaje.format(resumenMontecarlo.prob_antes_2043)}</h3><span>Proporción simulada bajo el modelo</span></article>
    <article class="section-card"><span class="card-index">EN 2043</span><h3>${formatoPorcentaje.format(resumenMontecarlo.prob_en_2043)}</h3><span>Proporción simulada bajo el modelo</span></article>
    <article class="section-card"><span class="card-index">DESPUÉS DE 2043</span><h3>${formatoPorcentaje.format(resumenMontecarlo.prob_despues_2043)}</h3><span>Proporción simulada bajo el modelo</span></article>
    <article class="section-card"><span class="card-index">MEDIANA DEL AÑO DEL MÁXIMO POBLACIONAL</span><h3>${resumenMontecarlo.pico_mediana}</h3><span>Año central de las simulaciones</span></article>
    <article class="section-card"><span class="card-index">INTERVALO P5–P95</span><h3>${resumenMontecarlo.pico_p5}–${resumenMontecarlo.pico_p95}</h3><span>Rango percentil del año del máximo poblacional</span></article>
  </div>
</div>

<section class="editorial-section" aria-labelledby="abanico-incertidumbre">
  <p class="section-kicker">POBLACIÓN SIMULADA</p>
  <h2 id="abanico-incertidumbre">El rango de trayectorias se abre alrededor del máximo</h2>
  <p>El área muestra P5–P95 y la línea central, P50 de población simulada. La serie del DANE aparece como referencia externa.</p>
</section>

```js
Plot.plot({
  width,
  height: 410,
  marginLeft: 82,
  marginBottom: 48,
  x: {label: "Año", ticks: 8, tickFormat: d => String(Math.round(d))},
  y: {label: "Población (millones de habitantes)", grid: true, tickFormat: d => d.toLocaleString("es-CO", {maximumFractionDigits: 0})},
  marks: [
    Plot.areaY(bandasValidas, {x: "anio", y1: "p5_millones", y2: "p95_millones", fill: "#DCEBEC"}),
    Plot.ruleX([2043], {stroke: "#C8795B", strokeDasharray: "4,4", strokeWidth: 1.5}),
    Plot.line(bandasValidas, {x: "anio", y: "p5_millones", stroke: "#75AEB1", strokeDasharray: "3,3", strokeWidth: 1}),
    Plot.line(bandasValidas, {x: "anio", y: "p95_millones", stroke: "#75AEB1", strokeDasharray: "3,3", strokeWidth: 1}),
    Plot.line(bandasValidas, {x: "anio", y: "p50_millones", stroke: "#176B73", strokeWidth: 2.5}),
    Plot.line(bandasValidas, {x: "anio", y: "dane_millones", stroke: "#687789", strokeWidth: 2, strokeDasharray: "6,3"}),
    Plot.dot(bandasSimuladas, Plot.pointer({
      x: "anio",
      y: "p50_millones",
      maxRadius: 12,
      r: 4,
      fill: "#176B73"
    })),
    Plot.tip(bandasSimuladas, Plot.pointer({
      x: "anio",
      y: "p50_millones",
      maxRadius: 12,
      title: d => `Año: ${d.anio}\nSimulación Monte Carlo\nP5: ${formatoMillones.format(d.p5_millones)} millones\nP50: ${formatoMillones.format(d.p50_millones)} millones\nP95: ${formatoMillones.format(d.p95_millones)} millones`
    })),
    Plot.dot(daneReferencia, Plot.pointer({
      x: "anio",
      y: "dane_millones",
      maxRadius: 12,
      r: 4,
      fill: "#687789"
    })),
    Plot.tip(daneReferencia, Plot.pointer({
      x: "anio",
      y: "dane_millones",
      maxRadius: 12,
      title: d => `Año: ${d.anio}\nDANE: ${formatoMillones.format(d.dane_millones)} millones`
    }))
  ]
})
```

<p class="method-note"><strong>Lectura:</strong> área = P5–P95; línea central = P50; gris = DANE; vertical = 2043. El cursor muestra los valores anuales.</p>

<section class="editorial-section" aria-labelledby="distribucion-maximo-poblacional">
  <p class="section-kicker">DISTRIBUCIÓN DE SIMULACIONES</p>
  <h2 id="distribucion-maximo-poblacional">Distribución simulada del año máximo</h2>
  <p>El histograma muestra la frecuencia de cada año y complementa el intervalo P5–P95.</p>
</section>

```js
Plot.plot({
  width,
  height: 300,
  marginLeft: 70,
  marginBottom: 48,
  x: {label: "Año del máximo poblacional", tickFormat: d => String(Math.round(d))},
  y: {label: "Simulaciones", grid: true},
  marks: [
    Plot.ruleX([2043], {stroke: "#687789", strokeDasharray: "4,4"}),
    Plot.barY(serieFrecuenciaPico, {
      x: "anio_pico",
      y: "simulaciones",
      fill: "#C8795B",
      tip: true,
      title: d => `Año del máximo poblacional: ${String(d.anio_pico)}\nSimulaciones: ${d.simulaciones}`
    })
  ]
})
```

<section class="editorial-section" aria-labelledby="lectura-incertidumbre">
  <p class="section-kicker">LECTURA E INTERPRETACIÓN</p>
  <h2 id="lectura-incertidumbre">La mediana simulada difiere de 2043</h2>
  <p>La mediana del año máximo es ${resumenMontecarlo.pico_mediana} (P5–P95: ${resumenMontecarlo.pico_p5}–${resumenMontecarlo.pico_p95}). La proporción de máximos anteriores a 2043 es ${formatoPorcentaje.format(resumenMontecarlo.prob_antes_2043)}; la proporción en 2043, ${formatoPorcentaje.format(resumenMontecarlo.prob_en_2043)}.</p>
  <aside class="method-note"><strong>Alcance:</strong> las proporciones dependen de las distribuciones asumidas para fecundidad, mortalidad y migración; no son probabilidades oficiales del DANE.</aside>
</section>
