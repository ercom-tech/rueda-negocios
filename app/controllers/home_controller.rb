class HomeController < ApplicationController
  def index
    @active_round = BusinessRound.active.first
  end
end
