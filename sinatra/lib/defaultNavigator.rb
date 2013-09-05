#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/ordersmaker.rb'
require 'lib/modeUpdater.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase
	def navi_menu(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# mode$B$N=$@5(B
			status, @hash_mode = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw$B!'F~NO$5$l$?(Bstep$B$r(BCURRENT$B$H$7$FDs<((B
			parts, @hash_mode = maker.detailDraw()
			body.concat(parts)
			# Play$B!'ITMW!%%/%j%C%/$5$l$?(Bstep$B$ND4M}9TF0$r;O$a$l$P!$(BEXTERNAL_INPUT$B$G:F@8$5$l$k(B
			# Notify$B!'ITMW!%%/%j%C%/$5$l$?(Bstep$B$ND4M}9TF0$r;O$a$l$P!$(BEXTERNAL_INPUT$B$G:F@8$5$l$k(B
			# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
			parts, @hash_mode = maker.cancel()
			body.concat(parts)
			# ChannelSwitch$B!'ITMW(B
			# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
			parts, @hash_mode = maker.naviDraw()
			body.concat(parts)

			# $BMzNr%U%!%$%k$r=q$-9~$`(B
			logger()
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
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
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# mode$B$N=$@5(B
			status, @hash_mode = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw$B!'D4M}<T$,$H$C$?$b$N$K9g$o$;$?(Bsubstep$B$N(Bid$B$rDs<((B
			parts, @hash_mode = maker.detailDraw()
			body.concat(parts)
			# Play$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
			parts, @hash_mode = maker.play(jason_input["time"]["sec"])
			body.concat(parts)
			# Notify$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
			parts, @hash_mode = maker.notify(jason_input["time"]["sec"])
			body.concat(parts)
			# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
			parts, @hash_mode = maker.cancel()
			body.concat(parts)
			# ChannelSwitch$B!'ITMW(B
			# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
			parts, @hash_mode = maker.naviDraw()
			body.concat(parts)

			# $BMzNr%U%!%$%k$r=q$-9~$`(B
			logger()
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def channel(jason_input)
#		status = nil
		body = []
		begin
			if @hash_mode["display"] == jason_input["operation_contents"]
				p "#{@hash_mode["display"]} is displayed now. You try to display same one."
				# $BMzNr(B
				logger()
				return "invalid params", body
			end

			case jason_input["operation_contents"]
			when "GUIDE"
				# notification$B$,:F@8:Q$_$+%A%'%C%/!%(B
				@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				# $B%A%c%s%M%k$N@Z$jBX$((B
				@hash_mode["display"] = jason_input["operation_contents"]

				# DetailDraw$B!'(BmodeUpdate$B$7$J$$$N$G!$:G6aAw$C$?%*!<%@!<$HF1$8(BDetailDraw$B$rAw$k$3$H$K$J$k!%(B
				parts = detailDraw(@hash_mode)
				body.concat(parts)
				# Play$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
				parts, @hash_mode = play(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				body.concat(parts)
				# Notify$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
				parts, @hash_mode = notify(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				body.concat(parts)
				# Cancel$B!'ITMW!%:F@8BT$A%3%s%F%s%D$OB8:_$7$J$$!%(B
				# ChannelSwitch$B!'(BGUIDE$B$r;XDj(B
				body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
				# NaviDraw$B!'D>6a$N%J%S2hLL$HF1$8$b$N$rJV$9$3$H$K$J$k!%(B
				parts = naviDraw(@hash_recipe, @hash_mode)
				body.concat(parts)
			when "MATERIALS", "OVERVIEW"
				# mode$B$N=$@5(B
				media = ["audio", "video"]
				media.each{|v|
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "CURRENT"
							@hash_mode[v]["mode"][key][0] = "STOP"
						end
					}
				}
				# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&!%(B
				@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				# $B%A%c%s%M%k$N@Z$jBX$((B
				@hash_mode["display"] = jason_input["operation_contents"]

				# DetailDraw$B!'ITMW!%(BDetail$B$OIA2h$5$l$J$$(B
				# Play$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Notify$B!'ITMW!%:F@8%3%s%F%s%D$OB8:_$7$J$$(B
				# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
				parts, @hash_mode, status = cancel(@hash_recipe, @hash_mode)
				body.concat(parts)
				# ChannelSwitch$B!'(BMATERIALS$B$r;XDj(B
				body.push({"ChannelSwitch"=>{"channel"=>"#{jason_input["operation_contents"]}"}})
				# NaviDraw$B!'ITMW!%(BNavi$B$OIA2h$5$l$J$$(B
			else
				# $BMzNr(B
				logger()
				return "invalid params", body
			end
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			# $BMzNr(B
			logger()
			return "internal error", body
		end
		# $BMzNr(B
		logger()
		return "success", body
	end

	def check(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# element_name$B$N3NG'(B
			id = jason_input["operation_contents"]
			if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
				# mode$B$N=$@5(B
				status, @hash_mode = maker.modeUpdate_check(jason_input["time"]["sec"], id)
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				parts, @hash_mode = maker.detailDraw()
				body.concat(parts)
				# Play$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				parts, @hash_mode = maker.play(jason_input["time"]["sec"])
				body.concat(parts)
				# Notify$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				parts, @hash_mode = maker.notify(jason_input["time"]["sec"])
				body.concat(parts)
				# Cancel$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
				parts, @hash_mode = maker.cancel()
				body.concat(parts)
				# ChannelSwitch$B!'ITMW!%(B
				# NaviDraw$B!'%A%'%C%/$5$l$?$b$N$r(Bis_fisnished$B$K=q$-BX$(!$(Bvisual$B$rE,@Z$K=q$-49$($?$b$N$rDs<((B
				parts, @hash_mode = maker.naviDraw()
				body.concat(parts)

				# $BMzNr%U%!%$%k$r=q$-9~$`(B
				logger()
				session_id = jason_input["session_id"]
				open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
					io.puts(JSON.pretty_generate(@hash_mode))
				}
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
