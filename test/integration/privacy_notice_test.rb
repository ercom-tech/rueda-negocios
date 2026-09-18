require "test_helper"

# El aviso de privacidad, en el login: es el momento en que el capturista
# entrega sus datos.
#
# Se sirve desde `public/` de la propia app y no desde el sitio de FECEGO
# porque la laptop del evento NO tiene internet: un enlace externo estaría
# muerto justo cuando alguien lo tocara.
class PrivacyNoticeTest < ActionDispatch::IntegrationTest
  test "el login ofrece el aviso de privacidad" do
    get login_path

    assert_response :success
    assert_select "a[href='/aviso-de-privacidad.pdf']", text: "Aviso de privacidad"
  end

  # Sin sesión: quien todavía no entró tiene que poder leerlo.
  test "el aviso se abre sin haber iniciado sesión" do
    get "/aviso-de-privacidad.pdf"

    assert_response :success
    assert_equal "application/pdf", response.media_type
  end

  # El archivo tiene que existir en el repo, no solo la liga. Un enlace a un
  # PDF ausente da 404 en la laptop y nadie lo nota hasta el evento.
  test "el archivo está publicado y es un PDF de verdad" do
    ruta = Rails.root.join("public/aviso-de-privacidad.pdf")

    assert ruta.exist?, "falta public/aviso-de-privacidad.pdf"
    assert_equal "%PDF", ruta.read(4), "no es un PDF"
  end

  # El nombre no lleva versión a propósito: si la llevara, actualizar el
  # documento cambiaría la liga y habría que tocar la vista cada vez.
  test "el nombre del archivo no lleva versión" do
    assert_no_match(/v\d/, "aviso-de-privacidad.pdf")
    assert_empty Dir.glob(Rails.root.join("public/*viso*")).grep(/v\d|\s/),
                 "el archivo publicado no debe llevar versión ni espacios en el nombre"
  end
end
