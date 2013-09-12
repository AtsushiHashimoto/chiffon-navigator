#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/xmlParser.rb'
require 'lib/utils.rb'

class NavigatorBase
	def initialize
		@hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		@hash_mode = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
	end

	def counsel(jason_input)
		status = nil
		body = []
		orders = {}

		if jason_input["situation"] == nil || jason_input["situation"] == ""
			p "#####test2"
			p "invalid params : jason_input['situation'] is wrong."
			logger()
			status = "invalid params"
		else
			case jason_input["situation"]
			when "NAVI_MENU"
				status, body = navi_menu(jason_input)
			when "EXTERNAL_INPUT"
				p "#####test4"
				status, body = external_input(jason_input)
			when "CHANNEL"
				status, body = channel(jason_input)
			when "CHECK"
				status, body = check(jason_input)
			when "START"
				status, body = start(jason_input)
			when "END"
				status, body = finish(jason_input)
			when "PLAY_CONTROL"
				status, body = play_control(jason_input)
			else
				p "#####test10"
				p "invalid params : jason_input['situation'] is wrong."
				logger()
				status = "invalid params"
			end
		end

		if status == "internal error"
			p "#####test11"
			p body.class
			p body.message
			p body.backtrace
			logger()
			orders = {"status"=>status}
		elsif status == "internal error in 'system'"
			p "Cannot make some directory and files"
			logger()
			return {"status"=>"internal error"}
		elsif status == "invalid params"
			p "#####test12"
			orders = {"status"=>status}
		elsif status == "success"
			logger()
			orders = {"status"=>status, "body"=>body}
		else
			p "#####test14"
			p "internal error"
			p "navigatorBase.rb: parameter 'status' is wrong."
			logger()
			orders = {"status"=>"internal error"}
		end
		return orders
	rescue => e
		p "#####test15"
		p e.class
		p e.message
		p e.backtrace
		logger()
		return {"status"=>"internal error"}
	end

	private

	######################################################
	##### situation$B$K9g$o$;$FF0:n$9$k(B7$B%a%=%C%I$NFb!$(B #####
	##### $BF0:n$,7h$^$C$F$$$k(B5$B%a%=%C%I(B                #####
	######################################################

	def channel(jason_input)
		body = []
		if @hash_mode["display"] == jason_input["operation_contents"]
			p "invalid params : #{@hash_mode["display"]} is displayed now. You try to display same one."
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
			parts = detailDraw
			body.concat(parts)
			# Play$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
			parts = play(jason_input["time"]["sec"])
			body.concat(parts)
			# Notify$B!'(BSTART$B$+$i(Boverview$B$r7P$F(Bguide$B$K0\$k>l9g!$%a%G%#%"$N:F@8$,I,MW$+$b$7$l$J$$!%(B
			parts = notify(jason_input["time"]["sec"])
			body.concat(parts)
			# Cancel$B!'ITMW!%:F@8BT$A%3%s%F%s%D$OB8:_$7$J$$!%(B
			# ChannelSwitch$B!'(BGUIDE$B$r;XDj(B
			body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
			# NaviDraw$B!'D>6a$N%J%S2hLL$HF1$8$b$N$rJV$9$3$H$K$J$k!%(B
			parts = naviDraw
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
			parts = cancel()
			body.concat(parts)
			# ChannelSwitch$B!'(BMATERIALS$B$r;XDj(B
			body.push({"ChannelSwitch"=>{"channel"=>"#{jason_input["operation_contents"]}"}})
			# NaviDraw$B!'ITMW!%(BNavi$B$OIA2h$5$l$J$$(B
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHANNEL."
			return "invalid params", body
		end

		return "success", body
	rescue => e
		return "internal error", e
	end

	def check(jason_input)
		body = []
		unless @hash_mode["display"] == "GUIDE"
			p "invalid params : #{@hash_mode["display"]} is displayed now."
			logger()
			return "invalid params", body
		end

		id = jason_input["operation_contents"]
		# element_name$B$N3NG'(B
		if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
			# mode$B$N=$@5(B
			modeUpdate_check(jason_input["time"]["sec"], id)
			# DetailDraw$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
			body.concat(detailDraw())
			# Play$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
			body.concat(play(jason_input["time"]["sec"]))
			# Notify$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
			body.concat(notify(jason_input["time"]["sec"]))
			# Cancel$B!'JL$N(Bsubstep$B$KA+0\$9$k$+$b$7$l$J$$$N$GI,MW!%(B
			body.concat(cancel())
			# ChannelSwitch$B!'ITMW!%(B
			# NaviDraw$B!'%A%'%C%/$5$l$?$b$N$r(Bis_fisnished$B$K=q$-BX$(!$(Bvisual$B$rE,@Z$K=q$-49$($?$b$N$rDs<((B
			body.concat(naviDraw())
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHECK."
			logger()
			return "invalid params", body
		end

		return "success", body
	rescue => e
		return "internal error", e
	end

	def start(jason_input)
		body = []
		session_id = jason_input["session_id"]
		# Navigation$B$KI,MW$J%U%!%$%k$r:n@.(B
		unless system("mkdir -p records/#{session_id}")
			return "internal error in 'system'", body
		end
		unless system("touch records/#{session_id}/#{session_id}.log")
			return "internal error in 'system'", body
		end
		unless system("touch records/#{session_id}/#{session_id}_recipe.xml")
			return "internal error in 'system'", body
		end
		open("records/#{session_id}/temp.xml", "w"){|io|
			io.puts(jason_input["operation_contents"])
		}
		unless system("cat records/#{session_id}/temp.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			return "internal error in 'system'", body
		end
		unless system("rm records/#{session_id}/temp.xml")
			return "internal error in 'system'", body
		end

		# recipe.xml$B$r%Q!<%9$7!$(Bhash_recipe$B$K3JG<$9$k(B
		@hash_recipe = parse_xml("records/#{session_id}/#{session_id}_recipe.xml")

		# step$B$d(Bmedia$B$N4IM}$r$9$k(Bhahs_mode$B$N:n@.(B
		if @hash_recipe.key?("step")
			@hash_recipe["step"].each{|key, value|
				@hash_mode["step"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			}
		end
		if @hash_recipe.key?("substep")
			@hash_recipe["substep"].each{|key, value|
				@hash_mode["substep"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			}
		end
		if @hash_recipe.key?("audio")
			@hash_recipe["audio"].each{|key, value|
				@hash_mode["audio"]["mode"][key] = ["NOT_YET", -1]
			}
		end
		if @hash_recipe.key?("video")
			@hash_recipe["video"].each{|key, value|
				@hash_mode["video"]["mode"][key] = ["NOT_YET", -1]
			}
		end
		if @hash_recipe.key?("notification")
			@hash_recipe["notification"].each{|key, value|
				@hash_mode["notification"]["mode"][key] = ["NOT_YET", -1]
			}
		end
		# $BI=<($5$l$F$$$k2hLL$N4IM}$N$?$a$K!J(BSTART$B;~$O(BOVERVIEW$B!K(B
		@hash_mode["display"] = "OVERVIEW"

		# hahs_mode$B$K$*$1$k3FMWAG$N=i4|@_Dj(B
		# $BM%@hEY$N:G$b9b$$(Bstep$B$r(BCURRENT$B$H$7!$$=$N0lHVL\$N(Bsubstep$B$b(BCURRENT$B$K$9$k!%(B
		current_step = @hash_recipe["sorted_step"][0][1]
		current_substep = @hash_recipe["step"][current_step]["substep"][0]
		@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
		@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
		# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K$9$k!%(B
		@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
		# START$B$J$N$G!$(Bis_finished$B$J$b$N$O$J$$!%(B
		# CURRENT$B$H$J$C$?(Bsubstep$B$,(BABLE$B$J$i$P%a%G%#%"$N:F@8=`Hw$H$7$F(BCURRENT$B$K$9$k!%(B
		if @hash_mode["substep"]["mode"][current_substep][0] == "ABLE"
			media = ["audio", "video", "notification"]
			media.each{|v|
				if @hash_recipe["substep"][current_substep].key?(v)
					@hash_recipe["substep"][current_substep][v].each{|media_id|
						@hash_mode[v]["mode"][media_id][0] = "CURRENT"
					}
				end
			}
		end

		### DetailDraw$B!'ITMW(B
		### Play$B!'ITMW(B
		### Notify$B!'ITMW(B
		### Cancel$B!'ITMW(B
		### ChannelSwitch$B!'(BOVERVIEW$B$r;XDj(B
		body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
		### NaviDraw$B!'ITMW(B

		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		open("records/#{session_id}/#{session_id}_recipe.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_recipe))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	def finish(jason_input)
		body = []
		# media$B$r(BSTOP$B$K$9$k!%(B
		session_id = jason_input["session_id"]
		media = ["audio", "video", "notification"]
		media.each{|v|
			@hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT"
					@hash_mode[v]["mode"][key][0] = "STOP"
				end
			}
		}

		### DetailDraw$B!'ITMW(B
		### Play$B!'ITMW(B
		### Notify$B!'ITMW(B
		### Cancel$B!':F@8BT$A%3%s%F%s%D$,B8:_$9$l$P%-%c%s%;%k(B
		body = cancel
		### ChannelSwitch$B!'ITMW(B
		### NaviDraw$B!'ITMW(B

		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	def play_control(jason_input)
		body = []
		id = jason_input["operation_contents"]["id"]
		if @hash_recipe["audio"].key?(id) || @hash_recipe["video"].key?(id)
			case jason_input["operation_contents"]["operation"]
			when "PLAY"
			when "PAUSE"
			when "JUMP"
			when "TO_THE_END"
			when "FULL_SCREEN"
			when "MUTE"
			when "VOLUME"
			else
				p "invalid params : jason_input['operation_contents']['operation'] is wrong when situation is PLAY_CONTROL."
				logger()
				return "invalid params", body
			end
		else
			p "invalid params : jason_input['operation_contents']['id'] is wrong when situation is PLAY_CONTROL."
			logger()
			return "invalid params", body
		end

		### DetailDraw$B!'ITMW(B
		### Play$B!'ITMW(B
		### Notify$B!'ITMW(B
		### Cancel$B!'ITMW(B
		### ChannelSwitch$B!'ITMW(B
		### NaviDraw$B!'ITMW(B

#		session_id = jason_input["session_id"]
#		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
#			io.puts(JSON.pretty_generate(@hash_mode))
#		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	#####################################
	##### $B3FL?Na$r@8@.$9$k(B5$B%a%=%C%I(B #####
	#####################################

	# CURRENT$B$J(Bsubstep$B$N(Bhtml_contents$B$rI=<($5$;$k(BDetailDraw$BL?Na!%(B
	def detailDraw
		orders = []
		@hash_mode["substep"]["mode"].each{|key, value|
			if value[2] == "CURRENT"
				orders.push({"DetailDraw"=>{"id"=>key}})
				break
			end
		}
		return orders
	end

	# CURRENT$B$J(Baudio$B$H(Bvideo$B$r:F@8$5$;$k(BPlay$BL?Na!%(B
	def play(time)
		orders = []
		media = ["audio", "video"]
		media.each{|v|
			@hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT"
					# trigger$B$N?t$,(B1$B8D0J>e$N$H$-!%(B
					if @hash_recipe[v][key].key?("trigger")
						# trigger$B$,J#?t8D$N>l9g!$$I$&$9$k$N$+9M$($F$$$J$$!%(B
						orders.push({"Play"=>{"id"=>key, "delay"=>@hash_recipe[v][key]["trigger"][0][2].to_i}})
						finish_time = time + @hash_recipe[v][key]["trigger"][0][2].to_i * 1000
						@hash_mode[v]["mode"][key][1] = finish_time
					else # trigger$B$,(B0$B8D$N$H$-!%(B
						# trigger$B$,L5$$>l9g$O:F@8L?Na$O=P$5$J$$$,!$(Bhash_mode$B$O$I$&JQ99$9$k$N$+9M$($F$$$J$$!%(B
						# @hash_mode[v]["mode"][key][1] = ?
						return []
					end
				end
			}
		}
		return orders
	end

	# CURRENT$B$J(Bnotification$B$r:F@8$5$;$k(BNotify$BL?Na!%(B
	def notify(time)
		orders = []
		@hash_mode["notification"]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# notification$B$O(Btrigger$B$,I,$:$"$k!%(B
				# trigger$B$,J#?t8D$N>l9g!$$I$&$9$k$N$+9M$($F$$$J$$!%(B
				orders.push({"Notify"=>{"id"=>key, "delay"=>@hash_recipe["notification"][key]["trigger"][0][2].to_i}})
				finish_time = time + @hash_recipe["notification"][key]["trigger"][0][2].to_i * 1000
				# notification$B$OFC<l$J$N$G!$FCJL$K(BKEEP$B$KJQ99$9$k!%(B
				@hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
			end
		}
		return orders
	end

	# $B:F@8BT$A>uBV$N(Baudio$B!$(Bvideo$B!$(Bnotification$B$rCf;_$9$k(BCancel$BL?Na!%(B
	def cancel(*id)
		orders = []
		# $BFC$KCf;_$5$;$k%a%G%#%"$K$D$$$F;XDj$,L5$$>l9g(B
		if id == []
			# audio$B$H(Bvideo$B$N=hM}!%(B
			# Cancel$B$5$;$k$Y$-$b$N$O!$(BSTOP$B$K$J$C$F$$$k$O$:!%(B
			media = ["audio", "video"]
			media.each{|v|
				if @hash_mode.key?(v)
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOP$B$+$i(BFINISHED$B$KJQ99!%(B
							@hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notification$B$N=hM}!%(B
			# Cancel$B$5$;$k$Y$-$b$N$O!$(BSTOP$B$N$J$C$F$$$k$O$:!%(B
			if @hash_mode.key?("notification")
				@hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOP$B$+$i(BFINISHED$B$KJQ99!%(B
						@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audio$B$r$b$D(Bnotification$B$N>l9g!$(Baudio$B$b(BFINISHED$B$KJQ99!%(B
						if @hash_recipe["notification"][key].key?("audio")
							audio_id = @hash_recipe["notification"][key]["audio"]
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # $BCf;_$5$;$k%a%G%#%"$K$D$$$F;XDj$,$"$k>l9g!%(B
			id.each{|v|
				# $B;XDj$5$l$?%a%G%#%"$N(Belement name$B$rD4::!%(B
				element_name = search_ElementName(@hash_recipe, v)
				# audio$B$H(Bvideo$B$N>l9g!%(B
				if @hash_recipe["audio"].key?(v) || @hash_recipe["video"].key?(v)
					# $B;XDj$5$l$?$b$N$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!$(B
					if @hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif @hash_recipe["notification"].key?(v) # notification$B$N>l9g!%(B
					# $B;XDj$5$l$?(Bnotification$B$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!%(B
					if @hash_mode["notification"]["mode"][v][0] == "KEEP"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audio$B$r;}$D(Bnotification$B$O(Baudio$B$b(BFINISHED$B$K!%(B
						if @hash_recipe["notification"][v].key?("audio")
							audio_id = @hash_recipe["notification"][v]["audio"]
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				end
			}
		end
		return orders
	end

	# $B%J%S2hLL$NI=<($r7hDj$9$k(BNaviDraw$BL?Na!%(B
	def naviDraw
		# sorted_step$B$N=g$KI=<($5$;$k!%(B
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			id = v[1]
			visual = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual = "CURRENT"
			else
				visual = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
			end
			# CURRENT$B$J(Bstep$B$N>l9g!$(Bsubstep$B$bI=<($5$;$k!%(B
			if visual == "CURRENT"
				@hash_recipe["step"][id]["substep"].each{|id|
					visual = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual = "CURRENT"
					else
						visual = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
					end
				}
			end
		}
		return orders
	end

	##############################################################
	##### mode$B$N(Bupdate$B=hM}$,J#;($J(BCHECK$B%a%=%C%I$N(BmodeUpdater #####
	##############################################################

	def modeUpdate_check(time, id)
		# $B%A%'%C%/$5$l$?$b$N$K$h$C$F>l9gJ,$1!%(B
		# $B>e0L%a%=%C%I$GH=Dj$7$F$$$k$N$G!$(Bid$B$H$7$F(Bstep$B$^$?$O(Bsubstep$B0J30$,F~NO$5$l$k$3$H$O$J$$!%(B
		if @hash_recipe["step"].key?(id)
			# is_finished$B$^$?$O(BNOT_YET$B$NA`:n!%(B
			if @hash_mode["step"]["mode"][id][1] == "NOT_YET" # NOT_YET$B$J$i(Bis_finished$B$K!%(B
				# $B%A%'%C%/$5$l$?(Bstep$B$r(Bis_finished$B$K!%(B
				@hash_mode["step"]["mode"][id][1] = "is_finished"
				# $B%A%'%C%/$5$l$?(Bstep$B$K4^$^$l$k(Bsubstep$B$rA4$F(Bis_finished$B$K!%(B
				@hash_recipe["step"][id]["substep"].each{|substep_id|
					@hash_mode["substep"]["mode"][substep_id][1] = "is_finished"
					# substep$B$K4^$^$l$k%a%G%#%"$r(BFINISHED$B$K$9$k!%(B
					# $B$b$7$b8=>u$G(BCURRENT$B$^$?$O(BKEEP$B$@$C$?$i!$:F@8BT$A$^$?$O:F@8Cf$J$N$G(BSTOP$B$K$9$k!%(B
					media = ["audio", "video", "notification"]
					media.each{|v|
						if @hash_recipe["substep"][substep_id].key?(v)
							@hash_recipe["substep"][substep_id][v].each{|media_id|
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						end
					}
				}
				#
				# $BK\Ev$O!$%A%'%C%/$5$l$?(Bstep$B$,(Bparent$B$K;}$D(Bstep$B$b(Bis_finished$B$K$7$J$1$l$P$J$i$J$$!%(B
				#
			else # is_finished$B$J$i(BNOT_YET$B$K!%(B
				# $B%A%'%C%/$5$l$?(Bstep$B$r(BNOT_YET$B$K!%(B
				@hash_mode["step"]["mode"][id][1] = "NOT_YET"
				# $B%A%'%C%/$5$l$?(Bstep$B$K4^$^$l$k(Bsubstep$B$rA4$F(BNOT_YET$B$K!%(B
				@hash_recipe["step"][id]["substep"].each{|substep_id|
					@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
					# substep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K$9$k!%(B
					media = ["audio", "video", "notification"]
					media.each{|v|
						if @hash_recipe["substep"][substep_id].key?(v)
							@hash_recipe["substep"][substep_id][v].each{|media_id|
								@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
							}
						end
					}
				}
				#
				# $BK\Ev$O!$%A%'%C%/$5$l$?(Bstep$B$r(Bparent$B$K;}$D(Bstep$B$b(BNOT_YET$B$K$7$J$1$l$P$J$i$J$$!%(B
				#
			end
		elsif @hash_recipe["substep"].key?(id)
			# is_finished$B$^$?$O(BNOT_YET$B$NA`:n!%(B
			if @hash_mode["substep"]["mode"][id][1] == "NOT_YET" # NOT_YET$B$J$i$P(Bis_finished$B$K!%(B
				parent_step = @hash_recipe["substep"][id]["parent_step"]
				media = ["audio", "video", "notification"]
				# $B%A%'%C%/$5$l$?(Bsubstep$B$r4^$a$=$l0JA0$N(Bsubstep$BA4$F$r(Bis_finished$B$K!%(B
				@hash_recipe["step"][parent_step]["substep"].each{|child_substep|
					@hash_mode["substep"]["mode"][child_substep][1] = "is_finished"
					# $B$=$N(Bsubstep$B$K4^$^$l$k%a%G%#%"$r(BFINISHED$B$K!%(B
					# $B$b$7$b8=>u$G(BCURRENT$B$^$?$O(BKEEP$B$J$i$P!$:F@8Cf$^$?$O:F@8BT$A$J$N$G(BSTOP$B$K!%(B
					media.each{|v|
						if @hash_recipe["substep"][child_substep].key?(v)
							@hash_recipe["substep"][child_substep][v].each{|media_id|
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						end
					}
					# $B%A%'%C%/$5$l$?(Bsubstep$B$r(Bis_finished$B$K$7$?$i%k!<%W=*N;!%(B
					if child_substep == id
						# $B%A%'%C%/$5$l$?(Bsubstep$B$,(Bstep$BFb$N:G=*(Bsubstep$B$J$i$P!$?F%N!<%I$b(Bis_finished$B$K$9$k!%(B
						if @hash_recipe["step"][parent_step]["substep"].last == id
							@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
						end
						break
					end
				}
				#
				# $B$+$D!$(Bis_finished$B$H$J$C$?(Bstep$B$,(Bparent$B$K$b$D(Bstep$B$b(Bis_finished$B$K$7$J$1$l$P$J$i$J$$(B
				#
			else # is_finished$B$J$i$P(BNOT_YET$B$K!%(B
				parent_step = @hash_recipe["substep"][id]["parent_step"]
				media = ["audio", "video", "notification"]
				# $B%A%'%C%/$5$l$?(Bsubstep$B$r4^$`$=$l0J9_$N!JF10l(Bstep$BFb$N!K(Bsubstep$B$r(BNOT_YET$B$K!%(B
				flag = -1
				@hash_recipe["step"][parent_step]["substep"].each{|child_substep|
					if flag == 1 || child_substep == id
						flag = 1
						@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
						# $B$=$N(Bsubstep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K!%(B
						media.each{|v|
							if @hash_recipe["substep"][child_substep].key?(v)
								@hash_recipe["substep"][child_substep][v].each{|media_id|
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							end
						}
					end
				}
				# $B?F%N!<%I$N(Bstep$B$rL@<(E*$K(BNOT_YET$B$K$9$k!%(B
				@hash_mode["step"]["mode"][parent_step][1] = "NOT_YET"
				#
				# $B$+$D!$(BNOT_YET$B$H$J$C$?(Bstep$B$r(Bparent$B$K$b$D(Bstep$B$b(BNOT_YET$B$K$7$J$1$l$P$J$i$J$$(B
				#
			end
		end
		# ABLE$B$^$?$O(BOTHERS$B$NA`:n$N$?$a$K!$(BCURRENT$B$J(Bstep$B$H(Bsubstep$B$N(Bid$B$rD4$Y$k!%(B
		current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
		# ABLE$B$^$?$O(BOTHERS$B$NA`:n!%(B
		@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
		# $BA4$F(Bis_finished$B$J$i$P(BCURRENT$BC5:w$O$7$J$$(B
		flag = -1
		@hash_mode["step"]["mode"].each{|key, value|
			if value[1] == "NOT_YET"
				flag = 1
				break
			end
		}
		if flag == 1 # NOT_YET$B$J(Bstep$B$,B8:_$9$k>l9g$N$_!$(BCURRENT$B$N0\F0$r9T$&(B
			# $B2DG=$J(Bsubstep$B$KA+0\$9$k(B
			@hash_mode = go2current(@hash_recipe, @hash_mode, current_step, current_substep)
			# $B:FEY(BABLE$B$NH=Dj$r9T$&(B
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			# ABLE$B$^$?$O(BOTHERS$B$NA`:n!%(B
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
		end
		# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&!%(B
		@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
	end
end
