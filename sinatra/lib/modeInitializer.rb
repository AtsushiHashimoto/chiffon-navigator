#!/usr/bin/ruby

def initialize_mode(hash_recipe)
	hash_mode = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}

	if hash_recipe.key?("step")
		hash_recipe["step"].each{|step_id, value|
			hash_mode["step"][step_id]["ABLE?"] = false
			hash_mode["step"][step_id]["is_finished?"] = false
			hash_mode["step"][step_id]["CURRENT?"] = false
			hash_mode["step"][step_id]["open?"] = false
		}
	end
	if hash_recipe.key?("substep")
		hash_recipe["substep"].each{|substep_id, value|
			hash_mode["substep"][substep_id]["ABLE?"] = false
			hash_mode["substep"][substep_id]["is_finished?"] = false
			hash_mode["substep"][substep_id]["CURRENT?"] = false
			hash_mode["substep"][substep_id]["can_be_searched?"] = false
			hash_mode["substep"][substep_id]["have_be_current?"] = false
		}
	end
	if hash_recipe.key?("audio")
		hash_recipe["audio"].each{|audio_id, value|
			hash_mode["audio"][audio_id]["PLAY_MODE"] = "---"
			hash_mode["audio"][audio_id]["time"] = -1
		}
	end
	if hash_recipe.key?("video")
		hash_recipe["video"].each{|video_id, value|
			hash_mode["video"][video_id]["PLAY_MODE"] = "---"
			hash_mode["video"][video_id]["time"] = -1
		}
	end
	if hash_recipe.key?("notification")
		hash_recipe["notification"].each{|notification_id, value|
			hash_mode["notification"][notification_id]["PLAY_MODE"] = "---"
			hash_mode["notification"][notification_id]["time"] = -1
		}
	end
	# 表示されている画面（START時はOVERVIEW）
	hash_mode["display"] = "OVERVIEW"
	# DetailDrawで指定される（currentな）substep
	hash_mode["shown"] = nil
	# 過去にcurrentであったsubstepのリスト
	hash_mode["prev_substep"] = []
	# currentなstep
	hash_mode["current_step"] = nil
	# currentなsubstep
	hash_mode["current_substep"] = nil
	# EXTERNAL_INPUTで入力された，takenされているリスト
	hash_mode["taken"] = {"food"=>{}, "seasoning"=>{}, "utensil"=>{}}
	# 直前のestimationのstate
	hash_mode["prev_estimation_level"] = nil
	# 現在のestimationのstate
	hash_mode["current_estimation_level"] = "recommend"

	# 優先度の最も高いstepをCURRENTとし，その一番目のsubstepもCURRENTにする．
	current_step = hash_recipe["sorted_step"][0][1]
	current_substep = hash_recipe["step"][current_step]["substep"][0]
	hash_mode["step"][current_step]["CURRENT?"] = true
	hash_mode["step"][current_step]["open?"] = true
	hash_mode["substep"][current_substep]["CURRENT?"] = true
	hash_mode["shown"] = current_substep
	hash_mode["current_step"] = current_step
	hash_mode["current_substep"] = current_substep
	# stepとsubstepを適切にABLEにする．
	hash_mode = updateABLE(hash_recipe, hash_mode, current_step, current_substep)
	if hash_mode["substep"][current_substep]["ABLE?"]
		hash_mode = controlMedia(hash_recipe, hash_mode, "all", "START", current_substep)
	end

	return hash_mode
end
