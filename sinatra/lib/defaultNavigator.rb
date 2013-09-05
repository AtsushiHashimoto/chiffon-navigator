#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/ordersmaker.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase
	def navi_menu(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# mode$B$N=$@5(B
			status = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw$B!'F~NO$5$l$?(Bstep$B$r(BCURRENT$B$H$7$FDs<((B
			body.concat(maker.detailDraw())
			# Play$B!'ITMW!%%/%j%C%/$5$l$?(Bstep$B$ND4M}9TF0$r;O$a$l$P!$(BEXTERNAL_INPUT$B$G:F@8$5$l$k(B
			# Notify$B!'ITMW!%%/%j%C%/$5$l$?(Bstep$B$ND4M}9TF0$r;O$a$l$P!$(BEXTERNAL_INPUT$B$G:F@8$5$l$k(B
			# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
			body.concat(maker.cancel())
			# ChannelSwitch$B!'ITMW(B
			# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
			body.concat(maker.naviDraw())

			# $BMzNr%U%!%$%k$r=q$-9~$`(B
			logger()
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def external_input(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# mode$B$N=$@5(B
			status = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw$B!'D4M}<T$,$H$C$?$b$N$K9g$o$;$?(Bsubstep$B$N(Bid$B$rDs<((B
			body.concat(maker.detailDraw)
			# Play$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
			body.concat(maker.play(jason_input["time"]["sec"]))
			# Notify$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
			body.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
			body.concat(maker.cancel())
			# ChannelSwitch$B!'ITMW(B
			# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
			body.concat(maker.naviDraw())

			# $BMzNr%U%!%$%k$r=q$-9~$`(B
			logger()
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def channel(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)

			case jason_input["operation_contents"]
			when "GUIDE"
				# mode$B$N=$@5(B
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "GUIDE")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw$B!'(BmodeUpdate$B$7$J$$$N$G!$:G6aAw$C$?%*!<%@!<$HF1$8(BDetailDraw$B$rAw$k$3$H$K$J$k!%(B
				body.concat(maker.detailDraw())
				# Play$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
				body.concat(maker.play(jason_input["time"]["sec"]))
				# Notify$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
				body.concat(maker.notify(jason_input["time"]["sec"]))
				# Cancel$B!'ITMW!%:F@8BT$A%3%s%F%s%D$OB8:_$7$J$$!%(B
				# ChannelSwitch$B!'(BGUIDE$B$r;XDj(B
				body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
				# NaviDraw$B!'D>6a$N%J%S2hLL$HF1$8$b$N$rJV$9$3$H$K$J$k!%(B
				body.concat(maker.naviDraw())

				# $BMzNr%U%!%$%k=q$-9~$`(B
				logger()
			when "MATERIALS"
				# mode$B$N=$@5(B
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "MATERIALS")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw$B!'ITMW!%(BDetail$B$OIA2h$5$l$J$$(B
				# Play$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Notify$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
				body.concat(maker.cancel())
				# ChannelSwitch$B!'(BMATERIALS$B$r;XDj(B
				body.push({"ChannelSwitch"=>{"channel"=>"MATERIALS"}})
				# NaviDraw$B!'ITMW!%(BNavi$B$OIA2h$5$l$J$$(B

				# $BMzNr%U%!%$%k$r=q$-9~$`(B
				logger()
			when "OVERVIEW"
				# mode$B$N99?7(B
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "OVERVIEW")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw$B!'ITMW!%(BDetail$B$OIA2h$5$l$J$$(B
				# Play$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Notify$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
				body.concat(maker.cancel())
				# ChannelSwitch$B!'(BOVERVIEW$B$r;XDj(B
				body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
				# NaviDraw$B!'ITMW!%(BNavi$B$OIA2h$5$l$J$$(B

				# $BMzNr%U%!%$%k$r=q$-9~$`(B
				logger()
			else
				# $BMzNr%U%!%$%k$K=q$-9~$`(B
				logger()
				errorLOG()
				return "invalid params", body
			end
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def check(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# element_name$B$N3NG'(B
			id = jason_input["operation_contents"]
			if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
				# mode$B$N=$@5(B
				status = maker.modeUpdate_check(jason_input["time"]["sec"], id)
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				body.concat(maker.detailDraw())
				# Play$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				body.concat(maker.play(jason_input["time"]["sec"]))
				# Notify$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				body.concat(maker.notify(jason_input["time"]["sec"]))
				# Cancel$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				body.concat(maker.cancel())
				# ChannelSwitch$B!'ITMW!%(B
				# NaviDraw$B!'%A%'%C%/$5$l$?$b$N$r(Bis_fisnished$B$K=q$-BX$(!$(Bvisual$B$rE,@Z$K=q$-49$($?$b$N$rDs<((B
				body.concat(maker.naviDraw())

				# $BMzNr%U%!%$%k$r=q$-9~$`(B
				logger()
			else
				# $BMzNr%U%!%$%k$r=q$-9~$`(B
				logger()
				errorLOG()
				return "invalid params", body
			end
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end
end
