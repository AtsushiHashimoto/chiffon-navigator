require 'sinatra/base'
require './app/app.rb'
require './wizard_of_oz/app.rb'

class Application < Sinatra::Base
  use ChiffonNavigator
  use WOZ

  # 404 Error!
  not_found do
    status 404
    haml :error404
  end
end

Application.run!
