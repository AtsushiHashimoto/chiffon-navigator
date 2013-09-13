#!/usr/bin/ruby

def set_ABLEorOTHERS(hash_recipe, hash_mode, current_step, current_substep)
	# step
	hash_mode["step"]["mode"].each{|key, value|
		# NOT_YETなstepのみがABLEになれる．
		if value[1] == "NOT_YET"
			# parentを持たないstepはいつでもできるので，無条件でABLEにする．
			unless hash_recipe["step"][key].key?("parent")
				hash_mode["step"]["mode"][key][0] = "ABLE"
			else # parentを持つstepは，その複数の(単数の場合あり)stepが全てis_finishedならばABLEにな
				flag = -1
				hash_recipe["step"][key]["parent"].each{|v|
					# parentとして指定されたidがちゃんと存在する．
					if hash_mode["step"]["mode"].key?(v)
						# parentがis_finishedならばABLEになる可能性あり．（その他のparentに期待）
						if hash_mode["step"]["mode"][v][1] == "is_finished"
							flag = 1
						# parentがis_finishedでない場合，
						else
							# parentがCURRENTなstepでありかつ，そのCURRENTなsubstepがstep内の最後尾であれば，ABLEになる可能性あり．（その他のparentに期待）
							if v == current_step && !hash_recipe["substep"][current_substep].key?("next_substep")
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
				if flag == 1
					hash_mode["step"]["mode"][key][0] = "ABLE"
				else
					# ABLEでないstepは明示的にOTHERSに
					hash_mode["step"]["mode"][key][0] = "OTHERS"
				end
			end
		else
			# ABLEでないstepは明示的にOTHERSに
			hash_mode["step"]["mode"][key][0] = "OTHERS"
		end

		# substepの処理
		# ["step"]["mode"][id][0] == ABLEなstepにおいて，is_finishedでない一番最初のsubstepがABLEになれる．
		# ["step"]["mode"][id][2] == CURRENTなstepにおいてのみ，CURRENTなsubstepの次のsubstepもABLEになれる．

		# とりあえず，全てのsubstepをOTHERSにする．
		hash_recipe["step"][key]["substep"].each{|substep_id|
			hash_mode["substep"]["mode"][substep_id][0] = "OTHERS"
		}
		if value[0] == "ABLE"
			hash_recipe["step"][key]["substep"].each{|substep_id|
				if hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
					# 一番初めのsubstepをABLEに
					hash_mode["substep"]["mode"][substep_id][0] = "ABLE"
					# step，substep共にCURRENTならば次のsubstepもABLEにする
					if value[2] == "CURRENT" && hash_mode["substep"]["mode"][substep_id][2] == "CURRENT" && hash_recipe["substep"][substep_id].key?("next_substep")
						next_substep = hash_recipe["substep"][substep_id]["next_substep"]
						hash_mode["substep"]["mode"][next_substep][0] = "ABLE"
					end
					break
				end
			}
		end
	}
	return hash_mode
end

def go2current(hash_recipe, hash_mode, current_step, current_substep)
	# 現状でCURRENTなstepとsubstepをNOT_CURRENTにする．
	hash_mode["step"]["mode"][current_step][2] = "NOT_CURRENT"
	hash_mode["substep"]["mode"][current_substep][2] = "NOT_CURRENT"

	hash_recipe["sorted_step"].each{|v|
		if hash_mode["step"]["mode"][v[1]][0] == "ABLE"
			hash_mode["step"]["mode"][v[1]][2] = "CURRENT"
			hash_recipe["step"][v[1]]["substep"].each{|substep_id|
				if hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
					hash_mode["substep"]["mode"][substep_id][2] = "CURRENT"
					media = ["audio", "video", "notification"]
					media.each{|v|
						if hash_recipe["substep"][substep_id].key?(v)
							hash_recipe["substep"][substep_id][v].each{|media_id|
								if hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									hash_mode[v]["mode"][media_id][0] = "CURRENT"
								end
							}
						end
					}
					break
				end
			}
			break
		end
	}
	return hash_mode
end

def check_notification_FINISHED(hash_recipe, hash_mode, time)
	hash_mode["notification"]["mode"].each{|key, value|
		if value[0]  == "KEEP"
			if time > value[1]
				hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
				# notificationがaudioをもっていれば，それもFINISHEDにする．
				if hash_recipe["notification"][key].key?("audio")
					audio_id = hash_recipe["notification"][key]["audio"]
					hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
				end
			end
		end
	}
	return hash_mode
end

def search_CURRENT(hash_recipe, hash_mode)
	current_step = nil
	current_substep = nil
	hash_mode["step"]["mode"].each{|key, value|
		if hash_mode["step"]["mode"][key][2] == "CURRENT"
			current_step = key
			hash_recipe["step"][key]["substep"].each{|substep_id|
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
