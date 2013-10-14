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
	# 表示されている画面の管理のために（START時はOVERVIEW）
	hash_mode["display"] = "OVERVIEW"
	# DetailDrawで指定されるsubstepの管理
	hash_mode["shown"] = nil
	# 直前にcurrentであったstepの管理
	hash_mode["prev_step"] = nil
	# 直前にcurrentであったsubstepの管理
	hash_mode["prev_substep"] = nil
	# currentなstepの管理
	hash_mode["current_step"] = nil
	# currentなsubstepの管理
	hash_mode["current_substep"] = nil
	# EXTERNAL_INPUTで入力された，Takenされている物体リスト（サイズは最大２）
	hash_mode["taken"] = []

	# hahs_modeにおける各要素の初期設定
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
		media = ["audio", "video", "notification"]
		media.each{|media_name|
			hash_recipe["substep"][current_substep][media_name].each{|media_id|
				hash_mode[media_name][media_id]["PLAY_MODE"] = "START"
			}
		}
	end

	return hash_mode
end
