#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

def read_hash(session_id)
	hash_mode = Hash.new()
	open("records/#{session_id}/#{session_id}_mode.txt", "r"){|io|
		hash_mode = JSON.load(io)
	}
	sorted_step = []
	open("records/#{session_id}/#{session_id}_sortedstep.txt", "r"){|io|
		sorted_step = JSON.load(io)
	}
	doc = REXML::Document.new(open("records/#{session_id}/#{session_id}_recipe.xml"))
	return doc, hash_mode, sorted_step
end


def searchElementName(session_id, id)
	hash_id = Hash.new()
	open("records/#{session_id}/#{session_id}_table.txt", "r"){|io|
		hash_id = JSON.load(io)
	}
	element_name = nil
	hash_id.each{|key1, value1|
		value1["id"].each{|value2|
			if value2 == id then
				element_name = key1
				break
			end
		}
	}
	return element_name
end

def set_ABLEorOTHERS(doc, hash_mode, current_step, current_substep)
	# step
	hash_mode["step"]["mode"].each{|key, value|
		# NOT_YET$B$J(Bstep$B$N$_$,(BABLE$B$K$J$l$k!%(B
		if value[1] == "NOT_YET"
			# parent$B$r;}$?$J$$(Bstep$B$O$$$D$G$b$G$-$k$N$G!$L5>r7o$G(BABLE$B$K$9$k!%(B
			if doc.elements["//step[@id=\"#{key}\"]/parent"] == nil
				hash_mode["step"]["mode"][key][0] = "ABLE"
			# parent$B$r;}$D(Bstep$B$O!$$=$NJ#?t$N(B($BC1?t$N>l9g$"$j(B)step$B$,A4$F(Bis_finished$B$J$i$P(BABLE$B$K$J$k!%(B
			else
				flag = -1
				doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
					# parent$B$H$7$F;XDj$5$l$?(Bid$B$,$A$c$s$HB8:_$9$k!%(B
					if hash_mode["step"]["mode"].key?(v)
						# parent$B$,(Bis_finished$B$J$i$P(BABLE$B$K$J$k2DG=@-$"$j!%!J$=$NB>$N(Bparent$B$K4|BT!K(B
						if hash_mode["step"]["mode"][v][1] == "is_finished"
							flag = 1
						# parent$B$,(Bis_finished$B$G$J$$>l9g!$(B
						else
							# parent$B$,(BCURRENT$B$J(Bstep$B$G$"$j$+$D(BABLE$B$G$"$l$P!$(BABLE$B$K$J$k2DG=@-$"$j!%!J$=$NB>$N(Bparent$B$K4|BT!K(B
							if v == current_step && hash_mode["step"]["mode"][current_step][0] == "ABLE"
								flag = 1
							# $B>e5-0J30$O(BABLE$B$K$J$l$J$$$N$GD>$A$K(Bbreak$B!%(B
							else
								flag = -1
								break
							end
						end
					# parent$B$H$7$F;XDj$5$l$?(Bid$B$,B8:_$7$J$$>l9g!$(Brecipe.xml$B$N5-=R$,$*$+$7$$!%!J%(%i!<$H$7$F=P$9!)!K(B
					else
						flag = 1
					end
				}
				# parent$B$,A4$F(Bis_finished$B$J$i(BABLE$B$K@_Dj!%(B
				if flag == 1 then
					hash_mode["step"]["mode"][key][0] = "ABLE"
				# ABLE$B$G$J$$(Bstep$B$OL@<(E*$K(BOTHERS$B$K!%(B
				else
					hash_mode["step"]["mode"][key][0] = "OTHERS"
				end
			end
		# ABLE$B$G$J$$(Bstep$B$OL@<(E*$K(BOTHERS$B$K!%(B
		else
			hash_mode["step"]["mode"][key][0] = "OTHERS"
		end
	}
	# substep
	# $B$H$j$"$($:!$A4$F$N(Bsubstep$B$r(BOTHERS$B$K$9$k!%(B
	hash_mode["substep"]["mode"].each{|key, value|
		hash_mode["substep"]["mode"][key][0] = "OTHERS"
	}
	# current_substep$B$N?F%N!<%I$N(Bstep$B$,(BABLE$B$N>l9g$N$_!$;R%N!<%I(Bsubstep$B$N$$$:$l$+$,(BABLE$B$K$J$l$k!%(B
	if hash_mode["step"]["mode"][current_step][0] == "ABLE"
		doc.get_elements("//step[@id=\"#{current_step}\"]/substep").each{|node|
			substep_id = node.attributes.get_attribute("id").value
			# NOT_YET$B$J(Bsubstep$B$NCf$GM%@hEY$N0lHV9b$$$b$N!J0lHV=i$a$K8=$l$k$b$N!K$r(BABLE$B$K$9$k!%(B
			if hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
				hash_mode["substep"]["mode"][substep_id][0] = "ABLE"
				# ABLE$B$J(Bsubstep$B$,(BCURRENT$B$G$+$D!$Do%N!<%I$J(Bsubstep$B$,$"$l$P$=$l$r(BABLE$B$K$9$k!%(B
				if substep_id == current_substep && doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node != nil
					next_substep = doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node.attributes.get_attribute("id").value
					hash_mode["substep"]["mode"][next_substep][0] = "ABLE"
				end
				break
			end
		}
	end
	return hash_mode
end

def go2current(doc, hash_mode, sorted_step, current_step, current_substep)
	# $B8=>u$G(BCURRENT$B$J(Bstep$B$H(Bsubstep$B$r(BNOT_CURRENT$B$K$9$k!%(B
	hash_mode["step"]["mode"][current_step][2] = "NOT_CURRENT"
	hash_mode["substep"]["mode"][current_substep][2] = "NOT_CURRENT"

	sorted_step.each{|v|
		if hash_mode["step"]["mode"][v[1]][0] == "ABLE"
			hash_mode["step"]["mode"][v[1]][2] = "CURRENT"
			doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
				substep_id = node.attributes.get_attribute("id").value
				if hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
					hash_mode["substep"]["mode"][substep_id][2] = "CURRENT"
					media = ["audio", "video", "notification"]
					media.each{|v|
						doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node2|
							media_id = node2.attributes.get_attribute("id").value
							if hash_mode[v]["mode"][media_id][0] == "NOT_YET"
								hash_mode[v]["mode"][media_id][0] = "CURRENT"
							end
						}
					}
					break
				end
			}
			break
		end
	}
	return hash_mode
end

def check_notification_FINISHED(doc, hash_mode, time)
	hash_mode["notification"]["mode"].each{|key, value|
		if value[0]  == "KEEP"
			if time > value[1]
				hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
				# notification$B$,(Baudio$B$r$b$C$F$$$l$P!$$=$l$b(BFINISHED$B$K$9$k!%(B
				doc.get_elements("//notification[@id=\"#{key}\"]/audio").each{|node|
					audio_id = node.attributes.get_attribute("id").value
					if audio_id != nil
						hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
					end
				}
			end
		end
	}
	return hash_mode
end

def search_CURRENT(doc, hash_mode)
	current_step = nil
	current_substep = nil
	hash_mode["step"]["mode"].each{|key, value|
		if hash_mode["step"]["mode"][key][2] == "CURRENT"
			current_step = key
			doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
				substep_id = node.attributes.get_attribute("id").value
				if hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
					current_substep = substep_id
					break
				end
			}
			break
		end
	}
	return current_step, current_substep
end

def logger()
end

def errorLOG()
end

# $B:F@8BT$A>uBV$N(Baudio$B!$(Bvideo$B!$(Bnotification$B$rCf;_$9$k(BCancel$BL?Na!%(B
def cancel(session_id, doc, hash_mode, *id)
	begin
		orders = []
		# $BFC$KCf;_$5$;$k%a%G%#%"$K$D$$$F;XDj$,L5$$>l9g(B
		if id == []
			# audio$B$H(Bvideo$B$N=hM}!%(B
			# Cancel$B$5$;$k$Y$-$b$N$O!$(BSTOP$B$K$J$C$F$$$k$O$:!%(B
			media = ["audio", "video"]
			media.each{|v|
				if hash_mode.key?(v)
					hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOP$B$+$i(BFINISHED$B$KJQ99!%(B
							hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notification$B$N=hM}!%(B
			# Cancel$B$5$;$k$Y$-$b$N$O!$(BSTOP$B$N$J$C$F$$$k$O$:!%(B
			if hash_mode.key?("notification")
				hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOP$B$+$i(BFINISHED$B$KJQ99!%(B
						hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audio$B$r$b$D(Bnotification$B$N>l9g!$(Baudio$B$b(BFINISHED$B$KJQ99!%(B
						if doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # $BCf;_$5$;$k%a%G%#%"$K$D$$$F;XDj$,$"$k>l9g!%(B
			id.each{|v|
				# $B;XDj$5$l$?%a%G%#%"$N(Belement name$B$rD4::!%(B
				element_name = searchElementName(session_id, v)
				# audio$B$H(Bvideo$B$N>l9g!%(B
				if element_name == "audio" || element_name == "video"
					# $B;XDj$5$l$?$b$N$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!$(B
					if hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notification$B$N>l9g!%(B
					# $B;XDj$5$l$?(Bnotification$B$,:F@8BT$A$+$I$&$+$H$j$"$($:D4$Y$k!%(B
					if hash_mode["notification"]["mode"][v][0] == "KEEP"
						# Cancel$B$7$F(BFINISHED$B$K!%(B
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audio$B$r;}$D(Bnotification$B$O(Baudio$B$b(BFINISHED$B$K!%(B
						if doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # $B;XDj$5$l$?$b$N$,(Baudio$B!$(Bvideo$B!$(Bnotification$B$GL5$$>l9g!%(B
					return [], hash_mode, "invalid_params"
				end
			}
		end
	rescue => e
		p e
		return [], hash_mode, "internal_error"
	end

	return orders, hash_mode, "success"
end
