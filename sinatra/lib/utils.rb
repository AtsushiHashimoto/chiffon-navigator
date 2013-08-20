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
		# NOT_YETなstepのみがABLEになれる．
		if value[1] == "NOT_YET"
			# parentを持たないstepはいつでもできるので，無条件でABLEにする．
			if doc.elements["//step[@id=\"#{key}\"]/parent"] == nil
				hash_mode["step"]["mode"][key][0] = "ABLE"
			# parentを持つstepは，その複数の(単数の場合あり)stepが全てis_finishedならばABLEになる．
			else
				flag = -1
				doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
					# parentとして指定されたidがちゃんと存在する．
					if hash_mode["step"]["mode"].key?(v)
						# parentがis_finishedならばABLEになる可能性あり．（その他のparentに期待）
						if hash_mode["step"]["mode"][v][1] == "is_finished"
							flag = 1
						# parentがis_finishedでない場合，
						else
							# parentがCURRENTなstepでありかつABLEであれば，ABLEになる可能性あり．（その他のparentに期待）
							if v == current_step && hash_mode["step"]["mode"][current_step][0] == "ABLE"
								flag = 1
							# 上記以外はABLEになれないので直ちにbreak．
							else
								flag = -1
								break
							end
						end
					# parentとして指定されたidが存在しない場合，recipe.xmlの記述がおかしい．（エラーとして出す？）
					else
						flag = 1
					end
				}
				# parentが全てis_finishedならABLEに設定．
				if flag == 1 then
					hash_mode["step"]["mode"][key][0] = "ABLE"
				# ABLEでないstepは明示的にOTHERSに．
				else
					hash_mode["step"]["mode"][key][0] = "OTHERS"
				end
			end
		# ABLEでないstepは明示的にOTHERSに．
		else
			hash_mode["step"]["mode"][key][0] = "OTHERS"
		end
	}
	# substep
	# とりあえず，全てのsubstepをOTHERSにする．
	hash_mode["substep"]["mode"].each{|key, value|
		hash_mode["substep"]["mode"][key][0] = "OTHERS"
	}
	# current_substepの親ノードのstepがABLEの場合のみ，子ノードsubstepのいずれかがABLEになれる．
	if hash_mode["step"]["mode"][current_step][0] == "ABLE"
		doc.get_elements("//step[@id=\"#{current_step}\"]/substep").each{|node|
			substep_id = node.attributes.get_attribute("id").value
			# NOT_YETなsubstepの中で優先度の一番高いもの（一番初めに現れるもの）をABLEにする．
			if hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
				hash_mode["substep"]["mode"][substep_id][0] = "ABLE"
				# ABLEなsubstepがCURRENTでかつ，弟ノードなsubstepがあればそれをABLEにする．
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
	# 現状でCURRENTなstepとsubstepをNOT_CURRENTにする．
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
				# notificationがaudioをもっていれば，それもFINISHEDにする．
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

# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
def cancel(session_id, doc, hash_mode, *id)
	begin
		orders = []
		# 特に中止させるメディアについて指定が無い場合
		if id == []
			# audioとvideoの処理．
			# Cancelさせるべきものは，STOPになっているはず．
			media = ["audio", "video"]
			media.each{|v|
				if hash_mode.key?(v)
					hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOPからFINISHEDに変更．
							hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notificationの処理．
			# Cancelさせるべきものは，STOPのなっているはず．
			if hash_mode.key?("notification")
				hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOPからFINISHEDに変更．
						hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audioをもつnotificationの場合，audioもFINISHEDに変更．
						if doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # 中止させるメディアについて指定がある場合．
			id.each{|v|
				# 指定されたメディアのelement nameを調査．
				element_name = searchElementName(session_id, v)
				# audioとvideoの場合．
				if element_name == "audio" || element_name == "video"
					# 指定されたものが再生待ちかどうかとりあえず調べる，
					if hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notificationの場合．
					# 指定されたnotificationが再生待ちかどうかとりあえず調べる．
					if hash_mode["notification"]["mode"][v][0] == "KEEP"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audioを持つnotificationはaudioもFINISHEDに．
						if doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # 指定されたものがaudio，video，notificationで無い場合．
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
