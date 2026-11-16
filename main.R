# =============================================================================
# PROYECTO DEMOGRAFÍA COLOMBIA - ¿Qué tan firme es el pico de población de 2043?
# main.R : LIMPIEZA Y CONSOLIDACIÓN DE DATOS (fase 1)
#
# QUÉ HACE (en orden)
#   1. Crea la estructura de carpetas y comprueba que estén los archivos crudos
#   2. Limpia las bases nacionales del DANE (población, fecundidad, mortalidad,
#      migración, tablas de vida)
#   3. Limpia la población regional (22 regiones)  -> opcional, si el Excel existe
#   4. Limpia los nacimientos EEVV 2018-2025 (nacional y por departamento)
#   5. Calcula la fecundidad "calculada con EEVV" vs la proyectada por el DANE
#   6. Consolida: controles, diccionario de datos y listado de archivos
#
# CÓMO USARLO
#   1. Abre RStudio y crea/abre un proyecto en la carpeta "proyecto_demografia"
#      (o fija esa carpeta como directorio de trabajo: setwd("ruta/a/proyecto_demografia")).
#   2. Pon los archivos crudos así:
#         datos_crudos/dane/   -> los 5 Excel DCD-* y PPED-* (y el regional si lo tienes)
#         datos_crudos/eevv/   -> los Cuadro 1 y Cuadro 7A de nacimientos 2018-2025
#   3. Ejecuta:  source("main.R")
#
# ESTRUCTURA FINAL
#   proyecto_demografia/
#   ├── main.R                 <- este script
#   ├── datos_crudos/dane/     <- Excel del DANE (no se modifican)
#   ├── datos_crudos/eevv/     <- Excel de nacimientos (no se modifican)
#   ├── datos_limpios/         <- CSV limpios (los que se comparten y se usan después)
#   ├── resultados/            <- tablas de resultados, controles, diccionario
#   └── scripts/               <- (reservado) scripts siguientes: proyector, simulación
#
# REGLAS DEL PROYECTO
#   - Aquí solo se limpia y se comprueba; las bases NO se unen entre sí.
#   - Todo script posterior lee SOLO desde datos_limpios/.
#   - Si un control falla, el script se detiene con un mensaje claro.
# =============================================================================

library(tidyverse)
library(readxl)


# 0. RUTAS Y ESTRUCTURA --------------------------------------------------------
# Todas las rutas salen de aquí; no escribas rutas en otras partes del script.
ruta <- list(
  dane      = file.path("datos_crudos", "dane"),
  eevv      = file.path("datos_crudos", "eevv"),
  limpios   = "datos_limpios",
  resultados = "resultados",
  scripts   = "scripts"
)

invisible(lapply(ruta, dir.create, recursive = TRUE, showWarnings = FALSE))

# Atajos para armar rutas de entrada/salida
en_dane   <- function(f) file.path(ruta$dane, f)
a_limpios <- function(f) file.path(ruta$limpios, f)
a_result  <- function(f) file.path(ruta$resultados, f)

# Nombres de los archivos crudos obligatorios del DANE
crudos_dane <- c(
  poblacion   = "PPED-AreaSexoEdadNac-2018-2070.xlsx",
  fecundidad  = "DCD-Fec-EstNal-Reg-2018-2070_VP.xlsx",
  mortalidad  = "DCD-Mor-EstSexNal-Reg-2018-2070_VP.xlsx",
  migracion   = "DCD-Mig-EstSexNal-Reg-2018-2070_VP.xlsx",
  tablas_vida = "DCD-Tabvidacomplabresexo-2018-2070_VP.xlsx"
)
crudo_regional <- "PPED-AreaSexoEdadReg-2018-2050.xlsx"   # opcional

faltan <- crudos_dane[!file.exists(en_dane(crudos_dane))]
if (length(faltan) > 0) {
  stop("Faltan estos archivos en ", ruta$dane, "/:\n  ", paste(faltan, collapse = "\n  "),
       "\n(¿Estás en la carpeta del proyecto? getwd() = ", getwd(), ")", call. = FALSE)
}

# Lista donde se guardan los controles de todo el flujo (se exporta al final)
controles <- tibble(etapa = character(), control = character(), ok = logical(), detalle = character())
anotar <- function(etapa, control, ok, detalle = "") {
  controles <<- bind_rows(controles, tibble(etapa, control, ok = isTRUE(ok), detalle = as.character(detalle)))
  cat(if (isTRUE(ok)) "  [OK]    " else "  [FALLA] ", etapa, "-", control, detalle, "\n")
}

guardar <- function(datos, nombre) {
  write_csv(datos, a_limpios(paste0(nombre, ".csv")))
  invisible(datos)
}


# 1. BASES NACIONALES DEL DANE -------------------------------------------------
cat("\n== 1. Bases nacionales DANE ==\n")

# Cada Excel tiene 3 hojas: Índice, metadatos y DATOS (la 3.ª). Los datos empiezan
# después de filas de título, por eso `skip`, y se ponen los nombres de columna.
leer <- function(archivo, saltar, nombres) {
  read_excel(en_dane(archivo), sheet = 3, skip = saltar, col_names = nombres)
}
edades <- 0:100

# 1.1 Población (ancho: una columna por sexo y edad; 100 = "100 y más").
# Cabecera y centros poblados llegan a 2050; "total" llega a 2070.
nombres_pob <- c("territorio", "anio", "area", "tot_total", "tot_hombres", "tot_mujeres",
                 paste0("hombres_", edades), paste0("mujeres_", edades), paste0("total_", edades))

pob_ancha <- leer(crudos_dane[["poblacion"]], 9, nombres_pob) %>%
  filter(!is.na(anio)) %>%                                   # quita notas al pie
  mutate(anio = as.integer(anio),
         area = recode(area, "Cabecera" = "cabecera",
                       "Centros Poblados y Rural Disperso" = "centros_poblados_rural",
                       "Total" = "total"))

poblacion <- pob_ancha %>%
  select(anio, area, starts_with("hombres_"), starts_with("mujeres_")) %>%
  pivot_longer(-c(anio, area), names_to = c("sexo", "edad"), names_sep = "_",
               values_to = "poblacion") %>%
  mutate(edad = as.integer(edad)) %>%
  arrange(anio, area, sexo, edad)

totales_oficiales <- pob_ancha %>%
  select(anio, area, total = tot_total, hombres = tot_hombres, mujeres = tot_mujeres) %>%
  arrange(anio, area)

# 1.2 Fecundidad: el Excel trae 22 regiones y el país; nos quedamos con "NAL".
fec <- leer(crudos_dane[["fecundidad"]], 11,
            c("sigla", "territorio", "anio", "area", "tgf", paste0("e", 10:49))) %>%
  filter(sigla == "NAL")

asfr <- fec %>%                                              # tasa por año y edad
  select(anio, starts_with("e")) %>%
  pivot_longer(-anio, names_to = "edad", names_prefix = "e", values_to = "tasa") %>%
  mutate(anio = as.integer(anio), edad = as.integer(edad))

tgf <- fec %>% transmute(anio = as.integer(anio), tgf_dane = tgf)   # hijos por mujer

# 1.3 Mortalidad: mx por sexo y edad (nacional)
mortalidad <- leer(crudos_dane[["mortalidad"]], 11,
                   c("sigla", "territorio", "anio", "area", "sexo", paste0("e", 0:100))) %>%
  filter(sigla == "NAL") %>%
  select(anio, sexo, starts_with("e")) %>%
  pivot_longer(starts_with("e"), names_to = "edad", names_prefix = "e", values_to = "mx") %>%
  mutate(anio = as.integer(anio), sexo = tolower(sexo), edad = as.integer(edad))

# 1.4 Migración: saldo neto (positivo = entran más de los que salen).
# tipo = internacional | interna (a nivel nacional la interna suma cero).
migracion <- leer(crudos_dane[["migracion"]], 11,
                  c("sigla", "territorio", "anio", "area", "sexo", "tipo", paste0("e", 0:100))) %>%
  filter(sigla == "NAL") %>%
  select(anio, sexo, tipo, starts_with("e")) %>%
  pivot_longer(starts_with("e"), names_to = "edad", names_prefix = "e", values_to = "saldo") %>%
  mutate(anio = as.integer(anio), sexo = tolower(sexo), tipo = tolower(tipo),
         edad = as.integer(edad)) %>%
  arrange(anio, tipo, sexo, edad)

# 1.5 Tablas de vida: ya vienen en formato largo (completa = edad simple; abreviada).
# La columna "1(X)" del Excel es lx (letra ele); "L(X)" se llama nLx.
tablas_vida <- leer(crudos_dane[["tablas_vida"]], 10,
                    c("sigla", "territorio", "anio", "area", "sexo", "tipo_tabla", "edad",
                      "qx", "dx", "mx", "lx", "nLx", "sx", "Tx", "ex")) %>%
  filter(sigla == "NAL", area == "Total") %>%
  mutate(anio = as.integer(anio), edad = as.integer(edad),
         sexo = tolower(sexo), tipo_tabla = tolower(tipo_tabla)) %>%
  select(anio, sexo, tipo_tabla, edad, qx:ex) %>%
  arrange(tipo_tabla, anio, sexo, edad)

bases_dane <- list(poblacion = poblacion, totales_oficiales = totales_oficiales, asfr = asfr,
                   tgf = tgf, mortalidad = mortalidad, migracion = migracion,
                   tablas_vida = tablas_vida)

# 1.6 Controles
filas_esperadas <- c(poblacion = 24038, totales_oficiales = 119, asfr = 2120, tgf = 53,
                     mortalidad = 10706, migracion = 21412, tablas_vida = 12614)
for (nm in names(bases_dane)) {
  anotar("dane", paste("filas", nm), nrow(bases_dane[[nm]]) == filas_esperadas[[nm]],
         paste0("(", nrow(bases_dane[[nm]]), ")"))
  anotar("dane", paste("sin vacíos", nm), sum(is.na(bases_dane[[nm]])) == 0)
}

# La población por sexo y edad debe sumar los totales oficiales del DANE
chequeo_pob <- poblacion %>% group_by(anio, area) %>%
  summarise(suma = sum(poblacion), .groups = "drop") %>%
  left_join(totales_oficiales, by = c("anio", "area"))
anotar("dane", "población suma el total oficial", all(abs(chequeo_pob$suma - chequeo_pob$total) < 1))

pico <- totales_oficiales %>% filter(area == "total") %>% slice_max(total, n = 1)
anotar("dane", "pico DANE = 2043", pico$anio == 2043, paste0("(", pico$anio, ": ", format(pico$total, big.mark = ","), ")"))

iwalk(bases_dane, ~ guardar(.x, paste0(.y, "_limpia")))


# 2. POBLACIÓN REGIONAL (OPCIONAL) --------------------------------------------
cat("\n== 2. Población regional (22 regiones) ==\n")

if (!file.exists(en_dane(crudo_regional))) {
  cat("  (se omite: no está", crudo_regional, "en", ruta$dane, ")\n")
} else {
  nombres_reg <- c("sigla", "territorio", "anio", "area", "tot_total", "tot_hombres", "tot_mujeres",
                   paste0("hombres_", edades), paste0("mujeres_", edades), paste0("total_", edades))

  pob_reg_ancha <- read_excel(en_dane(crudo_regional), sheet = 3, skip = 9, col_names = nombres_reg) %>%
    filter(!is.na(anio)) %>%
    mutate(anio = as.integer(anio),
           area = recode(area, "Cabecera" = "cabecera",
                         "Centros Poblados y Rural Disperso" = "centros_poblados_rural",
                         "Total" = "total"))

  poblacion_regional <- pob_reg_ancha %>%
    select(sigla, territorio, anio, area, starts_with("hombres_"), starts_with("mujeres_")) %>%
    pivot_longer(-c(sigla, territorio, anio, area), names_to = c("sexo", "edad"),
                 names_sep = "_", values_to = "poblacion") %>%
    mutate(edad = as.integer(edad)) %>%
    arrange(sigla, anio, area, sexo, edad)

  totales_regional <- pob_reg_ancha %>%
    select(sigla, territorio, anio, area, total = tot_total, hombres = tot_hombres, mujeres = tot_mujeres) %>%
    arrange(sigla, anio, area)

  # Controles: 22 regiones, años 2018-2050, sin vacíos, suma = total oficial,
  # y la suma de regiones coincide con el total nacional (tolerancia 1 persona)
  anotar("regional", "22 regiones", n_distinct(poblacion_regional$sigla) == 22,
         paste0("(", n_distinct(poblacion_regional$sigla), ")"))
  anotar("regional", "años 2018-2050", identical(range(poblacion_regional$anio), c(2018L, 2050L)))
  anotar("regional", "sin vacíos", sum(is.na(poblacion_regional)) == 0)

  chequeo_reg <- poblacion_regional %>% group_by(sigla, anio, area) %>%
    summarise(suma = sum(poblacion), .groups = "drop") %>%
    left_join(totales_regional, by = c("sigla", "anio", "area"))
  anotar("regional", "suma = total oficial regional", all(abs(chequeo_reg$suma - chequeo_reg$total) < 1))

  reg_vs_nal <- poblacion_regional %>% filter(area == "total") %>%
    group_by(anio) %>% summarise(regiones = sum(poblacion), .groups = "drop") %>%
    left_join(totales_oficiales %>% filter(area == "total") %>% select(anio, nacional = total), by = "anio")
  anotar("regional", "regiones suman el nacional", all(abs(reg_vs_nal$regiones - reg_vs_nal$nacional) < 1))

  guardar(poblacion_regional, "poblacion_regional_2018_2050_limpia")
  guardar(totales_regional,   "totales_oficiales_regional_limpia")
}


# 3. NACIMIENTOS EEVV 2018-2025 -----------------------------------------------
cat("\n== 3. Nacimientos EEVV ==\n")

# 3.1 Algunos .xls del DANE (2020, 2021, 2023) vienen protegidos y R no los abre.
# En Windows se convierten a .xlsx con Excel (solo los que aún no tienen .xlsx).
if (.Platform$OS.type == "windows") {
  ps <- c(
    '$excel = New-Object -ComObject Excel.Application',
    '$excel.Visible = $false',
    '$excel.DisplayAlerts = $false',
    sprintf('Get-ChildItem -Path "%s" -Recurse | Where-Object { $_.Extension -eq ".xls" -and $_.Name -match "(?i)nacimientos" } | ForEach-Object {',
            normalizePath(ruta$eevv)),
    '  $destino = $_.FullName + "x"',
    '  if (-not (Test-Path $destino)) {',
    '    $wb = $excel.Workbooks.Open($_.FullName)',
    '    $wb.SaveAs($destino, 51)',
    '    $wb.Close($false)',
    '    Write-Host ("Convertido: " + $_.Name)',
    '  }',
    '}',
    '$excel.Quit()'
  )
  archivo_ps <- tempfile(fileext = ".ps1")
  writeLines(ps, archivo_ps)
  system2("powershell", c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", shQuote(archivo_ps)),
          wait = TRUE, stdout = FALSE)
}

anios <- 2018:2025
grupos <- c("10-14", "15-19", "20-24", "25-29", "30-34", "35-39", "40-44", "45-49", "50-54", "sin_info")

excel <- list.files(ruta$eevv, pattern = "\\.xlsx?$", ignore.case = TRUE, recursive = TRUE, full.names = TRUE)
excel <- excel[str_detect(basename(excel), "(?i)nacimientos") & str_detect(basename(excel), "(?i)cuadro")]

# Archivo de un año/cuadro; prefiere .xlsx. Solo 2018 trae un archivo por cuadro.
buscar <- function(anio, cuadro) {
  cand <- excel[str_detect(basename(excel), as.character(anio))]
  if (anio == 2018) cand <- cand[str_detect(basename(cand), regex(cuadro, ignore_case = TRUE))]
  if (length(cand) == 0) stop("No encuentro el archivo EEVV de ", anio, " (", cuadro, ") en ", ruta$eevv, call. = FALSE)
  cand_xlsx <- cand[str_detect(cand, "(?i)\\.xlsx$")]
  if (length(cand_xlsx) > 0) cand_xlsx[1] else cand[1]
}

fuentes <- tibble(anio = anios) %>%
  mutate(archivo_c1  = map_chr(anio, buscar, "Cuadro1"),
         archivo_c7a = map_chr(anio, buscar, "Cuadro7a"))

no_abre <- unique(c(fuentes$archivo_c1, fuentes$archivo_c7a)) %>%
  keep(~ inherits(try(excel_sheets(.x), silent = TRUE), "try-error"))
if (length(no_abre) > 0) {
  stop("R no puede abrir (archivo protegido): ", paste(basename(no_abre), collapse = ", "),
       "\nConviértelos a .xlsx (en Windows el script lo hace solo si Excel está instalado y cerrado).",
       call. = FALSE)
}

# 3.2 Lectura
leer_hoja <- function(archivo, patron_hoja) {
  hojas <- excel_sheets(archivo)
  hoja  <- if (length(hojas) == 1) 1 else str_subset(hojas, regex(patron_hoja, ignore_case = TRUE))[1]
  read_excel(archivo, sheet = hoja, col_names = FALSE, col_types = "text",
             n_max = 80, .name_repair = "minimal") %>%
    set_names(paste0("V", seq_len(ncol(.))))
}

etiqueta_edad <- function(x) {
  case_when(str_detect(x, "(?i)^total") ~ "total",
            str_detect(x, "(?i)^sin")   ~ "sin_info",
            TRUE ~ str_extract(x, "[0-9]+-[0-9]+"))
}

# Cuadro 1: nacimientos por edad de la madre (filas = grupos de edad), total nacional
leer_cuadro1 <- function(archivo, anio) {
  leer_hoja(archivo, "^cuadro ?1$") %>%
    filter(str_detect(V1, "(?i)^(total nacional|de [0-9]|sin informaci)")) %>%
    transmute(anio = anio, grupo_edad = etiqueta_edad(V1),
              nacimientos = as.numeric(V2), hombres = as.numeric(V3),
              mujeres = as.numeric(V4), indeterminado = as.numeric(V5))
}

# Cuadro 7A: departamento de residencia de la madre x grupo de edad
leer_cuadro7a <- function(archivo, anio) {
  x  <- leer_hoja(archivo, "^cuadro ?7a$")
  c0 <- which(map_int(x, ~ sum(str_detect(.x, "^[0-9]{2} "), na.rm = TRUE)) >= 20)[1]   # columna con códigos de dpto

  enc <- x[which(str_detect(x[[c0 + 2]], "De 10-14"))[1], (c0 + 2):(c0 + 11)] %>% unlist()
  if (!all(str_detect(enc, c("10-14", "15-19", "20-24", "25-29", "30-34",
                             "35-39", "40-44", "45-49", "50-54", "(?i)^sin")))) {
    stop("Cuadro 7A ", anio, ": los encabezados de edad no son los esperados.", call. = FALSE)
  }

  x[, c0:(c0 + 11)] %>%
    set_names(c("rotulo", "total", grupos)) %>%
    filter(str_detect(rotulo, "(?i)^([0-9]{2} |total|extranjer|sin inf)")) %>%
    mutate(anio = anio,
           cod_dpto = case_when(str_detect(rotulo, "^[0-9]{2} ")     ~ str_extract(rotulo, "^[0-9]{2}"),
                                str_detect(rotulo, "(?i)^extranjer") ~ "EX",   # madre residente en el exterior
                                str_detect(rotulo, "(?i)^sin inf")   ~ "SI",   # sin información
                                TRUE                                 ~ "TOTAL"),
           departamento = str_squish(str_remove(rotulo, "^[0-9]{2}\\s*")),
           across(c(total, all_of(grupos)), as.numeric)) %>%
    select(anio, cod_dpto, departamento, total, all_of(grupos))
}

nacional_ancho <- map2_dfr(fuentes$archivo_c1,  fuentes$anio, leer_cuadro1)
depto_ancho    <- map2_dfr(fuentes$archivo_c7a, fuentes$anio, leer_cuadro7a)

eevv_nacional <- nacional_ancho %>% filter(grupo_edad != "total") %>% arrange(anio, grupo_edad)

eevv_departamental <- depto_ancho %>%
  filter(cod_dpto != "TOTAL") %>%
  pivot_longer(all_of(grupos), names_to = "grupo_edad", values_to = "nacimientos") %>%
  select(anio, cod_dpto, departamento, grupo_edad, nacimientos, total_depto = total) %>%
  arrange(anio, cod_dpto, grupo_edad)

# 3.3 Controles. Totales definitivos del DANE (boletines EEVV).
total_dane <- c("2018" = 649115, "2019" = 642660, "2020" = 629402, "2021" = 616914,
                "2022" = 573625, "2023" = 515549, "2024" = 453901, "2025" = 441537)

ctrl_eevv <- nacional_ancho %>% filter(grupo_edad == "total") %>%
  select(anio, total_c1 = nacimientos, hombres, mujeres, indeterminado) %>%
  left_join(depto_ancho %>% filter(cod_dpto == "TOTAL") %>% select(anio, total_7a = total), by = "anio") %>%
  left_join(eevv_nacional %>% group_by(anio) %>% summarise(suma_edades = sum(nacimientos)), by = "anio") %>%
  left_join(eevv_departamental %>% group_by(anio) %>% summarise(suma_deptos = sum(nacimientos)), by = "anio") %>%
  mutate(total_dane = total_dane[as.character(anio)])

ok_depto <- eevv_departamental %>% group_by(anio, cod_dpto) %>%
  summarise(ok = sum(nacimientos) == first(total_depto), .groups = "drop")

anotar("eevv", "total Cuadro 1 = total DANE",     all(ctrl_eevv$total_c1 == ctrl_eevv$total_dane))
anotar("eevv", "grupos de edad suman el total",   all(ctrl_eevv$total_c1 == ctrl_eevv$suma_edades))
anotar("eevv", "hombres+mujeres+indet = total",   all(ctrl_eevv$total_c1 == ctrl_eevv$hombres + ctrl_eevv$mujeres + ctrl_eevv$indeterminado))
anotar("eevv", "Cuadro 7A = Cuadro 1",            all(ctrl_eevv$total_c1 == ctrl_eevv$total_7a & ctrl_eevv$total_7a == ctrl_eevv$suma_deptos))
anotar("eevv", "cada depto suma su total",        all(ok_depto$ok), paste0("(", sum(ok_depto$ok), " de ", nrow(ok_depto), ")"))
anotar("eevv", "sin vacíos",                      sum(is.na(eevv_nacional)) + sum(is.na(eevv_departamental)) == 0)

guardar(eevv_nacional, "eevv_nacional")
guardar(eevv_departamental, "eevv_departamental")


# 4. FECUNDIDAD CALCULADA CON EEVV vs PROYECTADA POR EL DANE -------------------
cat("\n== 4. Fecundidad calculada con EEVV vs DANE ==\n")

# "Calculada con EEVV" = nacimientos EEVV / mujeres de la proyección DANE.
# Ojo: EEVV incluye hijos de madres residentes en el exterior y excluye registros tardíos.

grupo_5 <- function(e) {
  as.character(cut(e, c(9, 14, 19, 24, 29, 34, 39, 44, 49),
                   labels = c("10-14", "15-19", "20-24", "25-29", "30-34", "35-39", "40-44", "45-49")))
}

mujeres_edad <- poblacion %>%
  filter(area == "total", sexo == "mujeres", edad %in% 10:49) %>%
  transmute(anio, edad, mujeres = poblacion)

mujeres_grupo <- mujeres_edad %>% mutate(grupo = grupo_5(edad)) %>%
  group_by(anio, grupo) %>% summarise(mujeres = sum(mujeres), .groups = "drop")

# Variantes de tratamiento de 50-54 y "sin información" (para ver cuánto cambia la TGF)
calcular_tgf <- function(sumar_50_54, repartir_sin_info) {
  nac <- eevv_nacional %>%
    mutate(grupo = if_else(grupo_edad == "50-54" & sumar_50_54, "45-49", grupo_edad)) %>%
    group_by(anio, grupo) %>% summarise(nacimientos = sum(nacimientos), .groups = "drop")
  sin_info <- nac %>% filter(grupo == "sin_info") %>% select(anio, sin_info = nacimientos)
  nac %>% filter(grupo %in% unique(mujeres_grupo$grupo)) %>%
    left_join(sin_info, by = "anio") %>%
    group_by(anio) %>%
    mutate(nacimientos = if (repartir_sin_info) nacimientos * (1 + sin_info / sum(nacimientos)) else nacimientos) %>%
    ungroup() %>%
    left_join(mujeres_grupo, by = c("anio", "grupo")) %>%
    mutate(tasa_eevv = nacimientos / mujeres)
}

# Variante base: 50-54 se suma a 45-49 (el DANE proyecta hasta 49) y sin_info se reparte
base_eevv <- calcular_tgf(TRUE, TRUE)

# DANE por grupo de edad: promedio de tasas por edad simple ponderado por mujeres
dane_grupo <- asfr %>%
  inner_join(mujeres_edad, by = c("anio", "edad")) %>%
  mutate(grupo = grupo_5(edad)) %>%
  group_by(anio, grupo) %>%
  summarise(tasa_dane = sum(tasa * mujeres) / sum(mujeres), .groups = "drop")

fecundidad_calculada_vs_dane <- base_eevv %>%
  left_join(dane_grupo, by = c("anio", "grupo")) %>%
  mutate(razon = tasa_dane / tasa_eevv) %>%            # >1: el DANE proyecta más que lo calculado
  select(anio, grupo, tasa_eevv, tasa_dane, razon)

tgf_calculada_vs_dane <- fecundidad_calculada_vs_dane %>%
  group_by(anio) %>% summarise(tgf_eevv = 5 * sum(tasa_eevv), .groups = "drop") %>%
  left_join(tgf, by = "anio") %>%
  mutate(razon = tgf_dane / tgf_eevv)

# Sensibilidad: ¿cambia mucho la TGF según cómo se traten 50-54 y sin_info?
sensibilidad_tgf <- expand_grid(sumar_50_54 = c(TRUE, FALSE), repartir_sin_info = c(TRUE, FALSE)) %>%
  mutate(res = map2(sumar_50_54, repartir_sin_info,
                    ~ calcular_tgf(.x, .y) %>% group_by(anio) %>%
                      summarise(tgf_eevv = 5 * sum(tasa_eevv), .groups = "drop"))) %>%
  unnest(res)

dif_max <- sensibilidad_tgf %>% group_by(anio) %>% summarise(d = max(tgf_eevv) - min(tgf_eevv)) %>% pull(d) %>% max()
anotar("fecundidad", "TGF 2025 EEVV ≈ 1,03", abs(tgf_calculada_vs_dane$tgf_eevv[tgf_calculada_vs_dane$anio == 2025] - 1.03) < 0.01)
anotar("fecundidad", "variantes de 50-54/sin_info cambian la TGF poco", dif_max < 0.02,
       paste0("(máx ", round(dif_max, 3), ")"))

print(tgf_calculada_vs_dane %>% mutate(across(-anio, ~ round(.x, 2))), n = Inf)

write_csv(fecundidad_calculada_vs_dane, a_result("fecundidad_calculada_vs_dane.csv"))
write_csv(tgf_calculada_vs_dane,        a_result("tgf_calculada_vs_dane.csv"))
write_csv(sensibilidad_tgf,             a_result("sensibilidad_tgf_tratamiento.csv"))
write_csv(totales_oficiales %>% filter(area == "total") %>% transmute(anio, poblacion_dane = total),
          a_result("serie_dane_poblacion_total.csv"))


# 5. CONSOLIDACIÓN -------------------------------------------------------------
cat("\n== 5. Consolidación ==\n")

diccionario <- tribble(
  ~archivo, ~columnas, ~descripcion,
  "datos_limpios/poblacion_limpia.csv", "anio, area, sexo, edad, poblacion", "Población proyectada nacional 2018-2070; edad 100 = 100+; cabecera/centros_poblados_rural solo a 2050",
  "datos_limpios/totales_oficiales_limpia.csv", "anio, area, total, hombres, mujeres", "Totales oficiales DANE (control)",
  "datos_limpios/asfr_limpia.csv", "anio, edad, tasa", "Tasa de fecundidad por edad (10-49), proyección DANE",
  "datos_limpios/tgf_limpia.csv", "anio, tgf_dane", "Hijos por mujer, proyección DANE",
  "datos_limpios/mortalidad_limpia.csv", "anio, sexo, edad, mx", "Tasa de mortalidad por sexo y edad",
  "datos_limpios/migracion_limpia.csv", "anio, sexo, tipo, edad, saldo", "Migración neta; usar tipo = internacional",
  "datos_limpios/tablas_vida_limpia.csv", "anio, sexo, tipo_tabla, edad, qx, dx, mx, lx, nLx, sx, Tx, ex", "Tablas de vida completas y abreviadas",
  "datos_limpios/eevv_nacional.csv", "anio, grupo_edad, nacimientos, hombres, mujeres, indeterminado", "Nacimientos EEVV 2018-2025 por edad de la madre",
  "datos_limpios/eevv_departamental.csv", "anio, cod_dpto, departamento, grupo_edad, nacimientos, total_depto", "Nacimientos por departamento de residencia de la madre (EX = exterior, SI = sin información)",
  "datos_limpios/poblacion_regional_2018_2050_limpia.csv", "sigla, territorio, anio, area, sexo, edad, poblacion", "Población por 22 regiones (solo si existe el Excel regional)",
  "resultados/serie_dane_poblacion_total.csv", "anio, poblacion_dane", "Serie de población total DANE (pico 2043)",
  "resultados/tgf_calculada_vs_dane.csv", "anio, tgf_eevv, tgf_dane, razon", "TGF calculada con EEVV vs proyectada por el DANE",
  "resultados/fecundidad_calculada_vs_dane.csv", "anio, grupo, tasa_eevv, tasa_dane, razon", "Tasas por grupo quinquenal",
  "resultados/sensibilidad_tgf_tratamiento.csv", "sumar_50_54, repartir_sin_info, anio, tgf_eevv", "TGF según el tratamiento de 50-54 y sin información",
  "resultados/controles.csv", "etapa, control, ok, detalle", "Todos los controles de este flujo"
)
write_csv(diccionario, a_result("diccionario_datos.csv"))
write_csv(controles,   a_result("controles.csv"))

cat("\nControles OK:", sum(controles$ok), "de", nrow(controles), "\n")
cat("Archivos en datos_limpios/:\n"); print(list.files(ruta$limpios))
cat("Archivos en resultados/:\n");    print(list.files(ruta$resultados))

if (!all(controles$ok)) {
  print(controles %>% filter(!ok))
  stop("Hay controles que fallaron: revisa la tabla anterior antes de usar los datos.", call. = FALSE)
}
cat("\nListo: datos limpios y resultados consolidados.\n")
