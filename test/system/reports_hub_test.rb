require "application_system_test_case"

# El hub de reportes con cinco tarjetas (desde las cotizaciones, 2026-10-27).
# En cinco columnas la tarjeta crece con su contenido y el rótulo quedaba
# donde vive el badge "Próximamente": "Reporte de [Próximamente]", con la
# segunda línea tapada 12 px (15ª auditoría). Solo se ve midiendo.
class ReportsHubTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(erp_person_id: 970_601, username: "cap_hub", password: "secret123",
                         role: "capturista", active: true)
    round = BusinessRound.create!(erp_round_id: 970_601, name: "Rueda hub", active: true)
    BusinessRoundPerson.create!(business_round: round, user: @user, position: 1,
                                supplier: Supplier.create!(erp_supplier_id: 970_601, name: "PROV HUB"))
  end

  test "el badge Próximamente no tapa el rótulo de su tarjeta" do
    sign_in @user
    [ [ 1024, 768 ], [ 1400, 900 ] ].each do |width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height,
                                      deviceScaleFactor: 1, mobile: false)
      visit reports_path

      overlaps = evaluate_script(<<~JS)
        [...document.querySelectorAll("[aria-disabled=true]")].map(card =>
          card.querySelector("span.text-xl").getBoundingClientRect().bottom -
          card.querySelector("span.absolute").getBoundingClientRect().top)
      JS
      assert_equal 2, overlaps.size
      overlaps.each { |px| assert_operator px, :<=, 0, "a #{width} px el badge tapa #{px.round} px del rótulo" }
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
