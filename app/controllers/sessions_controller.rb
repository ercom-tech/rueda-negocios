class SessionsController < ApplicationController
  layout "auth"

  skip_before_action :require_login, only: %i[new create]
  # Los guards de sesión no aplican aquí: login/logout deben funcionar
  # siempre (y el logout de una sesión ya desplazada no debe chocar).
  skip_before_action :require_round_for_capturista
  skip_before_action :require_current_session

  # Compartido con el guard de sesión (require_round_for_capturista).
  def self.no_round_message
    "No hay rueda en curso en esta laptop. " \
      "El equipo servidor debe cargar la información primero."
  end

  def new
    redirect_to(root_path) if logged_in?
  end

  def create
    username = params[:username].to_s.strip
    user     = User.find_by(username: username)

    if user&.active? && authenticates?(user, params[:password].to_s)
      # Sin rueda cargada un capturista no tiene nada que operar: se bloquea
      # en la puerta. El rol server sí entra siempre — es quien la carga.
      if !user.can_see_all_orders? && BusinessRound.active.none?
        log_attempt(user, username, success: false)
        flash.now[:alert] = SessionsController.no_round_message
        return render :new, status: :unprocessable_entity
      end

      log_attempt(user, username, success: true)
      reset_session # evita session fixation
      # Sesión única: el token nuevo invalida cualquier sesión anterior del
      # mismo usuario en otro equipo (el último login gana).
      user.regenerate_session_token
      session[:user_id]       = user.id
      session[:session_token] = user.session_token
      redirect_to root_path, notice: "Hola, #{user.full_name.presence || user.username}."
    else
      log_attempt(user, username, success: false)
      flash.now[:alert] = "Usuario o contraseña incorrectos."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Sesión cerrada."
  end

  private

  # El digest viene del ERP por el sync (`cnf_persona_has_metodoidentifica`), y
  # el import solo descarta los VACÍOS. Un hash con otro formato —md5, texto
  # plano, un valor migrado— hace que `BCrypt::Password` reviente, y el
  # capturista recibe un error del sistema en vez de "usuario o contraseña
  # incorrectos", en bucle y sin que nadie sepa por qué. Un digest ilegible es
  # una credencial que no sirve: se trata como inválida.
  def authenticates?(user, password)
    user.authenticate(password)
  rescue BCrypt::Errors::InvalidHash
    Rails.logger.warn("[login] #{user.username} tiene un digest ilegible en la BD local")
    false
  end

  # Auditoría: un renglón por intento de login, exitoso o no. `success: false`
  # cubre credenciales malas, usuario inactivo/inexistente y capturista sin
  # rueda — "no se abrió sesión".
  def log_attempt(user, username, success:)
    LoginEvent.create!(user: user, username: username, success: success,
                       ip: request.remote_ip, user_agent: request.user_agent)
  end
end
