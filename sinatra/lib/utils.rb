#!/usr/bin/ruby

def bodyMaker(hash_mode, hash_body, time, session_id)
	body = []
	if hash_body["DetailDraw"]
		body.concat(detailDraw(session_id))
	end
	if hash_body["Play"]
		body.concat(play(time, session_id))
	end
	if hash_body["Notify"]
		body.concat(notify(time, session_id))
	end
	if hash_body["Cancel"]
		body.concat(cancel(session_id))
	end
	if hash_body["ChannelSwitch"]
		body.push({"ChannelSwitch"=>{"channel"=>hash_mode["display"]}})
	end
	if hash_body["NaviDraw"]
		body.concat(naviDraw(session_id))
	end
	return body
end

def controlMedia(hash_recipe, hash_mode, media_array, media_mode, *id_array)
	case media_mode
	when "INITIALIZE"
		unless id_array == []
			substep_id = id_array[0]
			media_array.each{|media_name|
				hash_recipe["substep"][substep_id][media_name].each{|media_id|
					hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
					hash_mode[media_name][media_id]["time"] = -1
				}
			}
		end
	when "START"
		unless id_array == []
			substep_id = id_array[0]
			media_array.each{|media_name|
				hash_recipe["substep"][substep_id][media_name].each{|media_id|
					hash_mode[media_name][media_id]["PLAY_MODE"] = "START"
				}
			}
		end
	when "STOP"
		if id_array = []
			media_array.each{|media_name|
				hash_mode[media_name].each{|media_id, value|
					if value["PLAY_MODE"] == "PLAY"
						hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
		else
			substep_id = id_array[0]
			media_array.each{|media_name|
				hash_recipe["substep"][substep_id][media_name].each{|media_id|
					if hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
						hash_mode[media_name][media_id]["PLAY_MODE"] == "STOP"
					end
				}
			}
		end
	end
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
		}
		if hash_mode["step"][step_id]["ABLE?"]
			hash_recipe["step"][step_id]["substep"].each{|substep_id|
				unless hash_mode["substep"][substep_id]["is_finished?"]
					hash_mode["substep"][substep_id]["ABLE?"] = true
					if step_id == current_step && substep_id == current_substep
						if hash_recipe["substep"][substep_id]["next_substep"] != nil
							next_substep = hash_recipe["substep"][substep_id]["next_substep"]
							hash_mode["substep"][next_substep]["ABLE?"] = true
						end
					end
					break
				end
			}
		end
	}
	return hash_mode
end

# id先に移動する．
# mode=INITIALIZEなら，currentなsubstepはothersにする．
# mode=FINISHなら，currentなsubstepはis_finishedにする．
# ableの設定等もここでやる．
def jump(hash_recipe, hash_mode, next_substep, mode, prev)
	next_step = hash_recipe["substep"][next_substep]["parent_step"]
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	hash_mode["step"][current_step]["CURRENT?"] = false
	hash_mode["substep"][current_substep]["CURRENT?"] = false

	hash_mode["current_step"] = next_step
	hash_mode["current_substep"] = next_substep
	unless prev
		hash_mode["prev_substep"].push(current_substep)
	end
	hash_mode["step"][next_step]["CURRENT?"] = true
	hash_mode["step"][next_step]["open?"] = true
	hash_mode["substep"][next_substep]["CURRENT?"] = true
	hash_mode["shown"] = next_substep

	media = ["audio", "video", "notification"]
	if mode == "finish"
		hash_mode = check_isFinished(hash_recipe, hash_mode, current_substep)
	elsif mode == "initialize"
		hash_mode = controlMedia(hash_recipe, hash_mode, media, "STOP", current_substep)
	end

	hash_mode = controlMedia(hash_recipe, hash_mode, media, "START", next_substep)
	hash_mode = updateABLE(hash_recipe, hash_mode, next_step, next_substep)
	return hash_mode
end

# currentのsubstepをis_finished=trueにし，次のsubstepに遷移する．
# abel等の設定も全てここで行う
def go2next(hash_recipe, hash_mode, *mode)
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	if mode == []
		hash_mode = check_isFinished(hash_recipe, hash_mode, current_substep)
		hash_mode = updateABLE(hash_recipe, hash_mode)
	end
	next_substep = nil
	if hash_mode["step"][current_step]["ABLE?"]
		hash_recipe["step"][current_step]["substep"].each{|substep_id|
			unless hash_mode["substep"][substep_id]["is_finished?"]
				next_substep = substep_id
				break
			end
		}
	end
	if next_substep == nil
		hash_recipe["sorted_step"].each{|value|
			if hash_mode["step"][value[1]]["ABLE?"]
				hash_recipe["step"][value[1]]["substep"].each{|substep_id|
					unless hash_mode["substep"][substep_id]["is_finished?"]
						next_substep = substep_id
						break
					end
				}
				break
			end
		}
	end
	hash_mode = jump(hash_recipe, hash_mode, next_substep, "initialize", false)
	return hash_mode
end

def prev(hash_recipe, hash_mode)
	prev_substep = hash_mode["prev_substep"].pop
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	hash_mode = uncheck_isFinished(hash_recipe, hash_mode, prev_substep)
	hash_mode = jump(hash_recipe, hash_mode, prev_substep, "initialize", true)
	return hash_mode
end

def check(hash_recipe, hash_mode, id)
	hash_mode = check_isFinished(hash_recipe, hash_mode, id)
	hash_mode = updateABLE(hash_recipe, hash_mode)
	current_step = hash_mode["current_step"]
	current_substep = hash_mode["current_substep"]
	if hash_mode["substep"][current_substep]["is_finished?"]
		hash_mode = go2next(hash_recipe, hash_mode, "check")
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
		hash_mode = go2next(hash_recipe, hash_mode, "uncheck")
	end
	return hash_mode
end

def check_notification_FINISHED(hash_recipe, hash_mode, time)
	hash_mode["notification"].each{|key, value|
		if value["PLAY_MODE"]  == "PLAY"
			if time > value["time"]
				hash_mode["notification"][key]["PLAY_MODE"] = "---"
				hash_mode["notification"][key]["time"] = -1
				hash_recipe["notification"][key]["audio"].empty{|audio_id|
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
			hash_recipe["step"][id]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = true
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
				hash_mode = controlMedia(hash_recipe, hash_mode, media, "INITIALIZE", substep_id)
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
				hash_mode = controlMedia(hash_recipe, hash_mode, media, "INITIALIZE", substep_id)
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

def outputHashMode(session_id, hash_mode)
	open("records/#{session_id}/mode.txt", "w"){|io|
		io.puts(JSON.pretty_generate(hash_mode))
	}
end

def logger()
end
