class SessionsController < ApplicationController
  layout "auth"

  skip_before_action :require_login, only: %i[new create]
  # El guard de rueda no aplica aquí: login/logout deben funcionar siempre
  # (y el logout de un capturista tras cerrarse la rueda no debe chocar).
  skip_before_action :require_round_for_capturista

  # Compartido con el guard de sesión (require_round_for_capturista).
  def self.no_round_message
    "No hay rueda en curso en esta laptop. " \
      "El equipo servidor debe cargar la información primero."
  end

  def new
    redirect_to(root_path) if logged_in?
  end

  def create
    user = User.find_by(username: params[:username].to_s.strip)

    if user&.active? && user.authenticate(params[:password].to_s)
      # Sin rueda cargada un capturista no tiene nada que operar: se bloquea
      # en la puerta. El rol server sí entra siempre — es quien la carga.
      if !user.can_see_all_orders? && BusinessRound.active.none?
        flash.now[:alert] = SessionsController.no_round_message
        return render :new, status: :unprocessable_entity
      end

      reset_session # evita session fixation
      session[:user_id] = user.id
      redirect_to root_path, notice: "Hola, #{user.full_name.presence || user.username}."
    else
      flash.now[:alert] = "Usuario o contraseña incorrectos."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Sesión cerrada."
  end
end
