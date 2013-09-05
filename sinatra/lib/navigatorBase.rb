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
			status = "invalid params"
		else
			case jason_input["situation"]
			when "NAVI_MENU"
				status, body = navi_menu(jason_input)
			when "EXTERNAL_INPUT"
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

	def start(jason_input)
#		status = nil
		body = []
		begin
			session_id = jason_input["session_id"]
			# Navigation$B$KI,MW$J%U%!%$%k$r:n@.(B
			result = system("mkdir -p records/#{session_id}")
			result = system("touch records/#{session_id}/#{session_id}.log")
			result = system("touch records/#{session_id}/#{session_id}_recipe.xml")
			open("records/#{session_id}/temp.xml", "w"){|io|
				io.puts(jason_input["operation_contents"])
			}
			result = system("cat records/#{session_id}/temp.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			result = system("rm records/#{session_id}/temp.xml")
			unless result
				p "Permission denied."
				p "Cannot make directory or files."
				return "internal error", body
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

	def finish(jason_input)
		status = nil
		body = []
		begin
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
			body, @hash_mode, status = cancel(jason_input["session_id"], @hash_recipe, @hash_mode)
			if status == "internal error"
				# $BMzNr(B
				logger()
				return status, body
			elsif status == "invalid params"
				# $BMzNr(B
				logger()
				return status, body
			end
			### ChannelSwitch$B!'ITMW(B
			### NaviDraw$B!'ITMW(B


			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
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
		return status, body
	end

	def play_control(jason_input)
#		status = nil
		body = []
		begin
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
					# $BMzNr(B
					logger()
					return "invalid params", body
				end
			else
				# $BMzNr(B
				logger()
				return "invalid params", body
			end

			### DetailDraw$B!'ITMW(B
			### Play$B!'ITMW(B
			### Notify$B!'ITMW(B
			### Cancel$B!'ITMW(B
			### ChannelSwitch$B!'ITMW(B
			### NaviDraw$B!'ITMW(B

			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
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
end
