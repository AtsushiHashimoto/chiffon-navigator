#!/usr/bin/ruby

def controlMedia(hash_recipe, hash_mode, media_array, play_mode, *id_array)
	media_array = ["audio", "video", "notification"] if media_array == "all"
	case play_mode
	when "FIRST"
		# 開始時に再生すべきnotificationが無いか探索し，そのidを返す
		hash_recipe["notification"].each{|id, value|
			trigger = value["trigger"][0]["ref"]["other"][0]
			if trigger == "first"
				return id
			end
		}
		return nil
	when "INITIALIZE"
		# 与えられたsubstepのメディアを初期化する
		unless id_array == []
			substep_id = id_array[0]
			media_array.each{|media_name|
				hash_recipe["substep"][substep_id][media_name].each{|media_id|
					hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
					hash_mode[media_name][media_id]["time"] = -1
				}
			}
		end
		return hash_mode
	when "START"
		substep_id = nil
		if id_array == []
			substep_id = hash_mode["current_substep"]
		else
			id = id_array[0]
			if hash_recipe["substep"].key?(id)
				substep_id = id
			elsif hash_recipe["audio"].key?(id)
				if hash_mode["audio"][id]["PLAY_MODE"] == "---"
					hash_mode["audio"][id]["PLAY_MODE"] = "START"
				end
				return hash_mode
			elsif hash_recipe["video"].key?(id)
				if hash_mode["video"][id]["PLAY_MODE"] == "---"
					hash_mode["video"][id]["PLAY_MODE"] = "START"
				end
				return hash_mode
			elsif hash_recipe["notification"].key?(id)
				if hash_mode["notification"][id]["PLAY_MODE"] == "---"
					hash_mode["notification"][id]["PLAY_MODE"] = "START"
				end
				return hash_mode
			end
		end
		media_array.each{|media_name|
			hash_recipe["substep"][substep_id][media_name].each{|media_id|
				media_trigger = nil
				if hash_recipe[media_name][media_id]["trigger"][0] != nil
					media_trigger = hash_recipe[media_name][media_id]["trigger"][0]["ref"]["other"][0]
				end
				if media_trigger == "sametime" && hash_mode[media_name][media_id]["PLAY_MODE"] == "---"
					hash_mode[media_name][media_id]["PLAY_MODE"] = "START"
				end
			}
		}
		return hash_mode
	when "STOP"
		# 全てのメディア，または与えられたsubstepのメディアを停止する
		if id_array = []
			media_array.each{|media_name|
				hash_mode[media_name].each{|media_id, value|
					if value["PLAY_MODE"] == "PLAY"
						hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
			return hash_mode
		end
		substep_id = id_array[0]
		media_array.each{|media_name|
			hash_recipe["substep"][substep_id][media_name].each{|media_id|
				if hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
					hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
				end
			}
		}
		return hash_mode
	end
	# invalid play_mode
	return hash_mode
end

def updateABLE(hash_recipe, hash_mode, *current)
	current_step = nil
	current_substep = nil
	unless current == []
		current_step = current[0]
		current_substep = current[1]
	end
	hash_mode["step"].each{|step_id, value|
		if !value["is_finished?"]
			if hash_recipe["step"][step_id]["parent"].empty?
				hash_mode["step"][step_id]["ABLE?"] = true
			else
				flag = false
				hash_recipe["step"][step_id]["parent"].each{|parent_id|
					if hash_mode["step"][parent_id]["is_finished?"]
						flag = true
					elsif parent_id == current_step
						if hash_recipe["substep"][current_substep]["next_substep"] == nil
							flag = true
						else
							flag = false
							break
						end
					else
						flag = false
						break
					end
				}
				hash_mode["step"][step_id]["ABLE?"] = flag
			end
		else
			hash_mode["step"][step_id]["ABLE?"] = false
		end

		hash_recipe["step"][step_id]["substep"].each{|substep_id|
			hash_mode["substep"][substep_id]["ABLE?"] = false
			# have_be_current=trueならnext substepをcan_be_searched=trueにする．
			if hash_mode["substep"][substep_id]["have_be_current?"]
				next_substep = hash_mode["substep"][substep_id]["next_substep"]
				hash_mode["substep"][substep_id]["can_be_searched?"] = true
			end
		}
		if hash_mode["step"][step_id]["ABLE?"]
			hash_recipe["step"][step_id]["substep"].each{|substep_id|
				unless hash_mode["substep"][substep_id]["is_finished?"]
					hash_mode["substep"][substep_id]["ABLE?"] = true
					# ableはcan_be_searched=trueにする．
					hash_mode["substep"][substep_id]["can_be_searched?"] = true
					if step_id == current_step && substep_id == current_substep
						if hash_recipe["substep"][substep_id]["next_substep"] != nil
							next_substep = hash_recipe["substep"][substep_id]["next_substep"]
							hash_mode["substep"][next_substep]["ABLE?"] = true
							hash_mode["substep"][next_substep]["can_be_searched?"] = true
						end
					end
					next_substep = hash_recipe["substep"][substep_id]["next_substep"]
					unless next_substep == nil
						if hash_recipe["substep"][substep_id]["order"] == hash_recipe["substep"][next_substep]["order"]
							next
						end
					end
					break
				end
			}
		end
	}
	return hash_mode
end

def sortSubstep(hash_recipe, hash_mode, current_substep)
	current_step = hash_recipe["substep"][current_substep]["parent_step"]
	substep_list = hash_recipe["step"][current_step]["substep"]
	# current_substepが一番目であれば，sortしない
	if hash_recipe["substep"][current_substep]["prev_substep"] == nil
		return hash_recipe
	end
	# orderが重複している事を確認
	order = -1
	flag = false
	substep_list.each{|substep_id|
		if flag
			unless order == hash_recipe["substep"][substep_id]["order"]
				return hash_recipe
			end
		end
		if substep_id == current_substep
			unless order == hash_recipe["substep"][substep_id]["order"]
				return hash_recipe
			end
			break
		end
		unless hash_mode["substep"][substep_id]["is_finished?"]
			order = hash_recipe["substep"][substep_id]["order"]
			flag = true
		end
	}
	i = 0
	# substepリストを修正
	substep_list.each{|substep_id|
		unless hash_mode["substep"][substep_id]["is_finished?"] || substep_id == current_substep
			# 先にcurrentになったsubstepをi番目に挿入する
			hash_recipe["step"][current_step]["substep"].insert(i, current_substep)
			# 挿入したsubstepのnext_susbtepを更新
			hash_recipe["substep"][current_substep]["next_substep"] = hash_recipe["step"][current_step]["substep"][i+1]
			# 挿入したsubstepのprev_substepを更新
			if i == 0
				hash_recipe["substep"][current_substep]["prev_substep"] = nil
			else
				hash_recipe["substep"][current_substep]["prev_substep"] = hash_recipe["step"][current_step]["substep"][i-1]
			end
			# i+1番目のsubstepのprev_substepを更新
			i = i + 1
			substep_id = hash_recipe["step"][current_step]["substep"][i]
			hash_recipe["substep"][substep_id]["prev_substep"] = current_substep
			# これ以降のlistはforループ内で更新
			for j in (i+1)..(substep_list.size)
				if hash_recipe["step"][current_step]["substep"][j] == current_substep
					# j-1番目のsubstepのnext_substepを更新
					substep_id = hash_recipe["step"][current_step]["substep"][j-1]
					if j == substep_list.size
						hash_recipe["substep"][substep_id]["next_substep"] = nil
					else
						hash_recipe["substep"][substep_id]["next_substep"] = hash_recipe["step"][current_step]["substep"][j+1]
					end
					# j番目のsubstepをdelete
					hash_recipe["step"][current_step]["substep"].delete_at(j)
					# j+1（deleteの結果本当はj）番目のsubstepのprev_substepを更新
					substep_id_2 = hash_recipe["step"][current_step]["substep"][j]
					hash_recipe["substep"][substep_id_2]["prev_substep"] = substep_id
					break
				end
			end
			break
		end
		i = i + 1
	}

	return hash_recipe
end

# id先に移動するだけ
# ableの設定はここでやる．
def jump(hash_recipe, hash_mode, next_substep)
	next_step = hash_recipe["substep"][next_substep]["parent_step"]
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	hash_mode["step"][current_step]["CURRENT?"] = false
	hash_mode["substep"][current_substep]["CURRENT?"] = false

	hash_mode["current_step"] = next_step
	hash_mode["current_substep"] = next_substep
	hash_mode["step"][next_step]["CURRENT?"] = true
	hash_mode["step"][next_step]["open?"] = true
	hash_mode["substep"][next_substep]["CURRENT?"] = true
	hash_mode["shown"] = next_substep

	hash_mode = updateABLE(hash_recipe, hash_mode, next_step, next_substep)
	return hash_mode
end

# 次のsubstepを探し，jumpで移動．
# 次のsubstepが無かったら何もしない
def go2next(hash_recipe, hash_mode)
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]

	next_substep = nil
	if hash_mode["step"][current_step]["ABLE?"]
		hash_recipe["step"][current_step]["substep"].each{|substep_id|
			unless hash_mode["substep"][substep_id]["is_finished?"]
				hash_mode = jump(hash_recipe, hash_mode, substep_id)
				return hash_mode
			end
		}
	end
	# chainなstepの探索
	hash_recipe["step"].each{|step_id, value|
		chain_step = hash_recipe["step"][step_id]["chain"][0]
		if chain_step == current_step && hash_mode["step"][step_id]["ABLE?"]
			hash_recipe["step"][step_id]["substep"].each{|substep_id|
				unless hash_mode["substep"][substep_id]["is_finished?"]
					hash_mode = jump(hash_recipe, hash_mode, substep_id)
					return hash_mode
				end
			}
			break
		end
	}
	# priorityが一つしたのstepを探索
	flag = false
	hash_recipe["sorted_step"].each{|value|
		if flag
			if hash_mode["step"][value[1]]["ABLE?"]
				hash_recipe["step"][value[1]]["substep"].each{|substep_id|
					unless  hash_mode["substep"][substep_id]["is_finished?"]
						hash_mode = jump(hash_recipe, hash_mode, substep_id)
						return hash_mode
					end
				}
			end
		else
			flag = false
		end
		if value[1] == current_step
			flag = true
		end
	}
	# current stepをparentにもつstepの探索
	# そのようなstepはableではないので，まだ終了していないparent stepを探索する
	hash_recipe["sorted_step"].each{|value|
		unless hash_mode["step"][value[1]]["is_finished?"]
			hash_recipe["step"][value[1]]["parent"].each{|step_id|
				if step_id == current_step
					hash_recipe["step"][value[1]]["parent"].each{|step_id|
						if !hash_mode["step"][step_id]["is_finished?"] && hash_mode["step"][step_id]["ABLE?"]
							hash_recipe["step"][step_id]["substep"].each{|substep_id|
								unless hash_mode["substep"][substep_id]["is_finished?"]
									hash_mode = jump(hash_recipe, hash_mode, substep_id)
									return hash_mode
								end
							}
						end
					}
				end
			}
		end
	}
	hash_recipe["sorted_step"].each{|value|
		if hash_mode["step"][value[1]]["ABLE?"]
			hash_recipe["step"][value[1]]["substep"].each{|substep_id|
				unless hash_mode["substep"][substep_id]["is_finished?"]
					hash_mode = jump(hash_recipe, hash_mode, substep_id)
					return hash_mode
				end
			}
		end
	}
	return hash_mode
end

def prev(hash_recipe, hash_mode)
	prev_substep = hash_mode["prev_substep"].pop
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	hash_mode = uncheck_isFinished(hash_recipe, hash_mode, prev_substep)
	hash_mode = jump(hash_recipe, hash_mode, prev_substep)
	return hash_mode
end

def check(hash_recipe, hash_mode, id)
	hash_mode = check_isFinished(hash_recipe, hash_mode, id)
	hash_mode = updateABLE(hash_recipe, hash_mode)
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	if hash_mode["substep"][current_substep]["is_finished?"]
		hash_mode = go2next(hash_recipe, hash_mode)
		hash_mode = controlMedia(hash_recipe, hash_mode, ["audio", "video", "notification"], "START")
	else
		hash_mode = updateABLE(hash_recipe, hash_mode, current_step, current_substep)
	end
	return hash_mode
end

def uncheck(hash_recipe, hash_mode, id)
	hash_mode = uncheck_isFinished(hash_recipe, hash_mode, id)
	hash_mode = updateABLE(hash_recipe, hash_mode)
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	if hash_mode["substep"][current_substep]["ABLE?"]
		hash_mode = updateABLE(hash_recipe, hash_mode, current_step, current_substep)
	else
		hash_mode = go2next(hash_recipe, hash_mode)
		hash_mode = controlMedia(hash_recipe, hash_mode, ["audio", "video", "notification"], "START")
	end
	return hash_mode
end

def check_notification_FINISHED(hash_recipe, hash_mode, time)
	hash_mode["notification"].each{|key, value|
		if value["PLAY_MODE"]  == "PLAY"
			if time > value["time"]
				hash_mode["notification"][key]["PLAY_MODE"] = "---"
				hash_mode["notification"][key]["time"] = -1
				hash_recipe["notification"][key]["audio"].each{|audio_id|
					hash_mode["audio"][audio_id]["PLAY_MODE"] = "---"
					hash_mode["audio"][audio_id]["time"] = -1
				}
			end
		end
	}
	return hash_mode
end

def check_isFinished(hash_recipe, hash_mode, id)
	media = ["audio", "video", "notification"]
	if hash_recipe["step"].key?(id)
		unless hash_mode["step"][id]["is_finished?"]
			hash_mode["step"][id]["is_finished?"] = true
			hash_mode["step"][id]["open?"] = false
			hash_recipe["step"][id]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = true
				# is_finished=trueなsubstepはcan_be_searched=trueにする
				hash_mode["substep"][substep_id]["can_be_searched?"] = true
				hash_mode = controlMedia(hash_recipe, hash_mode, "STOP", substep_id)
			}
			hash_recipe["step"][id]["parent"].each{|parent_id|
				hash_mode = check_isFinished(hash_recipe, hash_mode, parent_id)
			}
		end
	elsif hash_recipe["substep"].key?(id)
		unless hash_mode["substep"][id]["is_finished?"]
			parent_step = hash_recipe["substep"][id]["parent_step"]
			hash_recipe["step"][parent_step]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = true
				# is_finished=trueなsubstepはcan_be_searched=trueにする
				hash_mode["substep"][substep_id]["can_be_searched?"] = true
				hash_mode = controlMedia(hash_recipe, hash_mode, "STOP", substep_id)
				if substep_id == id
					break
				end
			}
			hash_recipe["step"][parent_step]["parent"].each{|parent_id|
				hash_mode = check_isFinished(hash_recipe, hash_mode, parent_id)
			}
			if hash_recipe["substep"][id]["next_substep"] == nil
				hash_mode["step"][parent_step]["is_finished?"] = true
				hash_mode["step"][parent_step]["open?"] = false
			end
		end
	end
	return hash_mode
end

def uncheck_isFinished(hash_recipe, hash_mode, id)
	media = ["audio", "video", "notification"]
	if hash_recipe["step"].key?(id)
		if hash_mode["step"][id]["is_finished?"] || hash_mode["substep"][hash_recipe["step"][id]["substep"][0]]["is_finished?"]
			hash_mode["step"][id]["is_finished?"] = false
			hash_recipe["step"][id]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = false
				# is_finished=falseにするときはcan_be_searched=falseにする
				hash_mode["substep"][substep_id]["can_be_searched?"] = false
				hash_mode = controlMedia(hash_recipe, hash_mode, media, "STOP", substep_id)
			}
			hash_recipe["step"].each{|step_id, value|
				hash_recipe["step"][step_id]["parent"].each{|parent_id|
					if parent_id == id
						hash_mode = uncheck_isFinished(hash_recipe, hash_mode, step_id)
					end
				}
			}
		end
	elsif hash_recipe["substep"].key?(id)
		if hash_mode["substep"][id]["is_finished?"]
			parent_step = hash_recipe["substep"][id]["parent_step"]
			hash_recipe["step"][parent_step]["substep"].reverse_each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = false
				# is_finished=falseにするときはcan_be_searched=falseにする
				hash_mode["substep"][substep_id]["can_be_searched?"] = false
				hash_mode = controlMedia(hash_recipe, hash_mode, media, "STOP", substep_id)
				if substep_id == id
					break
				end
			}
			hash_recipe["step"].each{|step_id, value|
				hash_recipe["step"][step_id]["parent"].each{|parent_id|
					if parent_id == parent_step
						hash_mode = uncheck_isFinished(hash_recipe, hash_mode, step_id)
					end
				}
			}
			if hash_recipe["step"][parent_step]["is_finished?"]
				hash_mode["step"][parent_step]["is_finished?"] = false
			end
		end
	end
	return hash_mode
end

def lock(session_id)
	unless File.exist?("records/#{session_id}/lockfile")
		system("touch records/#{session_id}/lockfile")
	end
	fo = open("records/#{session_id}/lockfile", "w")
	fo.flock(File::LOCK_EX)
	return fo
end

def unlock(fo)
	fo.flock(File::LOCK_UN)
	fo.close
end

def inputHashMode(session_id)
	open("records/#{session_id}/mode.txt", "r"){|io|
		hash_mode = JSON.load(io)
	}
	return hash_mode
end

def outputHashMode(session_id, time, hash_mode)
	open("records/#{session_id}/mode/#{time["sec"]}-#{time["usec"]}.mode", "w"){|io|
		io.puts(JSON.pretty_generate(hash_mode))
	}
end

def logger(jason_input, status, message, *estimation_level)
	time = Time.at(jason_input["time"]["sec"].to_i, jason_input["time"]["usec"].to_i).strftime("%Y.%m.%d-%H.%M.%S-%L")
	situation = jason_input["situation"]
	output = nil
	if status == "success"
		if situation == "CHANNEL"
			if jason_input["operation_contents"] == "GUIDE"
				message.each{|part|
					if part.key?("DetailDraw")
						if part["DetailDraw"].key?("id")
							output = "#{situation} : #{jason_input["operation_contents"]} : #{part["DetailDraw"]["id"]}"
						else
							output = "#{situation} : #{jason_input["operation_contents"]} : {}"
						end
						break
					end
				}
				if output == nil
					output = "#{situation} : #{jason_input["operation_contents"]}"
				end
			else
				output = "#{situation} : #{jason_input["operation_contents"]}"
			end
		elsif situation == "PLAY_CONTROL"
			if jason_input["operation_contents"].key?("value")
				output = "#{situation} : #{jason_input["operation_contents"]["value"]} : #{jason_input["operation_contents"]["operation"]} : #{jason_input["operation_contents"]["id"]}"
			else
				output = "#{situation} : #{jason_input["operation_contents"]["operation"]} : #{jason_input["operation_contents"]["id"]}"
			end
		elsif situation == "START" || situation == "END"
			output = "#{situation}"
		elsif situation == "CHECK" || situation == "NAVI_MENU" || situation == "EXTERNAL_INPUT"
			output = "#{situation}"
			message.each{|part|
				if part.key?("DetailDraw")
					if part["DetailDraw"].key?("id")
						output = output + " : #{part["DetailDraw"]["id"]} : #{estimation_level[0]}"
					else
						output = output + " : {} : #{estimation_level[0]}"
					end
					break
				end
			}
		end
	else
		output = message
	end
	open("records/#{jason_input["session_id"]}/log", "a"){|io|
		io.print("[#{time}]")
		io.print(" [#{status}]")
		io.puts(" #{output}")
	}
end
