# Cambiar precios desde un archivo (2026-10-08), en el panel del servidor.
#
# Tres pasos: subir → revisar (no escribe nada) → aplicar. El precio cargado
# reemplaza al crédito mayoreo del ERP solo en esta laptop y solo para la rueda
# activa; las partidas ya agregadas conservan el suyo. Ver PriceList::Review.
class PricesController < ApplicationController
  layout "auth"

  # Grupos de la revisión, en el orden de las tarjetas. "changes" (lo que se
  # va a aplicar) es la vista por omisión, como el Total del reporte.
  REVIEW_GROUPS = %w[large rejected unchanged changes].freeze
  DEFAULT_GROUP = "changes".freeze

  before_action :require_server
  before_action :require_active_round
  # Aplicar y quitar escriben precios que el sync-down está a punto de usar.
  # Revisar no escribe nada, pero compara contra un catálogo que el sync-down
  # puede estar a medio reponer: también espera.
  before_action :pause_writes_during_sync, only: %i[review apply destroy]

  def index
    respond_to do |format|
      format.html { load_summary }
      format.csv do
        send_data PriceList::LoadedExport.csv, type: "text/csv; charset=utf-8",
                  filename: "precios-cargados-#{Date.current.iso8601}.csv"
      end
    end
  end

  # Subir: se lee de una vez para rechazar aquí un archivo inservible, y se
  # guarda para que la revisión y "Aplicar" lo vuelvan a leer.
  def review
    file = params[:file]
    unless file.respond_to?(:original_filename)
      return redirect_to server_prices_path, alert: "Elige el archivo de precios que quieres revisar."
    end

    upload = PriceList::Upload.store(file)
    begin
      upload.read
    rescue PriceList::Error => e
      upload.delete
      return redirect_to server_prices_path, alert: e.message
    end
    redirect_to server_price_review_path(upload.token)
  end

  # La revisión con la gramática del reporte de pedidos capturados: tarjetas que
  # son también el filtro (`group`) y UNA tabla paginada con el grupo elegido.
  def show_review
    @upload = find_upload or return
    @review = PriceList::Review.new(@upload.read)

    respond_to do |format|
      format.html do
        @group = REVIEW_GROUPS.include?(params[:group]) ? params[:group] : DEFAULT_GROUP
        rows = review_rows(@group)
        @page_sizes = ReportsController::PAGE_SIZES
        @pagy = Pagy.new(count: rows.size, page: ParamSanitizing.page(params[:page]), limit: page_size)
        @rows = rows[@pagy.offset, @pagy.limit] || []
      end
      format.csv do
        send_data PriceList::ReviewExport.csv(@review), type: "text/csv; charset=utf-8",
                  filename: "revision-#{File.basename(@upload.filename, '.*')}.csv"
      end
    end
  rescue PriceList::Error => e
    redirect_to server_prices_path, alert: e.message
  rescue Pagy::OverflowError
    # Una página que ya no existe (marcador viejo): a la primera del mismo
    # grupo, rearmada con lo ya saneado y no con los parámetros crudos.
    redirect_to server_price_review_path(@upload.token, group: @group, per_page: page_size)
  end

  # Se vuelve a leer y a revisar el archivo: se aplica contra el catálogo de
  # AHORA, no contra el de cuando se revisó.
  def apply
    upload = find_upload or return
    review = PriceList::Review.new(upload.read)
    applied = review.apply!(filename: upload.filename, loaded_by: current_user.username)
    drafts = review.drafts_with_old_price
    upload.delete

    redirect_to server_prices_path, notice: applied_message(applied, drafts)
  rescue PriceList::Error => e
    redirect_to server_prices_path, alert: e.message
  end

  # Quitar TODOS los precios cargados de la rueda: se vuelve a capturar con los
  # del ERP. Las partidas ya agregadas conservan su precio.
  def destroy
    removed = PriceOverride.for_active_round.delete_all
    redirect_to server_prices_path,
                notice: "Se #{removed == 1 ? 'quitó 1 precio cargado' : "quitaron #{removed.to_fs(:delimited)} precios cargados"}. " \
                        "Desde ahora se captura con los precios del ERP."
  end

  private

  # Lo que la pantalla muestra: cuántos precios vigentes vienen de cada archivo.
  def load_summary
    @loaded = PriceOverride.for_active_round
    @files = @loaded.group(:source_filename)
                    .order(Arel.sql("MAX(updated_at) DESC"))
                    .pluck(:source_filename, Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"),
                           Arel.sql("STRING_AGG(DISTINCT loaded_by, ', ')"))
  end

  def review_rows(group)
    case group
    when "large" then @review.large_variations
    when "rejected" then @review.rejected
    when "unchanged" then @review.unchanged
    else @review.changes
    end
  end

  def page_size
    size = params[:per_page].to_i
    ReportsController::PAGE_SIZES.include?(size) ? size : ReportsController::PAGE_SIZES.first
  end

  def require_active_round
    return if BusinessRound.active.exists?

    redirect_to root_path, alert: "Primero obtén la información de la rueda. Los precios se cambian sobre su catálogo."
  end

  def find_upload
    upload = PriceList::Upload.find(params[:token])
    return upload if upload

    redirect_to server_prices_path, alert: "Esa revisión ya no está disponible. Vuelve a subir el archivo."
    nil
  end

  def applied_message(applied, drafts)
    text = if applied.zero?
             "No había precios que cambiar: todos los del archivo ya eran los vigentes."
    else
             "Se #{applied == 1 ? 'cambió 1 precio' : "cambiaron #{applied.to_fs(:delimited)} precios"}. " \
             "Las partidas nuevas se capturan con el precio nuevo."
    end
    return text if drafts.zero?

    text + " #{drafts == 1 ? 'Hay 1 pedido en borrador' : "Hay #{drafts} pedidos en borrador"} con partidas " \
           "al precio anterior: si deben llevar el nuevo, quita la partida y agrégala otra vez."
  end
end
