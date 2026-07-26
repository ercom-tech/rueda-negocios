class SessionsController < ApplicationController
  layout "auth"

  skip_before_action :require_login, only: %i[new create]

  def new
    redirect_to(root_path) if logged_in?
  end

  def create
    user = User.find_by(username: params[:username].to_s.strip)

    if user&.active? && user.authenticate(params[:password].to_s)
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
