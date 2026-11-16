# =============================================================================
# PROYECTO DEMOGRAFÍA COLOMBIA
# mapa.R : PREPARA LOS MAPAS PARA EL TABLERO
#
# REQUISITO: haber corrido main.R. Necesita el shapefile del DANE (ver abajo).
#
# QUÉ DESCARGAR (una sola vez)
#   Geoportal DANE > Descargas > Marco Geoestadístico Nacional (MGN) > nivel
#   "Departamento" (archivo MGN_DPTO_POLITICO.shp + .shx .dbf .prj, juntos).
#   Guárdalos en:  datos_crudos/mapa/
#   (Opcional, para regiones) el MGN nivel "Municipio" (MGN_MPIO_POLITICO.shp) y
#   una tabla municipio -> región:  datos_crudos/mapa/municipio_region.csv
#   con columnas  cod_mpio (5 dígitos)  y  region (sigla DANE, p. ej. "VDA").
#
# QUÉ HACE
#   1. Lee los polígonos departamentales, los pasa a WGS84 y los simplifica (liviano para web)
#   2. Une los nacimientos EEVV por departamento (clave: código de 2 dígitos)
#   3. (Opcional) Disuelve municipios en las 22 regiones del DANE
#
# SALIDAS
#   datos_limpios/mapa_departamentos.geojson   polígonos + métricas, listo para el tablero
#   resultados/mapa_metricas_departamento.csv  las mismas métricas en tabla
#   datos_limpios/mapa_regiones.geojson        solo si existe la tabla municipio -> región
# =============================================================================

library(tidyverse)
library(sf)

dir.create("datos_crudos/mapa", recursive = TRUE, showWarnings = FALSE)

# Lee un shapefile, lo pasa a WGS84 (lat/lon) y lo simplifica (tolerancia en grados)
leer_shape <- function(patron, tolerancia = 0.005) {
  f <- list.files("datos_crudos/mapa", pattern = patron, full.names = TRUE, ignore.case = TRUE)
  f <- f[str_detect(f, "(?i)\\.shp$")]
  if (length(f) == 0) stop("No encuentro un shapefile que coincida con '", patron, "' en datos_crudos/mapa/", call. = FALSE)
  st_read(f[1], quiet = TRUE) %>%
    st_transform(4326) %>%
    st_make_valid() %>%
    st_simplify(dTolerance = tolerancia, preserveTopology = TRUE)
}


# 1. DEPARTAMENTOS -------------------------------------------------------------
dptos <- leer_shape("DPTO")
if (!"DPTO_CCDGO" %in% names(dptos)) stop("El shapefile no trae la columna DPTO_CCDGO; columnas: ", paste(names(dptos), collapse = ", "), call. = FALSE)

dptos <- dptos %>%
  transmute(cod_dpto = str_pad(as.character(DPTO_CCDGO), 2, pad = "0"),
            nombre = if ("DPTO_CNMBR" %in% names(.)) DPTO_CNMBR else cod_dpto)


# 2. MÉTRICAS POR DEPARTAMENTO (desde los datos limpios) -----------------------
eevv <- read_csv("datos_limpios/eevv_departamental.csv", show_col_types = FALSE) %>%
  filter(!cod_dpto %in% c("EX", "SI")) %>%                          # sin departamento no se mapea
  group_by(anio, cod_dpto) %>% summarise(nacimientos = sum(nacimientos), .groups = "drop")

metricas <- eevv %>%
  pivot_wider(names_from = anio, values_from = nacimientos, names_prefix = "nac_") %>%
  mutate(variacion_nac_2018_2025_pct = 100 * (nac_2025 / nac_2018 - 1),
         participacion_nac_2025_pct  = 100 * nac_2025 / sum(nac_2025))

# Controles: los 33 departamentos casan uno a uno con los polígonos
sin_poligono <- setdiff(metricas$cod_dpto, dptos$cod_dpto)
sin_datos    <- setdiff(dptos$cod_dpto, metricas$cod_dpto)
if (length(sin_poligono) + length(sin_datos) > 0) {
  stop("Códigos que no casan. Sin polígono: ", paste(sin_poligono, collapse = ", "),
       " | Sin datos: ", paste(sin_datos, collapse = ", "), call. = FALSE)
}
cat("Departamentos con polígono y datos:", n_distinct(metricas$cod_dpto), "(deben ser 33)\n")

mapa_dptos <- dptos %>% left_join(metricas, by = "cod_dpto")

write_csv(st_drop_geometry(mapa_dptos), "resultados/mapa_metricas_departamento.csv")
if (file.exists("datos_limpios/mapa_departamentos.geojson")) file.remove("datos_limpios/mapa_departamentos.geojson")
st_write(mapa_dptos, "datos_limpios/mapa_departamentos.geojson", quiet = TRUE)


# 3. REGIONES DEL DANE (OPCIONAL) ----------------------------------------------
# Las 22 regiones demográficas se arman con MUNICIPIOS (no con departamentos
# completos), así que se necesitan los polígonos municipales y la tabla municipio -> región.
tabla_region <- "datos_crudos/mapa/municipio_region.csv"
hay_mpio <- length(list.files("datos_crudos/mapa", pattern = "MPIO.*\\.shp$", ignore.case = TRUE)) > 0

if (file.exists(tabla_region) && hay_mpio) {
  mpios <- leer_shape("MPIO", tolerancia = 0.003)
  if (!"MPIO_CDPMP" %in% names(mpios)) stop("El shapefile municipal no trae MPIO_CDPMP.", call. = FALSE)
  m2r <- read_csv(tabla_region, col_types = "cc") %>% transmute(cod_mpio = str_pad(cod_mpio, 5, pad = "0"), region)

  mapa_reg <- mpios %>%
    transmute(cod_mpio = str_pad(as.character(MPIO_CDPMP), 5, pad = "0")) %>%
    left_join(m2r, by = "cod_mpio")
  if (any(is.na(mapa_reg$region))) stop(sum(is.na(mapa_reg$region)), " municipios sin región en municipio_region.csv", call. = FALSE)
  mapa_reg <- mapa_reg %>% group_by(region) %>% summarise(geometry = st_union(geometry), .groups = "drop")
  cat("Regiones:", nrow(mapa_reg), "(deben ser 22; la 23.ª sigla NAL es el total nacional y no se mapea)\n")

  if (file.exists("datos_limpios/mapa_regiones.geojson")) file.remove("datos_limpios/mapa_regiones.geojson")
  st_write(mapa_reg, "datos_limpios/mapa_regiones.geojson", quiet = TRUE)
} else {
  cat("(regiones omitidas: falta datos_crudos/mapa/municipio_region.csv o el shapefile municipal)\n")
}

cat("\nListo: datos_limpios/mapa_departamentos.geojson y resultados/mapa_metricas_departamento.csv\n")