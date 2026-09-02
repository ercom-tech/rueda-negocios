# Rails no trae el MIME de Excel, y sin registrarlo `format.xlsx` del reporte
# de productos no existe: la petición cae en un 406 sin explicación.
Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx
