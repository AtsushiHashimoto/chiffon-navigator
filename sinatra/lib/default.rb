$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/functions.rb'

class DefaultNavigator

	def initialize
		@hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
	end

	def counsel(jason_input)
		status = nil
		body = []
		orders = {}
		# jason_inputに従ってordersを生成する
		if jason_input["situation"] == nil || jason_input["situation"] == ""
			status = "invalid params"
		else
			case jason_input["situation"]
			when "NAVI_MENU"
				status, body = navi_menu(jason_input, @hash_recipe)
			when "EXTERNAL_INPUT"
				status, body = external_input(jason_input, @hash_recipe)
			when "CHANNEL"
				status, body = channel(jason_input, @hash_recipe)
			when "CHECK"
				status, body = check(jason_input, @hash_recipe)
			when "START"
				status, body, @hash_recipe = start(jason_input, @hash_recipe)
			when "END"
				status, body = finish(jason_input, @hash_recipe)
			when "PLAY_CONTROL"
				status, body = play_control(jason_input, @hash_recipe)
			else
				status = "invalid params"
			end
		end

		if status == "internal error" || status == "invalid params"
			orders = {"status"=>status}
		elsif status == "success"
			orders = {"status"=>status, "body"=>body}
		else
			orders = {"status"=>"internal error"}
		end

		return orders
	end
end
