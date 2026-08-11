class LoginEvent < ApplicationRecord
  # Un intento de inicio de sesión (exitoso o fallido). `username` guarda lo
  # tecleado aunque el usuario no exista; `user` puede quedar nulo si el
  # sync-down lo eliminó después (la FK anula, el evento permanece). Los
  # fallidos son la materia prima del throttling de la fase de strengthening.
  belongs_to :user, optional: true

  validates :username, presence: true
  validates :success, inclusion: { in: [ true, false ] }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :failed, -> { where(success: false) }
end
