#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase

	private

	########################################################
	##### situation$B$K9g$o$;$FF0:n$9$k(B7$B%a%=%C%I$NFb!$(B   #####
	##### navigator$B$N;EMM$K9g$o$;$FJQ99$9$Y$-(B3$B%a%=%C%I(B #####
	########################################################

	def navi_menu(jason_input)
		body = []
		unless @hash_mode["display"] == "GUIDE"
			p "invalid params : #{@hash_mode["display"]} is displayed now."
			logger()
			return "invalid params", body
		end

		id = jason_input["operation_contents"]
		unless @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
			p "invalid params : jason_input['operation_contents'] is wrong when situation is NAVI_MENU."
			logger()
			return "invalid params", body
		end
		# mode$B$N=$@5(B
		modeUpdate_navimenu(jason_input["time"]["sec"], id)

		# DetailDraw$B!'F~NO$5$l$?(Bstep$B$r(BCURRENT$B$H$7$FDs<((B
		body.concat(detailDraw())
		# Play$B!'ITMW!%(B
		# Notify$B!'ITMW!%(B
		# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
		body.concat(cancel())
		# ChannelSwitch$B!'ITMW(B
		# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
		body.concat(naviDraw())

		session_id = jason_input["session_id"]
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	def external_input(jason_input)
		body = []
		# mode$B$N=$@5(B
		modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])

		# DetailDraw$B!'D4M}<T$,$H$C$?$b$N$K9g$o$;$?(Bsubstep$B$N(Bid$B$rDs<((B
		body.concat(detailDraw())
		# Play$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
		body.concat(play(jason_input["time"]["sec"]))
		# Notify$B!'(Bsubstep$BFb$K%3%s%F%s%D$,B8:_$9$l$P:F@8L?Na$rAw$k(B
		body.concat(notify(jason_input["time"]["sec"]))
		# Cancel$B!':F@8BT$A%3%s%F%s%D$,$"$l$P%-%c%s%;%k(B
		body.concat(cancel())
		# ChannelSwitch$B!'ITMW(B
		# NaviDraw$B!'E,@Z$K(Bvisual$B$r=q$-49$($?$b$N$rDs<((B
		body.concat(naviDraw())

		session_id = jason_input["session_id"]
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	##########################################################
	##### mode$B$N(Bupdate$B=hM}$,J#;($J(B2$B%a%=%C%I$N(BmodeUpdater #####
	##########################################################

	def modeUpdate_navimenu(time, id)
		# $B8=>u$G(BCURRENT$B$J(Bstep$B!$(Bsubstep$B$K4X$7$F$O2?$N=hM}$b$7$J$$(B
		# clicked_with_NAVI_MENU$B$O(BCURRENT$B!$(BNOT_CURRENT$B$HF1$8>l=j$G4IM}$9$k(B
		if @hash_recipe["step"].key?(id)
			# $B%/%j%C%/$5$l$?(Bstep$B$,(Bclicked_with_NAVI_MENU$B$J$i$P(BNOT_CURRENT$B$KLa$9!%(B
			if @hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
				@hash_mode["step"]["mode"][id][2] = "NOT_CURRENT"
			else # $B%/%j%C%/$5$l$?(Bstep$B$,(BNOT_CURRENT$B$J$i$P(Bclicked_with_NAVI_MENU$B$K$9$k(B
				@hash_mode["step"]["mode"][id][2] = "clicked_with_NAVI_MENU"
			end
		elsif @hash_recipe["substep"].key?(id)
			# $B%/%j%C%/$5$l$?(Bsubstep$B$r(Bclicked_with_NAVI_MENU$B$K$9$k(B
			@hash_mode["substep"]["mode"][id][2] = "clicked_with_NAVI_MENU"
			# substep$B$,%/%j%C%/$5$l$?>l9g$N$_!$(BdetailDraw$B$,JQ2=$9$k$N$G!$F02h$H2;@<$rDd;_$9$k!%(B
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					# substep$B$K4^$^$l$k(Baudio$B!$(Bvideo$B$O:F@8:Q$_!&:F@8Cf!&:F@8BT$A4X$o$i$:(BSTOP$B$K!%(B
					media = ["audio", "video"]
					media.each{|v|
						@hash_mode[v]["mode"].each{|key, value|
							if value[0] == "CURRENT"
								@hash_mode[v]["mode"][key][0] = "STOP"
							end
						}
					}
					break
				end
			}
		end
	end

	# EXTERNAL_INPUT$B%j%/%(%9%H$N>l9g$N(Bmode$B%"%C%W%G!<%H(B
	def modeUpdate_externalinput(time, id)
		# $BM%@hEY=g$K!$F~NO$5$l$?%*%V%8%'%/%H$r%H%j%,!<$H$9$k(Bsubstep$B$rC5:w!%(B
		current_substep = nil
		@hash_recipe["sorted_step"].each{|v|
			flag = -1
			# ABLE$B$J(Bstep$B$NCf$N(BNOT_YET$B$J(Bsubstep$B$+$iC5:w!%!J8=>u$G(BCURRENT$B$J(Bsubstep$B$bC5:wBP>]!%0lC6%*%V%8%'%/%H$rCV$$$F$^$?$d$j;O$a$?$@$1$+$b$7$l$J$$!%!K(B
			if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
						if @hash_recipe["substep"][substep_id].key?("trigger")
							@hash_recipe["substep"][substep_id]["trigger"].each{|v|
								if v[1] == id
									current_substep = node2.parent.attributes.get_attribute("id").value
									flag = 1
									break # trigger$BC5:w$+$i$N(Bbreak
								end
							}
						end
					end
					if flag == 1
						break # substep$BC5:w$+$i$N(Bbreak
					end
				}
			elsif @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" && @hash_mode["step"]["mode"][v[1]][2] == "CURRENT" # ABLE$B$G$J$/$F$b!$(Bnavi_menu$BEy$G(BCURRENT$B$J(Bstep$B$bC5:wBP>](B
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
						if @hash_recipe["substep"][substep_id].key?("trigger")
							@hash_recipe["substep"][substep_id]["trigger"].each{|v|
								if v[1] == id
									current_substep = substep_id
									flag = 1
									break
								end
							}
						end
					end
					if flag == 1
						break
					end
				}
			end
			if flag == 1
				break # step$BC5:w$+$i$N(Bbreak
			end
		}
		previous_substep = nil
		if current_substep == nil
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					break
				end
			}
			if @hash_mode["substep"]["mode"][previous_substep][0] == "ABLE"
				if @hash_recipe["substep"][previous_substep].key?("next_substep")
					current_substep = @hash_recipe["substep"][previous_substep]["next_substep"]
				else
					parent_id = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_recipe["sorted_step"].each{|v|
						if v[1] != parent_id && @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
							@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
								if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
									current_substep = substep_id
									break
								end
							}
							break
						end
					}
				end
			else
				@hash_recipe["sorted_step"].each{|v|
					if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
						@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
			end
		end
		if current_substep == nil
			previous_substep = nil
			parent_step = nil
			# $BA4$F$N(Bsubstep$B$,=*N;2<$H9M$($i$l$k!%(B
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					@hash_mode["substep"]["mode"][previous_substep][1] = "is_finished"
					parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
					break
				end
			}
			media = ["audio", "video", "notification"]
			media.each{|v|
				if @hash_recipe["substep"][previous_substep].key?(v)
					@hash_recipe["substep"][previous_substep][v].each{|media_id|
						if @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
							@hash_mode[v]["mode"][media_id][0] = "STOP"
						end
					}
				end
			}
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, parent_step, previous_substep)

		else
			# $B8=>u$G(BCURRENT$B$J(Bsubstep$B$r(BNOT_CURRENT$B$+$D(Bis_finished$B$K!%(B
			previous_substep = nil
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					if previous_substep != current_substep
						@hash_mode["substep"]["mode"][previous_substep][2] = "NOT_CURRENT"
						@hash_mode["substep"]["mode"][previous_substep][1] = "is_finished"
						# $B;R$N;~E@$G$O%a%G%#%"$O(BSTOP$B$7$J$$!%(B
						# $B?F%N!<%I$b(BNOT_CURRENT$B$K$9$k!%$+$D!$>e5-$N(Bsubstep$B$,(Bstep$BFb$G:G8e$N(Bsubstep$B$G$"$l$P!$(Bstep$B$r(Bis_finished$B$K$9$k!%(B
						parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
						@hash_mode["step"]["mode"][parent_step][2] = "NOT_CURRENT"
						unless @hash_recipe["substep"][previous_substep].key?("next_substep")
							@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
						end
					end
					break
				end
			}
			# $B<!$K(BCURRENT$B$H$J$k(Bsubstep$B$r(BCURRENT$B$K!%(B
			@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
			current_step = @hash_recipe["substep"][current_substep]["parent_step"]
			@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
			# $B8=>u$G(BCURRENT$B$J(Bsubstep$B$H<!$K(BCURRENT$B$J(Bsubstep$B$,0[$J$k>l9g$O!$%a%G%#%"$r:F@8$5$;$k!%(B
			if current_substep != previous_substep
				media = ["audio", "video", "notification"]
				media.each{|v|
					if @hash_recipe["substep"][current_substep].key?(v)
						@hash_recipe["substep"][current_substep][v].each{|media_id|
							if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
								@hash_mode[v]["mode"][media_id][0] = "CURRENT"
							end
						}
					end
				}
				# previous_substep$B$N%a%G%#%"$O(BSTOP$B$9$k!%(B
				media = ["audio", "video"]
				media.each{|v|
					if @hash_recipe["substep"][previous_substep].key?(v)
						@hash_recipe["substep"][previous_substep][v].each{|media_id|
							@hash_mode[v]["mode"][media_id][0] = "STOP"
						}
					end
				}
			end
			# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K!%(B
			p current_step
			p current_substep
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&(B
			@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
		end
	end

	#################################################################
	##### NAVI_MENU$BMQ$NFCJL$J(BdetailDraw$B5Z$S(BnaviDraw$B$r:FDj5A$9$k(B #####
	#################################################################

	# clicked_with_NAVI_MENU$B$^$?$O(BCURRENT$B$J(Bsubstep$B$N(Bhtml_contents$B$rI=<($5$;$k(BDetailDraw$BL?Na!%(B
	# clicked_with_NAVI_MENU$B$NJ}$,M%@hEY$O9b$$(B
	# clicked_with_NAVI_MENU$B$O0lEY=hM}$9$k$H(BNOT_CURRENT$B$KLa$k(B
	def detailDraw
		orders = []
		@hash_mode["substep"]["mode"].each{|key, value|
			if value[2] == "CURRENT"
				orders = [{"DetailDraw"=>{"id"=>key}}]
			end
			if value[2] == "clicked_with_NAVI_MENU"
				orders = [{"DetailDraw"=>{"id"=>key}}]
				@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
				break
			end
		}
		return orders
	end

		# $B%J%S2hLL$NI=<($r7hDj$9$k(BNaviDraw$BL?Na!%(B
	def naviDraw
		# sorted_step$B$N=g$KI=<($5$;$k!%(B
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			id = v[1]
			visual_step = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual_step = "CURRENT"
			else
				visual_step = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>0})
			end
			# CURRENT$B$J(Bstep$B$N>l9g!$(Bsubstep$B$bI=<($5$;$k!%(B
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				@hash_recipe["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual_substep = "CURRENT"
					else
						visual_substep = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>0})
					end
				}
			elsif @hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
				# NAVI_MENU$B$GA*Br$5$l$?$b$N$b!$(Bsubstep$B$rI=<($5$;$k!%(B
				@hash_recipe["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual_substep = "CURRENT"
					else
						visual_substep = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>0})
					end
				}
			end
		}
		return orders
	end

end
