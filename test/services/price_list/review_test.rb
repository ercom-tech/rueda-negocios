require "test_helper"

module PriceList
  class ReviewTest < ActiveSupport::TestCase
    setup do
      @round = BusinessRound.create!(erp_round_id: 9501, name: "Rueda PL", active: true)
      @saw   = product(3021, "MOTOSIERRA", 6500)
      @blower = product(3022, "SOPLADORA", 1000)
    end

    def product(code, description, price)
      Product.create!(erp_product_id: code, description: description).tap do |p|
        Price.create!(product: p, credit_wholesale_price: price, tax_rate: 16)
      end
    end

    # Un Reader de mentira: las pruebas del archivo viven en ReaderTest.
    def reader(rows, problems: [])
      lines = rows.each_with_index.map { |(code, price), i| Reader::Row.new(line: i + 2, code:, price: BigDecimal(price.to_s)) }
      Struct.new(:rows, :problems).new(lines, problems)
    end

    def review(rows, **) = Review.new(reader(rows, **))

    test "separa lo que cambia, lo que queda igual y lo que no está en la rueda" do
      result = review([ [ 3021, 6900 ], [ 3022, 1000 ], [ 9999, 50 ] ])

      assert_equal [ [ 3021, 6500, 6900 ] ], result.changes.map { |c| [ c.code, c.current_price, c.new_price ] }
      assert_equal [ 3022 ], result.unchanged.map(&:code)
      assert_equal [ 9999 ], result.not_in_round.map(&:code)
      assert_equal "MOTOSIERRA", result.changes.sole.description
    end

    test "compara contra el precio con que hoy se captura, no contra el del ERP" do
      PriceOverride.create!(erp_round_id: 9501, erp_product_id: 3021, unit_price: 6900)

      result = review([ [ 3021, 6900 ], [ 3022, 1100 ] ])

      assert_equal [ 3021 ], result.unchanged.map(&:code), "6900 ya es el precio cargado"
      assert_equal [ [ 3022, 1000 ] ], result.changes.map { |c| [ c.code, c.current_price ] }
    end

    test "un código repetido con el mismo precio cuenta una vez" do
      assert_equal [ 3021 ], review([ [ 3021, 6900 ], [ 3021, 6900 ] ]).changes.map(&:code)
    end

    test "un código repetido con precios distintos no se aplica y se reporta" do
      result = review([ [ 3021, 6900 ], [ 3022, 1100 ], [ 3021, 7000 ] ])

      assert_equal [ 3022 ], result.changes.map(&:code)
      conflict = result.conflicts.sole
      assert_equal [ 3021, [ 2, 4 ], [ 6900, 7000 ] ], [ conflict.code, conflict.lines, conflict.prices ]
    end

    test "el 999999 se rechaza aunque esté en el catálogo" do
      product(Product::GENERIC_ERP_ID, "AJUSTE DE MERCANCIA", 0)

      result = review([ [ Product::GENERIC_ERP_ID, 50 ] ])

      assert_empty result.changes
      assert_match(/se captura a mano/, result.problems.sole.reason)
    end

    test "conserva los problemas del archivo, en orden de línea" do
      problems = [ Reader::Problem.new(line: 9, code_text: "1", reason: "b", kind: :no_price),
                   Reader::Problem.new(line: 3, code_text: "2", reason: "a", kind: :no_price) ]

      assert_equal [ 3, 9 ], review([], problems:).problems.map(&:line)
    end

    test "lo que no se aplica va junto, en orden de archivo y con su motivo" do
      problems = [ Reader::Problem.new(line: 6, code_text: "ABC", reason: "El código no es válido: deben ser hasta 6 dígitos.",
                                      kind: :invalid_code) ]
      result = review([ [ 9999, 5 ], [ 3021, 6900 ], [ 3021, 7000 ] ], problems:)

      assert_equal [ [ 2, "009999", "No está en el catálogo de esta rueda." ],
                     [ 3, "003021", "Viene repetido con precios distintos (líneas 3 y 4)." ],
                     [ 6, "ABC", "El código no es válido: deben ser hasta 6 dígitos." ] ],
                   result.rejected.map { |r| [ r.line, r.code_text, r.reason ] }
    end

    test "señala las variaciones de más de 50% en cualquier dirección" do
      product(3023, "ORILLADORA", 1000)
      product(3024, "HACHA", 1000)
      result = review([ [ 3021, 6500 * 1.5 + 1 ], [ 3022, 499 ], [ 3023, 1500 ], [ 3024, 500 ] ])

      assert_equal [ 3021, 3022 ], result.large_variations.map(&:code), "exactamente 50% no se señala"
    end

    test "cuenta cuántos suben y cuántos bajan" do
      product(3023, "ORILLADORA", 0)
      result = review([ [ 3021, 6900 ], [ 3022, 900 ], [ 3023, 50 ] ])

      assert_equal({ up: 2, down: 1 }, result.directions(result.changes), "el que no tenía precio sube")
    end

    test "desglosa lo que no se aplica por tipo, del más frecuente al menos" do
      problems = [ Reader::Problem.new(line: 2, code_text: "1", reason: "x", kind: :invalid_code),
                   Reader::Problem.new(line: 3, code_text: "2", reason: "x", kind: :no_price),
                   Reader::Problem.new(line: 4, code_text: "3", reason: "x", kind: :no_price) ]
      result = review([ [ 9999, 5 ], [ 9998, 5 ], [ 9997, 5 ] ], problems:)

      assert_equal [ [ :not_in_round, 3 ], [ :no_price, 2 ], [ :invalid_code, 1 ] ], result.rejected_kinds
    end

    test "el umbral de variación lo elige quien revisa" do
      result = Review.new(reader([ [ 3021, 6500 * 1.15 ], [ 3022, 1300 ] ]), threshold: BigDecimal("0.2"))

      assert_equal [ 3022 ], result.large_variations.map(&:code), "15% no pasa de 20; 30% sí"
      assert result.large?(result.changes.find { |c| c.code == 3022 })
      assert_equal 2, result.changes.size, "el umbral solo señala: se aplican todos"
    end

    test "un producto sin precio no tiene variación que señalar" do
      product(3023, "ORILLADORA", 0)

      change = review([ [ 3023, 100 ] ]).changes.sole
      assert_nil change.variation
      assert_not change.large_variation?
    end

    test "sin rueda activa no hay contra qué revisar" do
      @round.update!(active: false)

      error = assert_raises(Error) { review([ [ 3021, 6900 ] ]) }
      assert_match(/No hay una rueda cargada/, error.message)
    end

    test "cuenta los borradores con partidas a un precio distinto del nuevo" do
      user   = User.create!(erp_person_id: 9501, username: "cap_pl", password: "x", role: "capturista")
      client = Client.create!(erp_client_key: "PL01", name: "Cliente")
      draft = ->(status: "draft") { Order.create!(user:, business_round: @round, client:, kind: "remission", status:) }
      item  = ->(order, product, price) { order.order_items.create!(product.to_order_item_attributes.merge(quantity: 1, unit_price: price)) }

      item.(draft.(), @saw, 6500)                                 # precio viejo: cuenta
      d2 = draft.()
      item.(d2, @saw, 6500)
      item.(d2, @blower, 1000)                                    # el mismo pedido cuenta una vez
      item.(draft.(), @saw, 6900)                                 # ya al precio nuevo: no cuenta
      item.(draft.(), @blower, 1000)                              # producto que no cambia
      item.(draft.(status: "captured").tap { _1.update_column(:local_folio, "RN-1") }, @saw, 6500) # no es borrador

      assert_equal 2, review([ [ 3021, 6900 ] ]).drafts_with_old_price
    end

    # --- apply! -----------------------------------------------------------

    test "aplica solo lo que cambia, con el archivo y quién lo cargó" do
      result = review([ [ 3021, 6900 ], [ 3022, 1000 ], [ 9999, 5 ] ])

      assert_equal 1, result.apply!(filename: "stihl.xlsx", loaded_by: "servidor")

      override = PriceOverride.sole
      assert_equal [ 9501, 3021, 6900, "stihl.xlsx", "servidor" ],
                   [ override.erp_round_id, override.erp_product_id, override.unit_price, override.source_filename, override.loaded_by ]
      assert_equal 6900, @saw.reload.capture_price
    end

    # Decisión del usuario (2026-10-08): un archivo nuevo solo toca sus
    # códigos, y en uno repetido gana el último.
    test "los archivos se suman: el segundo no borra al primero" do
      review([ [ 3021, 6900 ] ]).apply!(filename: "stihl.xlsx", loaded_by: "a")
      review([ [ 3022, 1100 ] ]).apply!(filename: "otro.xlsx", loaded_by: "a")

      assert_equal 6900, @saw.reload.capture_price
      assert_equal 1100, @blower.reload.capture_price
    end

    test "en un código ya cargado gana el último archivo" do
      review([ [ 3021, 6900 ] ]).apply!(filename: "lunes.xlsx", loaded_by: "a")
      first = PriceOverride.sole
      travel 1.minute do
        review([ [ 3021, 7100 ] ]).apply!(filename: "martes.xlsx", loaded_by: "b")
      end

      override = PriceOverride.sole
      assert_equal [ 7100, "martes.xlsx", "b" ], [ override.unit_price, override.source_filename, override.loaded_by ]
      assert_operator override.updated_at, :>, first.updated_at, "updated_at dice cuándo se cambió"
      assert_equal first.created_at, override.created_at
    end

    test "no aplica mientras corre un sync" do
      result = review([ [ 3021, 6900 ] ])
      SyncRun.create!(kind: "down", status: "running", started_at: Time.current, pid: Process.pid)

      error = assert_raises(Error) { result.apply!(filename: "x.xlsx", loaded_by: "a") }
      assert_match(/Espera a que termine para cambiar precios/, error.message)
      assert_equal 0, PriceOverride.count
    end

    test "no aplica si la rueda cambió desde la revisión" do
      result = review([ [ 3021, 6900 ] ])
      @round.update!(active: false)
      BusinessRound.create!(erp_round_id: 9502, name: "Otra", active: true)

      error = assert_raises(Error) { result.apply!(filename: "x.xlsx", loaded_by: "a") }
      assert_match(/La rueda cambió/, error.message)
      assert_equal 0, PriceOverride.count
    end

    test "sin cambios no escribe nada" do
      assert_equal 0, review([ [ 3022, 1000 ] ]).apply!(filename: "x.xlsx", loaded_by: "a")
      assert_equal 0, PriceOverride.count
    end
  end
end
