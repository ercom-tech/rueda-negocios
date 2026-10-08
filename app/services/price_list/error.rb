module PriceList
  # Error que se le muestra tal cual al operador: el archivo no se pudo usar o
  # no se puede aplicar. Archivo propio para que el autoload lo encuentre sin
  # depender de que alguien haya cargado antes `Reader`.
  class Error < StandardError; end
end
