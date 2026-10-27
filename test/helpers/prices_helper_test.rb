require "test_helper"

class PricesHelperTest < ActionView::TestCase
  test "dice hacia dónde se mueven los precios, con concordancia" do
    assert_equal "2,900 suben · 406 bajan", price_directions_label(up: 2900, down: 406)
    assert_equal "1 sube · 1 baja", price_directions_label(up: 1, down: 1)
    assert_equal "3 suben", price_directions_label(up: 3, down: 0), "sin el lado en cero"
    assert_equal "Ninguno", price_directions_label(up: 0, down: 0)
  end

  test "el aviso de borradores dice a quién avisarle, hasta tres, y qué hacer" do
    draft = ->(name, client, locked = 0) { PriceList::Review::StaleDraft.new(capturista: name, client:, items: 1, locked:, estimate: false) }

    assert_equal "Hay 1 pedido en borrador con partidas al precio anterior: ANA (Ferretería Inti). " \
                 "No cambian solas: pide a cada capturista que las quite y las agregue otra vez.",
                 stale_drafts_sentence([ draft.("ANA", "Ferretería Inti") ])

    sentence = stale_drafts_sentence([ draft.("A", "1"), draft.("B", "2", 1), draft.("C", "3"), draft.("D", "4"), draft.("E", "5") ])
    assert_match(/\AHay 5 pedidos en borrador con partidas al precio anterior: A \(1\), B \(2\), C \(3\) y 2 más\./, sentence)
    assert_match(/las que tienen promoción aplicada, después de quitar la promoción\.\z/, sentence)
  end

  # Con una cotización en la lista el encabezado ya no puede decir "pedido", y
  # la cotización se nombra en su paréntesis (genérica: "Cliente genérico").
  test "el aviso nombra a las cotizaciones y no las llama pedidos" do
    sale     = PriceList::Review::StaleDraft.new(capturista: "ANA", client: "Ferretería", items: 1, locked: 0, estimate: false)
    estimate = PriceList::Review::StaleDraft.new(capturista: "LUIS", client: "Cliente genérico", items: 1, locked: 0, estimate: true)

    assert_match(/\AHay 2 borradores con partidas al precio anterior: ANA \(Ferretería\) y LUIS \(cotización, Cliente genérico\)\./,
                 stale_drafts_sentence([ sale, estimate ]))
    assert_match(/\AHay 1 borrador con partidas/, stale_drafts_sentence([ estimate ]))
  end

  test "desglosa los motivos: los dos más frecuentes y el resto como N más" do
    assert_equal "17 sin precio · 3 fuera de la rueda",
                 rejected_kinds_label([ [ :no_price, 17 ], [ :not_in_round, 3 ] ])
    assert_equal "2 códigos inválidos · 1 repetido con otro precio · 4 más",
                 rejected_kinds_label([ [ :invalid_code, 2 ], [ :conflict, 1 ], [ :generic, 3 ], [ :no_price, 1 ] ])
    assert_equal "1 fuera de catálogo (999999)", rejected_kinds_label([ [ :generic, 1 ] ])
    assert_equal "Ninguno", rejected_kinds_label([])
  end
end
