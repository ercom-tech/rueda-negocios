require "csv"

module PriceList
  # Lo que comparten los CSV de "Cambiar precios" (13ª auditoría):
  #
  # - **BOM al inicio.** Sin él, Excel en Windows abre el archivo en la
  #   codificación local y rompe los acentos — la misma trampa que ya resolvía
  #   el reporte de productos.
  # - **Texto que llega de fuera, neutralizado.** Una celda que empieza con
  #   `=`, `+`, `-` o `@` Excel la ejecuta como fórmula al abrir el CSV: un
  #   código como `=HYPERLINK(…)` en el archivo del proveedor, devuelto tal
  #   cual en la revisión, se volvía un enlace activo. Se le antepone un
  #   apóstrofo. Solo al texto ajeno (código del archivo, descripción, nombre
  #   del archivo, usuario): las cifras que arma la app ("-5.1%") son nuestras
  #   y con apóstrofo se verían mal.
  module SafeCsv
    FORMULA_START = /\A[=+\-@\t\r]/

    module_function

    def generate(&) = CSV.generate(String.new("﻿"), &)

    def text(value)
      return value unless value.is_a?(String) && value.match?(FORMULA_START)

      "'#{value}"
    end
  end
end
