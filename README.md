# Demografía de Colombia · 2018–2070

**Escenarios, incertidumbre y sensibilidad de la proyección poblacional.** Proyecto académico que contrasta la proyección del DANE con estimaciones de fecundidad calculadas a partir de Estadísticas Vitales (EEVV), y explora cómo cambian los resultados al variar los supuestos demográficos.

> El análisis propio complementa —no reemplaza— la proyección oficial. Las probabilidades de Monte Carlo son condicionales a los supuestos del modelo; la fecundidad EEVV es una estimación indirecta.

## Estructura

| Ruta | Contenido |
|---|---|
| `main.R` | Limpieza y validación de datos DANE y EEVV |
| `modelo.R` | Proyector por cohortes, escenarios, Monte Carlo y sensibilidad |
| `mapa.R` | Procesamiento territorial y generación de GeoJSON |
| `datos_crudos/` | Insumos originales; el shapefile del MGN se obtiene por separado |
| `datos_limpios/` | Datos procesados para el modelo y el dashboard |
| `resultados/` | Resultados tabulares generados por los scripts R |
| `dashboard_observable/` | Sitio web Observable Framework |
| `PROJECT_CONTEXT.md` | Contexto técnico ampliado para continuar el proyecto |
| `FICHA_TECNICA.md` | Descripción metodológica y fuentes del estudio |

## Requisitos

- R y los paquetes `tidyverse`, `readxl` y `sf` (este último para mapas).
- Node.js 18 o posterior y npm.

## Ejecución

Desde la raíz del repositorio, en R/RStudio:

```r
source("main.R")
source("modelo.R")
# Opcional, al contar con los insumos cartográficos:
source("mapa.R")
```

Para levantar y compilar el dashboard, desde `dashboard_observable/`:

```sh
npm ci
npm run dev
# Validación de producción
npm run build
```

La vista local se sirve normalmente en `http://localhost:3000`. Los CSV del dashboard se leen desde `resultados/` y `datos_limpios/` en la raíz; los loaders están en `dashboard_observable/src/data/`.

## Relevo territorial

La carpeta `datos_crudos/mapa/` no contiene actualmente el MGN. Para generar el mapa departamental:

1. Descargar del Geoportal del DANE el Marco Geoestadístico Nacional (MGN), nivel **Departamento**, incluidos los componentes del shapefile (`.shp`, `.shx`, `.dbf`, `.prj`), y guardarlos en `datos_crudos/mapa/`.
2. Confirmar que `main.R` ya generó `datos_limpios/eevv_departamental.csv`.
3. Ejecutar `source("mapa.R")`. Se esperan `datos_limpios/mapa_departamentos.geojson` y `resultados/mapa_metricas_departamento.csv`.
4. Revisar la página `dashboard_observable/src/explorador-geografico.md` y sus loaders asociados; compilar el dashboard.

La agregación opcional a las 22 regiones requiere además el shapefile municipal y `datos_crudos/mapa/municipio_region.csv` con columnas `cod_mpio` (código de cinco dígitos) y `region`. Sin esa correspondencia municipal no se deben inferir ni dibujar regiones.

## Fuentes y uso

Fuentes principales: DANE (proyecciones de población, fecundidad, mortalidad, migración y Marco Geoestadístico Nacional) y Estadísticas Vitales (nacimientos). Consultar `FICHA_TECNICA.md` y los metadatos de cada fuente para detalles y atribución. Los insumos del DANE incluidos en el repositorio se mantienen para reproducibilidad y colaboración; verificar sus condiciones de uso antes de redistribuir públicamente el proyecto.

No se incorpora una licencia de software por ahora: confirmar derechos y condiciones de redistribución de los componentes y datos antes de asignar una.
