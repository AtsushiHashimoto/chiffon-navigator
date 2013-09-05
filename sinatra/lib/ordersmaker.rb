#!?usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

# CURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
def detailDraw(hash_mode)
	orders = []
	hash_mode["substep"]["mode"].each{|key, value|
		# CURRENなsubstepは一つだけ（のはず）．
		if value[2] == "CURRENT"
			orders.push({"DetailDraw"=>{"id"=>key}})
			break
		end
	}
	return orders
end

# CURRENTなaudioとvideoを再生させるPlay命令．
def play(hash_recipe, hash_mode, time)
	orders = []
	media = ["audio", "video"]
	media.each{|v|
		hash_mode[v]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# triggerの数が1個以上のとき．
				if hash_recipe[v][key].key?("trigger")
					# triggerが複数個の場合，どうするのか考えていない．
					orders.push({"Play"=>{"id"=>key, "delay"=>hash_recipe[v][key]["trigger"][0][2].to_i}})
					finish_time = time + hash_recipe[v][key]["trigger"][0][2].to_i * 1000
					hash_mode[v]["mode"][key][1] = finish_time
				else # triggerが0個のとき．
					# triggerが無い場合は再生命令は出さないが，hash_modeはどう変更するのか考えていない．
					# @hash_mode[v]["mode"][key][1] = ?
					return []
				end
			end
		}
	}
	return orders, hash_mode
end

# CURRENTなnotificationを再生させるNotify命令．
def notify(hash_recipe, hash_mode, time)
	orders = []
	hash_mode["notification"]["mode"].each{|key, value|
		if value[0] == "CURRENT"
			# notificationはtriggerが必ずある．
			# triggerが複数個の場合，どうするのか考えていない．
			orders.push({"Notify"=>{"id"=>key, "delay"=>hash_recipe["notification"][key]["trigger"][0][2].to_i}})
			finish_time = time + hash_recipe["notification"][key]["trigger"][0][2].to_i * 1000
			# notificationは特殊なので，特別にKEEPに変更する．
			hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
		end
	}
	return orders, hash_mode
end

# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
def cancel(hash_recipe, hash_mode, *id)
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
						if hash_recipe["notification"][key].key?("audio")
							audio_id = hash_recipe["notification"][key]["audio"]
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # 中止させるメディアについて指定がある場合．
			id.each{|v|
				# 指定されたメディアのelement nameを調査．
				element_name = search_ElementName(hash_recipe, v)
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
						if hash_recipe["notification"][v].key?("audio")
							audio_id = hash_recipe["notification"][v]["audio"]
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # 指定されたものがaudio，video，notificationで無い場合．
					return [], hash_mode, "invalid params"
				end
			}
		end
	rescue => e
		p e
		return [], hash_mode, "internal error"
	end

	return orders, hash_mode, "success"
end

# ナビ画面の表示を決定するNaviDraw命令．
def naviDraw(hash_recipe, hash_mode)
	# sorted_stepの順に表示させる．
	orders = Array.new()
	orders.push({"NaviDraw"=>{"steps"=>[]}})
	hash_recipe["sorted_step"].each{|v|
		id = v[1]
		visual = nil
		if hash_mode["step"]["mode"][id][2] == "CURRENT"
			visual = "CURRENT"
		else
			visual = hash_mode["step"]["mode"][id][0]
		end
		if hash_mode["step"]["mode"][id][1] == "is_finished"
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
		elsif hash_mode["step"]["mode"][id][1] == "NOT_YET"
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
		end
		# CURRENTなstepの場合，substepも表示させる．
		if visual == "CURRENT"
			hash_recipe["step"][id]["substep"].each{|id|
				visual = nil
				if hash_mode["substep"]["mode"][id][2] == "CURRENT"
					visual = "CURRENT"
				else
					visual = hash_mode["substep"]["mode"][id][0]
				end
				if hash_mode["substep"]["mode"][id][1] == "is_finished"
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
				else
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
				end
			}
		end
		# NAVI_MENUで選択されたものも，substepを表示させる．（未対応）
		if hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
			hash_recipe["step"][id]["substep"].each{|id|
				visual = nil
				if hash_mode["substep"]["mode"][id][2] == "CURRENT"
					visual = "CURRENT"
				else
					visual = hash_mode["substep"]["mode"][id][0]
				end
				if hash_mode["substep"]["mode"][id][1] == "is_finished"
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
				else
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
				end
			}
		end
	}
	return orders
end
