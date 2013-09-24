#!/usr/bin/ruby

def set_ABLEorOTHERS(hash_recipe, hash_mode, current_step, current_substep)
	hash_mode["step"].each{|step_id, value|
		if !value["is_finished?"]
			if hash_recipe["step"][step_id]["parent"].empty?
				hash_mode["step"][step_id]["ABLE?"] = true
			else
				flag = -1
				hash_recipe["step"][step_id]["parent"].each{|parent_id|
					if hash_mode["step"][parent_id]["is_finished?"]
						flag = 1
					elsif parent_id == current_step && hash_recipe["substep"][current_substep]["next_substep"] == nil
						flag = 1
					else
						flag = -1
						break
					end
				}
				if flag == 1
					hash_mode["step"][step_id]["ABLE?"] = true
				else
					hash_mode["step"][step_id]["ABLE?"] = false
				end
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
					if step_id == current_step && substep_id == current_substep && hash_recipe["substep"][substep_id]["next_substep"] != nil
						next_substep = hash_recipe["substep"][substep_id]["next_substep"]
						hash_mode["substep"][next_substep]["ABLE?"] = true
					end
					break
				end
			}
		end
	}
	return hash_mode
end

def go2next(hash_recipe, hash_mode)
	next_step = nil
	next_substep = nil
	hash_recipe["sorted_step"].each{|v|
		if hash_mode["step"][v[1]]["ABLE?"]
			hash_mode["step"][v[1]]["CURRENT?"] = true
			hash_mode["step"][v[1]]["open?"] = true
			next_step = v[1]
			hash_recipe["step"][v[1]]["substep"].each{|substep_id|
				unless hash_mode["substep"][substep_id]["is_finished?"]
					hash_mode["substep"][substep_id]["CURRENT?"] = true
					hash_mode["substep"][substep_id]["is_shown?"] = true
					next_substep = substep_id
					media = ["audio", "video", "notification"]
					media.each{|media_name|
						hash_recipe["substep"][substep_id][media_name].each{|media_id|
							hash_mode[media_name][media_id]["PLAY_MODE"] = "START"
						}
					}
					break
				end
			}
			break
		end
	}
	return hash_mode, next_step, next_substep
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

def search_CURRENT(hash_recipe, hash_mode)
	current_step = nil
	current_substep = nil
	hash_mode["step"].each{|key, value|
		if hash_mode["step"][key]["CURRENT?"]
			current_step = key
			hash_recipe["step"][key]["substep"].each{|substep_id|
				if hash_mode["substep"][substep_id]["CURRENT?"]
					current_substep = substep_id
					break
				end
			}
			break
		end
	}
	return current_step, current_substep
end

def check_isFinished(hash_recipe, hash_mode, id)
	media = ["audio", "video", "notification"]
	if hash_recipe["step"].key?(id)
		unless hash_mode["step"][id]["is_finished?"]
			hash_mode["step"][id]["is_finished?"] = true
			hash_recipe["step"][id]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = true
				media.each{|media_name|
					hash_recipe["substep"][substep_id][media_name].each{|media_id|
						if hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
							hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
						end
					}
				}
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
				media.each{|media_name|
					hash_recipe["substep"][substep_id][media_name].each{|media_id|
						if hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
							hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
						end
					}
				}
				if substep_id == id
					break
				end
			}
			if hash_recipe["substep"][id]["next_substep"] == nil
				hash_mode["step"][parent_step]["is_finished?"] = true
				hash_recipe["step"][parent_step]["parent"].each{|parent_id|
					hash_mode = check_isFinished(hash_recipe, hash_mode, parent_id)
				}
			end
		end
	end
	return hash_mode
end

def uncheck_isFinished(hash_recipe, hash_mode, id)
	media = ["audio", "video", "notification"]
	if hash_recipe["step"].key?(id)
		if hash_mode["step"][id]["is_finished?"]
			hash_mode["step"][id]["is_finished?"] = false
			hash_recipe["step"][id]["substep"].each{|substep_id|
				hash_mode["substep"][substep_id]["is_finished?"] = false
				media.each{|media_name|
					hash_recipe["substep"][substep_id][media_name].each{|media_id|
						hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
						hash_mode[media_name][media_id]["time"] = -1
					}
				}
			}
			hash_recipe["step"].each{|step_id, value|
				hash_recipe["step"][step_id]["parent"].each{|parent_id|
					if parent_id == id && hash_mode["step"][step_id]["is_finished?"]
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
				media.each{|media_name|
					hash_recipe["substep"][substep_id][media_name].each{|media_id|
						hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
						hash_mode[media_name][media_id]["time"] = -1
					}
				}
				if substep_id == id
					break
				end
			}
			if hash_recipe["substep"][id]["next_substep"] == nil
				hash_mode["step"][parent_step]["is_finished?"] = false
				hash_recipe["step"].each{|step_id, value|
					hash_recipe["step"][step_id]["parent"].each{|parent_id|
						if parent_id == id && hash_mode["step"][step_id]["is_finished?"]
							hash_mode = uncheck_isFinished(hash_recipe, hash_mode, step_id)
						end
					}
				}
			end
		end
	end
	return hash_mode
end

def logger()
end
