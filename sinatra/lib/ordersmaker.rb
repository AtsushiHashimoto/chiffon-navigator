#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

class OrdersMaker
	def initialize(input)
		@session_id = input
		@hash_mode = Hash.new()
		open("records/#{@session_id}/#{@session_id}_mode.txt", "r"){|io|
			@hash_mode = JSON.load(io)
		}
		@sorted_step = []
		open("records/#{@session_id}/#{@session_id}_sortedstep.txt", "r"){|io|
			@sorted_step = JSON.load(io)
		}
		@doc = REXML::Document.new(open("records/#{@session_id}/#{@session_id}_recipe.xml"))
	end

	# CURRENT$B$J(Bsubstep$B$N(Bhtml_contents$B$rI=<($5$;$k(BDetailDraw$BL?Na!%(B
	def detailDraw
		orders = []
		@hash_mode["substep"]["mode"].each{|key, value|
			# CURREN$B$J(Bsubstep$B$O0l$D$@$1!J$N$O$:!K!%(B
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
					if @doc.elements["//#{v}[@id=\"#{key}\"]/trigger[1]"] != nil
						# trigger$B$,J#?t8D$N>l9g!$$I$&$9$k$N$+9M$($F$$$J$$!%(B
						@doc.get_elements("//#{v}[@id=\"#{key}\"]/trigger[1]").each{|node|
							orders.push({"Play"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
							finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
							@hash_mode[v]["mode"][key][1] = finish_time
						}
					else # trigger$B$,(B0$B8D$N$H$-!%(B
						# trigger$B$,L5$$>l9g$O:F@8L?Na$O=P$5$J$$$,!$(Bhash_mode$B$O$I$&JQ99$9$k$N$+9M$($F$$$J$$!%(B
						# @hash_mode[v]["mode"][key][1] = ?
						return []
					end
				end
			}
		}
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
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
				@doc.get_elements("//notification[@id=\"#{key}\"]/trigger[1]").each{|node|
					orders.push({"Notify"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
					finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
					# notification$B$OFC<l$J$N$G!$FCJL$K(BKEEP$B$KJQ99$9$k!%(B
					@hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
				}
			end
		}
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
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
						if @doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = @doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # $BCf;_$5$;$k%a%G%#%"$K$D$$$F;XDj$,$"$k>l9g!%(B
			id.each{|v|
				# $B;XDj$5$l$?%a%G%#%"$N(Belement name$B$rD4::!%(B
				element_name = searchElementName(@session_id, v)
				# audio$B$H(Bvideo$B$N>l9g!%(B
				if element_name == "audio" || element_name == "video"
					# $B;XDj$5$l$?$b$N$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!$(B
					if @hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notification$B$N>l9g!%(B
					# $B;XDj$5$l$?(Bnotification$B$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!%(B
					if @hash_mode["notification"]["mode"][v][0] == "KEEP"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audio$B$r;}$D(Bnotification$B$O(Baudio$B$b(BFINISHED$B$K!%(B
						if @doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = @doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # $B;XDj$5$l$?$b$N$,(Baudio$B!$(Bvideo$B!$(Bnotification$B$GL5$$>l9g!%(B
					return [{}]
				end
			}
		end
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return orders
	end

	# $B%J%S2hLL$NI=<($r7hDj$9$k(BNaviDraw$BL?Na!%(B
	def naviDraw
		# sorted_step$B$N=g$KI=<($5$;$k!%(B
		orders = Array.new()
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		flag = 0
		@sorted_step.each{|v|
			id = v[1]
			visual = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual = "CURRENT"
			elsif @hash_mode["step"]["mode"][id][2] == "NOT_CURRENT"
				visual = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
			end
			# CURRENT$B$J(Bstep$B$N>l9g!$(Bsubstep$B$bI=<($5$;$k!%(B
			if visual == "CURRENT"
				if flag == 1
					p "error" # CURRENT$B$J(Bstep$B$,J#?t8D$"$k>l9g!$%(%i!<$rEG$/!)9M$($F$$$J$$!%(B
				end
				@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
					id = node.attributes.get_attribute("id").value
					visual = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual = "CURRENT"
					elsif @hash_mode["substep"]["mode"][id][2] == "NOT_CURRENT"
						visual = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
					elsif @hash_mode["substep"]["mode"][id][1] == "NOT_YET"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
					end
				}
				flag = 1
			end
		}
		return orders
	end

	# NAVI_MENU$B%j%/%(%9%H$N>l9g$N(Bmode$B%"%C%W%G!<%H(B
	def modeUpdate_navimenu(time, id)
		begin
			unless @hash_mode["display"] == "GUIDE"
				p "#{@hash_mode["display"]} is displayed now."
				return "invalid_params"
			end
			element_name = searchElementName(@session_id, id)
			# $BA+0\MW5a@h$,(Bstep$B$+(Bsubstep$B$+$G>l9gJ,$1(B
			case element_name
			when "step"
				# $B$^$:$O!$(BCURRENT$B!$(BNOT_CURRENT$B$NA`:n!%(B
				# $B8=>u$G(BCURRENT$B$J(Bsubstep$B$r(BNOT_CURRENT$B$K$9$k!%(B
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
						# substep$B$K4^$^$l$k(Baudio$B!$(Bvideo$B$O:F@8:Q$_!&:F@8Cf!&:F@8BT$A4X$o$i$:(BSTOP$B$K!%(B
						media = ["audio", "video"]
						media.each{|v|
							@hash_mode[v]["mode"].each{|key, value|
								if value[0] == "CURRENT"
									@hash_mode[v]["mode"][key][0] = "STOP"
								end
							}
						}
						break # CURRENT$B$J(Bsubstep$B$O0l$D$@$1$N$O$:!%(B
					end
				}
				# $B8=>u$G(BCURRENT$B$@$C$?(Bstep$B$r(BNOT_CURRENT$B$K$9$k!%(B
				@hash_mode["step"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["step"]["mode"][key][2] = "NOT_CURRENT"
						break # CURRENT$B$J(Bstep$B$O0l$D$@$1$N$O$:!%(B
					end
				}
				# $B%/%j%C%/$5$l$?(Bstep$B$r(BCURRENT$B$K!%(B
				@hash_mode["step"]["mode"][id][2] = "CURRENT"
				# $B%/%j%C%/$5$l$?(Bstep$BFb$G(BNOT_YET$B$J(Bsubstep$B$N0lHVL\$r(BCURRENT$B$K!%(B
				# NOT_YET$B$J(Bsubstep$B$,B8:_$7$J$1$l$P!$Bh0lHVL\$N(Bsubstep$B$r(BCURRENT$B$K!%(B
				current_substep = nil
				@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
					substep_id = node.attributes.get_attribute("id").value
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
						current_substep = node.attributes.get_attribute("id").value
						break
					else
						next
					end
				}
				if current_substep != nil # NOT_YET$B$J(Bsubstep$B$,B8:_$9$k!%(B
					# $B0lHVL\$K(BNOT_YET$B$J(Bsubstep$B$r(BCURRENT$B$K!%(B
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
				else # NOT_YET$B$J(Bsubstep$B$,B8:_$7$J$$!%(B
					# $B0lHVL\$N(B(is_finished$B$J(B)substep$B$r(BCURRENT$B$K!%(B
					current_substep = @doc.elements["//step[@id=\"#{id}\"]/substep[1]"].attributes.get_attribute("id").value
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
				end
				# $B%/%j%C%/$5$l$?@h$N%a%G%#%"$O:F@8$5$;$J$$!%(B
				# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K$9$k!%(B
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, id, current_substep)
			when "substep"
				# $B$^$:$O!$(BCURRENT$B!$(BNOT_CURRENT$B$NA`:n!%(B
				# $B8=>u$G(BCURRENT$B$J(Bsubstep$B$r(BNOT_CURRENT$B$K!%(B
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
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
				# $B%/%j%C%/$5$l$?(Bsubstep$B$r(BCURRENT$B$K!%(B
				@hash_mode["substep"]["mode"][id][2] = "CURRENT"
				# CURRENT$B$J(Bstep$B$NC5:w!%(B
				current_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
				# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K$9$k!%(B
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, id)
			else # $BA+0\MW5a@h$,$*$+$7$$!%(B
				return "invalid_params"
			end
			# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&!%(B
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	# EXTERNAL_INPUT$B%j%/%(%9%H$N>l9g$N(Bmode$B%"%C%W%G!<%H(B
	def modeUpdate_externalinput(time, id)
		begin
			element_name = searchElementName(@session_id, id)
			# $BF~NO$5$l$?(Bid$B$,(Bnotification$B$N>l9g!%(B
			if element_name == "notification"
				# $B;XDj$5$l$?(Bnotification$B$,L$:F@8$J$i:F@8L?Na$HH=CG$7$F(BCURRENT$B$K!%(B
				if @hash_mode["notification"]["mode"][id][0] == "NOT_YET"
					@hash_mode["notification"]["mode"][id][0] = "CURRENT"
				elsif @hash_mode["notification"]["mode"][id][0] == "KEEP" # $B;XDj$5$l$?(Bnotification$B$,:F@8BT5!Cf$J$i(BCancel$BL?Na$HH=CG$7$F(BSTOP$B$K!%(B
					@hash_mode["notification"]["mode"][id][0] = "STOP"
				end
			else
				# $BM%@hEY=g$K!$F~NO$5$l$?%*%V%8%'%/%H$r%H%j%,!<$H$9$k(Bsubstep$B$rC5:w!%(B
				current_substep = nil
				@sorted_step.each{|v|
					flag = -1
					# ABLE$B$J(Bstep$B$NCf$N(BNOT_YET$B$J(Bsubstep$B$+$iC5:w!%!J8=>u$G(BCURRENT$B$J(Bsubstep$B$bC5:wBP>]!%0lC6%*%V%8%'%/%H$rCV$$$F$^$?$d$j;O$a$?$@$1$+$b$7$l$J$$!%!K(B
					if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
						@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node1|
							substep_id = node1.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
								@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
									if node2.attributes.get_attribute("ref").value == id
										current_substep = node2.parent.attributes.get_attribute("id").value
										flag = 1
										break # trigger$BC5:w$+$i$N(Bbreak
									end
								}
							end
							if flag == 1
								break # substep$BC5:w$+$i$N(Bbreak
							end
						}
					elsif @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" && @hash_mode["step"]["mode"][v[1]][2] == "CURRENT" # ABLE$B$G$J$/$F$b!$(Bnavi_menu$BEy$G(BCURRENT$B$J(Bstep$B$bC5:wBP>](B
						@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
								@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
									if node2.attributes.get_attribute("ref").value == id
										current_substep = node2.parent.attributes.get_attribute("id").value
										flag = 1
										break
									end
								}
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
						if @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node != nil
							current_substep = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node.attributes.get_attribute("id").value
						else
							parent_id = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].parent.attributes.get_attribute("id").value
							@sorted_step.each{|v|
								if v[1] != parent_id && @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
									@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
										substep_id = node.attributes.get_attribute("id").value
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
						@sorted_step.each{|v|
							if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
								@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
									substep_id = node.attributes.get_attribute("id").value
									if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
										previous_substep = substep_id
										break
									end
								}
								break
							end
						}
					end
				end
				if current_substep == nil
					# Do nothing
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
								parent_step = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].parent.attributes.get_attribute("id").value
								@hash_mode["step"]["mode"][parent_step][2] = "NOT_CURRENT"
								if @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node == nil
									@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
								end
							end
							break
						end
					}
					# $B<!$K(BCURRENT$B$H$J$k(Bsubstep$B$r(BCURRENT$B$K!%(B
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
					current_step = @doc.elements["//substep[@id=\"#{current_substep}\"]"].parent.attributes.get_attribute("id").value
					@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
					# $B8=>u$G(BCURRENT$B$J(Bsubstep$B$H<!$K(BCURRENT$B$J(Bsubstep$B$,0[$J$k>l9g$O!$%a%G%#%"$r:F@8$5$;$k!%(B
					if current_substep != previous_substep
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{current_substep}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "CURRENT"
								end
							}
						}
						# previous_substep$B$N%a%G%#%"$O(BSTOP$B$9$k!%(B
						media = ["audio", "video"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{previous_substep}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								@hash_mode[v]["mode"][media_id][0] = "STOP"
							}
						}
					end
					# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K!%(B
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
					# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&(B
					@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
				end
			end
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	# CHANNEL$B%j%/%(%9%H$N>l9g$N(Bmpode$B%"%C%W%G!<%H(B
	def modeUpdate_channel(time, flag)
		begin
			if @hash_mode["display"] == flag
				p "#{@hash_mode["display"]} is displayed now. You try to display same one."
				return "invalid_params"
			end
			# CURRENT$B$J(Baudio$B$H(Bvideo$B$r(BSTOP$B$9$k!%(B
			# notification$B$O(BSTOP$B$7$J$$!%(B
			if flag == "MATERIALS" || flag == "OVERVIEW"
				media = ["audio", "video"]
				media.each{|v|
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "CURRENT"
							@hash_mode[v]["mode"][key][0] = "STOP"
						end
					}
				}
			end
			# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&!%(B
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			# $B%A%c%s%M%k$N@Z$jBX$((B
			@hash_mode["display"] = flag
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	def modeUpdate_check(time, id)
		begin
			unless @hash_mode["display"] == "GUIDE"
				p "#{@hash_mode["display"]} is displayed now."
				return "invalid_params"
			end
			element_name = searchElementName(@session_id, id)
			# $B%A%'%C%/$5$l$?$b$N$K$h$C$F>l9gJ,$1!%(B
			case element_name
			when "step"
				# is_finished$B$^$?$O(BNOT_YET$B$NA`:n!%(B
				if @hash_mode["step"]["mode"][id][1] == "NOT_YET" # NOT_YET$B$J$i(Bis_finished$B$K!%(B
					# $B%A%'%C%/$5$l$?(Bstep$B$r(Bis_finished$B$K!%(B
					@hash_mode["step"]["mode"][id][1] = "is_finished"
					# $B%A%'%C%/$5$l$?(Bstep$B$K4^$^$l$k(Bsubstep$B$rA4$F(Bis_finished$B$K!%(B
					@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][substep_id][1] = "is_finished"
						# substep$B$K4^$^$l$k%a%G%#%"$r(BFINISHED$B$K$9$k!%(B
						# $B$b$7$b8=>u$G(BCURRENT$B$^$?$O(BKEEP$B$@$C$?$i!$:F@8BT$A$^$?$O:F@8Cf$J$N$G(BSTOP$B$K$9$k!%(B
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						}
					}
					#
					#
					# $BK\Ev$O!$%A%'%C%/$5$l$?(Bstep$B$,(Bparent$B$K;}$D(Bstep$B$b(Bis_finished$B$K$7$J$1$l$P$J$i$J$$!%(B
					# 
					#
				else # is_finished$B$J$i(BNOT_YET$B$K!%(B
					# $B%A%'%C%/$5$l$?(Bstep$B$r(BNOT_YET$B$K!%(B
					@hash_mode["step"]["mode"][id][1] = "NOT_YET"
					# $B%A%'%C%/$5$l$?(Bstep$B$K4^$^$l$k(Bsubstep$B$rA4$F(BNOT_YET$B$K!%(B
					@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
						# substep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K$9$k!%(B
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
							}
						}
					}
					# $B%A%'%C%/$5$l$?(Bstep$B$r(Bparent$B$K;}$D(Bis_finished$B$J(Bstep$B$rA4$F(BNOT_YET$B$K$9$k!%(B
					@hash_mode["step"]["mode"].each{|key, value|
						if value[1] == "is_finished"
							if @doc.elements["//step[@id=\"#{key}\"]/parent"] != nil
								@doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
									if v == id
										@hash_mode["step"]["mode"][key][1] = "NOT_YET"
										# NOT_YET$B$K$5$l$?(Bstep$B$K4^$^$l$k(Bsubstep$B$rA4$F(BNOT_YET$B$K!%(B
										@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
											substep_id = node.attributes.get_attribute("id").value
											@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
											# substep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K$9$k!%(B
											media = ["audio", "video", "notification"]
											media.each{|v|
												@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
													media_id = node.attributes.get_attribute("id").value
													@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
												}
											}
										}
										break
									end
								}
							end
						end
					}
				end
				# ABLE$B$^$?$O(BOTHERS$B$NA`:n$N$?$a$K!$(BCURRENT$B$J(Bstep$B$H(Bsubstep$B$N(Bid$B$rD4$Y$k!%(B
				current_step, current_substep = search_CURRENT(@doc, @hash_mode)
				# ABLE$B$^$?$O(BOTHERS$B$NA`:n!%(B
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
				# $B2DG=$J(Bsubstep$B$KA+0\$9$k(B
				@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
				# $B:FEY(BABLE$B$NH=Dj$r9T$&(B
				current_step, current_substep = search_CURRENT(@doc, @hash_mode)
				# ABLE$B$^$?$O(BOTHERS$B$NA`:n!%(B
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
			when "substep"
				# is_finished$B$^$?$O(BNOT_YET$B$NA`:n!%(B
				if @hash_mode["substep"]["mode"][id][1] == "NOT_YET" # NOT_YET$B$J$i$P(Bis_finished$B$K!%(B
					parent_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
					media = ["audio", "video", "notification"]
					# $B%A%'%C%/$5$l$?(Bsubstep$B$r4^$a$=$l0JA0$N(Bsubstep$BA4$F$r(Bis_finished$B$K!%(B
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node1|
						child_substep = node1.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][child_substep][1] = "is_finished"
						# $B$=$N(Bsubstep$B$K4^$^$l$k%a%G%#%"$r(BFINISHED$B$K!%(B
						# $B$b$7$b8=>u$G(BCURRENT$B$^$?$O(BKEEP$B$J$i$P!$:F@8Cf$^$?$O:F@8BT$A$J$N$G(BSTOP$B$K!%(B
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
								media_id = node2.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						}
						# $B%A%'%C%/$5$l$?(Bsubstep$B$r(Bis_finished$B$K$7$?$i%k!<%W=*N;!%(B
						if child_substep == id
							# $B%A%'%C%/$5$l$?(Bsubstep$B$,(Bstep$BFb$N:G=*(Bsubstep$B$J$i$P!$?F%N!<%I$b(Bis_finished$B$K$9$k!%(B
							if node1.next_sibling_node == nil
								@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
								# current$B$NC5:w(B
								current_step, current_substep = search_CURRENT(@doc, @hash_mode)
								# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K!%(B
								@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
							end
							break
						end
					}
					# current$B$NC5:w(B
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# $B2DG=$J(Bsubstep$B$KA+0\$9$k(B
					@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
					# $B:FEY(Bcurrent$B$NC5:w(B
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# ABLE$B$^$?$O(BOTHERS$B$NA`:n!%(B
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
				else # is_finished$B$J$i$P(BNOT_YET$B$K!%(B
					parent_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
					media = ["audio", "video", "notification"]
					# $B%A%'%C%/$5$l$?(Bsubstep$B$r4^$`$=$l0J9_$N!JF10l(Bstep$BFb$N!K(Bsubstep$B$r(BNOT_YET$B$K!%(B
					flag = -1
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node|
						child_substep = node.attributes.get_attribute("id").value
						if flag == 1
							@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
							# $B$=$N(Bsubstep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K!%(B
							media.each{|v|
								@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
									media_id = node2.attributes.get_attribute("id").value
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							}
						end
						if child_substep == id
							flag = 1
							@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
							# $B$=$N(Bsubstep$B$K4^$^$l$k%a%G%#%"$r(BNOT_YET$B$K!%(B
							media.each{|v|
								@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
									media_id = node2.attributes.get_attribute("id").value
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							}
							# $B%A%'%C%/$5$l$?(Bsubstep$B$,F10l(Bstep$BFb$N:G=*(Bsubstep$B$J$i$P!$?F%N!<%I$N(Bstep$B$r(BNOT_YET$B$K$7$F!$(BABLE$B$NA`:n$r$9$k!%(B
							if node.next_sibling_node == nil
								@hash_mode["step"]["mode"][parent_step][1] = "NOT_YET"
								@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, parent_step, id)
							end
						end
					}
					# current$B$NC5:w(B
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# $B2DG=$J(Bsubstep$B$KA+0\$9$k(B
					@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
					# $B:FEY(Bcurrent$B$NC5:w(B
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# ABLE$B$N@_Dj(B
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
				end
			else
				return "invalid_params"
			end
			# notification$B$,:F@8:Q$_$+$I$&$+$O!$7d$"$i$PD4$Y$^$7$g$&!%(B
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			 p e
			 return "internal_error"
		end

		return "success"
	end
end
