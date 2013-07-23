$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/functions.rb'

class DefaultNavigator

	def counsel(jason_input)
		orders = []
		# generate orders along to jason_input
		if jason_input["situation"] == nil or jason_input["situation"] == "" then
			orders = [{}]
		else
			case jason_input["situation"]
			when "NAVI_MENU"
				orders = navi_menu(jason_input)
			when "EXTERNAL_INPUT"
				orders = external_input(jason_input)
			when "CHANNEL"
				orders = channel(jason_input)
			when "CHECK"
				orders = check(jason_input)
			when "START"
				orders = start(jason_input)
			when "END"
				orders = finish(jason_input)
			else
				orders = [{}]
			end
		end
		return orders
	end
end
