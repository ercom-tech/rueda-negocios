require "test_helper"

module PriceList
  class UploadTest < ActiveSupport::TestCase
    setup { @dir = Dir.mktmpdir }
    teardown do
      FileUtils.remove_entry(@dir)
      FileUtils.rm_rf(Upload::ROOT)
    end

    def uploaded(name)
      path = File.join(@dir, "x").tap { |p| File.write(p, "CODIGO,PRECIO LISTA S/IVA\n1,2\n") }
      Rack::Test::UploadedFile.new(path, "text/csv", original_filename: name)
    end

    test "guarda el archivo con su nombre y lo encuentra por su ficha" do
      stored = Upload.store(uploaded("Lista Stihl.csv"))

      found = Upload.find(stored.token)
      assert_equal "Lista Stihl.csv", found.filename
      assert_equal "CODIGO,PRECIO LISTA S/IVA\n1,2\n", File.read(found.path)

      found.delete
      assert_nil Upload.find(stored.token)
    end

    # La ruta del navegador no deja pasar "..", pero la ficha también se
    # valida aquí: con ella se arma una ruta en disco.
    test "una ficha sin forma de ficha no se busca en disco" do
      Upload.store(uploaded("a.csv"))

      [ "..", "*", "../price_lists", "", nil ].each { |token| assert_nil Upload.find(token), token.inspect }
    end

    test "del nombre original se queda solo el nombre, sin ruta" do
      assert_equal "precios.csv", Upload.store(uploaded("../../etc/precios.csv")).filename
      assert_equal "lista_stihl_.csv", Upload.store(uploaded("lista*stihl?.csv")).filename
    end

    test "barre lo que se subió hace más de un día y nunca se aplicó" do
      old = Upload.store(uploaded("viejo.csv"))
      FileUtils.touch(Upload::ROOT.join(old.token), mtime: 2.days.ago.to_time)
      recent = Upload.store(uploaded("nuevo.csv"))

      assert_nil Upload.find(old.token)
      assert Upload.find(recent.token)
    end
  end
end
