#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase

	private

	def external_input(jason_input, session_id)
		body = []
		# EXTERNALINPUTのチェック
		e_input = nil
		begin
			e_input = JSON.load(jason_input["operation_contents"])
		rescue
			message = "EXTERNAL_INPUT can not be loaded because of invalid form."
			p message
			p "EXTERNAL_INPUT must be {\"navigator\":hoge,\"mode\":\"hogehoge\",...}"
			logger(jason_input, "invalid params", message)
			return "invalid params", body
		end
		# inputのチェック
		result, message = inputChecker_externalinput(@hash_recipe[session_id], @hash_mode[session_id], e_input)
		unless result
			p "EXTERNAL_INPUT is wrong."
			p message
			logger(jason_input, "invalid params", message)
			return "invalid params", body
		end
		# modeの修正
		updated = modeUpdate_externalinput(jason_input["time"], e_input, session_id)

		# modeが修正された場合は，bodyを形成する
		if updated
			@hash_body[session_id].each{|key, value|
				if key == "ChannelSwitch"
					@hash_body[session_id][key] = false
				else
					@hash_body[session_id][key] = true
				end
			}
			body = bodyMaker(jason_input["time"]["sec"], session_id)
			return "success", body
		end
		return "success", []
	rescue => e
		return "internal error", e
	end

	###########################################
	##### EXTERNAL_INPUT時の入力のchecker #####
	###########################################

	def inputChecker_externalinput(hash_recipe, hash_mode, e_input)
	unless e_input.key?("navigator") && e_input.key?("mode") && e_input.key?("action")
		message =  "EXTERNAL_INPUT must have keys, 'navigator', 'mode' and 'action'."
		return false, message
	end
	unless e_input["action"].key?("name")
		message = "EXTERNAL_INPUT must have keys, 'action':{'name':...}."
		return false, message
	end
	case e_input["mode"]
	when "order"
		case e_input["action"]["name"]
		when "next"
		when "prev"
			if hash_mode["prev_substep"] == []
				message = "prev_substep is not exist"
				return false, message
			end
			array_size = hash_mode["prev_substep"].size - 1
			delete_list = []
			hash_mode["prev_substep"].reverse_each{|substep_id|
				if hash_mode["substep"][substep_id]["is_finished?"]
					break
				else
					delete_list.push(array_size)
					array_size = array_size - 1
				end
			}
			delete_list.each{|address|
				hash_mode["prev_substep"].delete_at(address)
			}
		when "jump"
			unless e_input["action"].key?("target")
				message = "When 'action':'name' is 'jump', EXTERNAL_INPUT must have key, 'target'."
				return false, message
			end
			substep_id = e_input["action"]["target"]
			unless hash_recipe["substep"].key?(substep_id)
				message = "#{substep_id} : No such substep in recipe.xml"
				return false, message
			end
			unless hash_mode["substep"][substep_id]["ABLE?"]
				message = "Can not jump to #{substep_id}, because #{substep_id} is not ABLE."
				return false, message
			end
		when "change"
			unless e_input["action"].key?("target")
				message = "When 'action':'name' is 'change', EXTERNAL_INPUT must have key, 'target'."
				return false, message
			end
			substep_id = e_input["action"]["target"]
			unless hash_recipe["substep"].key?(substep_id)
				message = "#{substep_id} : No such substep in recipe.xml"
				return false, message
			end
			unless hash_mode["substep"][substep_id]["ABLE?"]
				message = "Can not jump to #{substep_id}, because #{substep_id} is not ABLE."
				return false, message
			end
		when "check"
			unless e_input["action"].key?("target")
				message = "When 'action':'name' is 'check', EXTERNAL_INPUT must have key, 'target'."
				return false, message
			end
			id = e_input["action"]["target"]
			if hash_recipe["step"].key?(id)
				if hash_mode["step"][id]["is_finished?"]
					message = "#{id} is already finished."
					return false, message
				end
			elsif hash_recipe["substep"].key?(id)
				if hash_mode["substep"][id]["is_finished?"]
					message = "#{id} is already finished."
					return false, message
				end
			else
				message = "#{id} : No such step/substep in recipe.xml"
				return false, message
			end
		when "uncheck"
			unless e_input["action"].key?("target")
				message = "When 'action':'name' is 'uncheck', EXTERNAL_INPUT must have key, 'target'."
				return false, message
			end
			id = e_input["action"]["target"]
			if hash_recipe["step"].key?(id)
				unless hash_mode["step"][id]["is_finished?"]
					message = "#{id} is not finished."
					return false, message
				end
			elsif hash_recipe["substep"].key?(id)
				unless hash_mode["substep"][id]["is_finished?"]
					message = "#{id} is not finished."
					return false, message
				end
			else
				message = "#{id} : No such step/substep in recipe.xml"
				return false, message
			end
		else
			message = "#{e_input["action"]["name"]}: no such 'action' in 'mode' 'order'."
			return false, message
		end
	when "recognizer"
		unless e_input["action"].key?("object")
			message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'object' in 'action'."
			return false, message
		end
		unless e_input["action"]["object"].key?("name")
			message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'name' in 'object'."
			return false, message
		end
		unless e_input["action"]["object"].key?("class")
			message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'class' in 'object'."
			return false, message
		end
		unless e_input["action"]["object"]["class"] == "food" || e_input["action"]["object"]["class"] == "utensil" || e_input["action"]["object"]["class"] == "seasoning"
			message = "e_input['action']['object']['class'] must be 'food', 'utensil' or 'seasoning'."
			return false, message
		end
		case e_input["action"]["name"]
		when "put"
			unless hash_mode["taken"][e_input["action"]["object"]["class"]].include?(e_input["action"]["object"]["name"])
				message = "#{e_input["action"]["object"]["name"]} : System user does not take such object."
				return false, message
			end
		when "taken"
#			event = "taken_" + e_input["action"]["object"]["class"] + "_" + e_input["action"]["object"]["name"]
#			unless hash_recipe["event"].key?(event)
#				message = "#{event} : No such event in recipe."
#				return false, message
#			end
		else
			message = "#{e_input["action"]["name"]}: no such 'action' in 'mode' 'recognizer'"
			return false, message
		end
	else
		message = "#{e_input["mode"]}: no such 'mode'"
		return false, message
	end
	return true, ""
end

	#####################################################
	##### EXTERNAL_INPUT時の，次のsubstepを探索する #####
	#####################################################

	def searchNextSubstep(hash_recipe, hash_mode, object)
		explicitly_substep_array = []
		probably_substep_array = []
		rank = []
		hash_recipe["substep"].each{|substep_id, value|
			level = "recommend"
			#p "substep id : #{substep_id}"
			#p "substep is able? : #{hash_mode["substep"][substep_id]["ABLE?"]}"
			#p "substep is finished? : #{hash_mode["substep"][substep_id]["is_finished?"]}"
			#p "substep can be searched? : #{hash_mode["substep"][substep_id]["can_be_searched?"]}"
			if hash_mode["substep"][substep_id]["can_be_searched?"]
				point = 0
				mismatch = 0
				hash_mode["taken"]["food"].each{|key, value|
					if hash_recipe["substep"][substep_id]["vote"].key?(key)
						point = point + hash_recipe["substep"][substep_id]["vote"][key]
					else
						mismatch = mismatch + 1
					end
				}
				hash_mode["taken"]["seasoning"].each{|key, value|
					if hash_recipe["substep"][substep_id]["vote"].key?(key)
						point = point + hash_recipe["substep"][substep_id]["vote"][key]
					else
						mismatch = mismatch + 1
					end
				}
				hash_mode["taken"]["utensil"].each{|key, value|
					if hash_recipe["substep"][substep_id]["vote"].key?(key)
						point = point + hash_recipe["substep"][substep_id]["vote"][key]
					else
						mismatch = mismatch + 1
					end
				}
				if point > 100
					point = 100
				end
				point = point - (mismatch * 4)
				rank.push([point, substep_id])
			end
		}
		rank.sort!{|v1, v2|
			v2[0] <=> v1[0]
		}
		p rank
		i = 0
		highest_point = -100
		highest_substep = []
		rank.each{|point, substep_id|
			next if hash_mode["substep"][substep_id]["is_finished?"]
			if point > highest_point
				highest_point = point
				highest_substep.push(substep_id)
			end
		}
		if highest_point > 90
			# ほとんど一致
			next_substep = hash_recipe["substep"][hash_mode["current_substep"]]["next_substep"]
			if highest_substep.include?(next_substep)
				return next_substep, "explicitly"
			elsif highest_substep.include?(hash_mode["current_substep"])
				return hash_mode["current_substep"], "explicitly"
			else
				current_step = hash_mode["current_step"]
				highest_substep.each{|substep_id|
				step_id = hash_recipe["substep"][substep_id]["parent_step"]
				if step_id == current_step
					return substep_id, "explicitly"
				end
			}
			end
			return highest_substep[0],"explicitly"
		elsif highest_point > 70
			# 食材は一致している．
			next_substep = hash_recipe["substep"][hash_mode["current_substep"]]["next_substep"]
			if highest_substep.include?(next_substep) && (hash_mode["current_estimation_level"] == "explicitly" || hash_mode["current_estimation_level"] == "probably")
				return next_substep, "explicitly"
			end
			current_step = hash_recipe["substep"][hash_mode["current_substep"]]["parent_step"]
			highest_substep.each{|substep_id|
				if hash_mode["substep"][substep_id]["is_finished?"]
					next
				end
				if substep_id == hash_mode["current_substep"]
					next
				end
				next_step = hash_recipe["substep"][substep_id]["parent_step"]
				flag = false
				hash_recipe["step"][next_step]["parent"].each{|parent|
					if parent == current_step
						flag = true
					elsif hash_mode["step"][parent]["is_finished?"]
						flag = true
					else
						flag = false
						break
					end
				}
				if flag == true
					return substep_id, "explicitly"
				end
			}
			if highest_substep.include?(hash_mode["current_substep"])
				return hash_mode["current_substep"], "explicitly"
			end
			return highest_substep[0], "probably"
		elsif highest_point > 20
			# なにか物体が一致している
		end
		rank.each{|point, substep_id|
			# 終了済みのsubstepを提示
			if point > 90
				return substep_id, "explicitly"
			end
		}
		return nil, nil
	end

	def searchPlayMedia(hash_recipe, hash_mode, action)
		action_string = nil
		media = ["audio", "video", "notification"]
		if action["name"] == "put"
			# actionがputのときは，特別にputされたobjectとメディアのrefを比較して判断
			media.each{|media_name|
				hash_recipe[media_name].each{|media_id, value|
					value["trigger"].each{|trigger|
						trigger["ref"]["put"][action["object"]["class"]].each{|ref|
							if ref == action["object"]["name"]
								return media_id, trigger["timing"]
							end
						}
					}
				}
			}
		end
		# takenリストと比較して判断
		media.each{|media_name|
			hash_recipe[media_name].each{|media_id, value|
				value["trigger"].each{|trigger|
					flag = false
					trigger["ref"]["taken"]["food"].each{|ref|
						unless hash_mode["taken"]["food"].key?(ref)
							flag = false
							break
						end
						flag = true
					}
					next unless flag
					trigger["ref"]["taken"]["seasoning"].each{|ref|
						unless hash_mode["taken"]["seasoning"].key?(ref)
							flag = false
							break
						end
						flag = true
					}
					next unless flag
					trigger["ref"]["taken"]["utensil"].each{|ref|
						unless hash_mode["taken"]["utensil"].key?(ref)
							flag = false
							break
						end
						flag = true
					}
					if flag
						return media_id, trigger["timing"]
					end
				}
			}
		}
		return nil, nil
	end

	def putObject_relate2Current?(hash_recipe, current_substep, put_object)
		hash_recipe["substep"][current_substep]["trigger"].each{|trigger|
			if trigger["ref"]["taken"][put_object["class"]].include?(put_object["name"])
				return true
			elsif trigger["ref"]["put"][put_object["class"]].include?(put_object["name"])
				return true
			end
		}
		return false
	end

	def currentSubstep_isFinished?(hash_recipe, current_substep, object)
		hash_recipe["substep"][current_substep]["trigger"].each{|trigger|
			timing = trigger["timing"]
			if timing == "end"
				trigger["ref"]["put"][object["class"]].each{|ref|
					if ref == object["name"]
						return true
					end
				}
			end
		}
		return false
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, e_input, session_id)
		next_step = nil
		next_substep = nil
		case e_input["mode"]
		when "order"
			if e_input["action"]["name"] == "next"
				@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id] = updateABLE(@hash_recipe[session_id], @hash_mode[session_id])
				@hash_mode[session_id] = go2next(@hash_recipe[session_id], @hash_mode[session_id])
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			elsif e_input["action"]["name"] == "prev"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id] = prev(@hash_recipe[session_id], @hash_mode[session_id])
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			elsif e_input["action"]["name"] == "jump"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], target)
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", target)
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			elsif e_input["action"]["name"] == "change"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
				target = e_input["action"]["target"]
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], target)
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", target)
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			elsif e_input["action"]["name"] == "check"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = check(@hash_recipe[session_id], @hash_mode[session_id], target)
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			elsif e_input["action"]["name"] == "uncheck"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = uncheck(@hash_recipe[session_id], @hash_mode[session_id], target)
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			end
			@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
			return true
		when "recognizer"
			if e_input["action"]["name"] == "put"
				released(time, e_input, session_id)
				return true
			elsif e_input["action"]["name"] == "taken"
				grabbed(time, e_input, session_id)
				return true
			else
				return false
			end
		end
	end

	def released(time, e_input, session_id)
		# 初めに，再生/停止すべきメディアの探索（foodのputも用いる）
		media_id, timing = searchPlayMedia(@hash_recipe[session_id], @hash_mode[session_id], e_input["action"])
		unless media_id == nil
			if timing == "start"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], [""], "START", media_id)
			elsif timing == "end"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], [""], "STOP", media_id)
			end
		end
		#p "playMedia in put : #{media_id}"
		# put時間とtaken時間の取得
		put_time = (time["sec"].to_s + time["usec"].to_s).to_i
		taken_time = @hash_mode[session_id]["taken"][e_input["action"]["object"]["class"]][e_input["action"]["object"]["name"]]
		@hash_mode[session_id]["prev_action"] = "put"
		@hash_mode[session_id]["prev_action_time"] = put_time
		#p "put time in 'put' : #{put_time}"
		#p "taken time in 'put' : #{taken_time}"
		# taken listからput objectのdelete
		@hash_mode[session_id]["taken"][e_input["action"]["object"]["class"]].delete(e_input["action"]["object"]["name"])
		# estimation levelに合わせて処理を変更
		#p "estimation level in 'put' : #{@hash_mode[session_id]["current_estimation_level"]}"
		case @hash_mode[session_id]["current_estimation_level"]
		when "recommend"
			# 特に何もしない
		when "probably", "explicitly"
			# put objectがcurrent substepに関係あるか調べる
			if putObject_relate2Current?(@hash_recipe[session_id], @hash_mode[session_id]["current_substep"], e_input["action"]["object"])
				#p "put object relates to current."
				#p "put time - taken time = #{put_time - taken_time}"
				# 経過時間を用いた移動判定（注意！！混合は移動とはしたくない！！）
				if (put_time - taken_time) > 1000000
					#p "put object is not moved, maybe cooked."
					# 移動でなかった場合，終了判定（foodは用いない→トリガーがfoodだけのときは混合なので使うことにする）
					#if e_input["action"]["object"]["class"] == "seasoning" || e_input["action"]["object"]["class"] == "utensil"
					# currentのsubstepのトリガーがfoodひとつのみならば，終了判定に突入できる
					if e_input["action"]["object"]["class"] == "food"
						flag = false
						@hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["trigger"].each{|trigger|
							if trigger["ref"]["taken"]["utensil"].empty? && trigger["ref"]["taken"]["seasoning"].empty?
								flag = true
								break
							end
						}
						unless flag
							# 終了判定しない
							if media_id == nil
								return false
							end
							@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
							return true
						end
					end
					# seasoningまたはutensilを用いて終了判定
					if currentSubstep_isFinished?(@hash_recipe[session_id], @hash_mode[session_id]["current_substep"], e_input["action"]["object"])
						#p "current substep is finished by putting object #{e_input["action"]["object"]["name"]}."
						# estimation levelがexplicitlyのとき，current substepをfinishする
						# level = probablyで終了判定trueの場合，食材をtakenされていない可能性が高い
						# taken listに何も含まれなかった場合は，is_finished=trueにし，taken listに何か含まれている場合は移動とみなす
						# waterがprobably時にputされても無視する．
						# seasoningがputされたときは，終了判定したいが，そもそもexplicitlyになっているはずなので問題ない
						if @hash_mode[session_id]["current_estimation_level"] == "explicitly" || @hash_mode[session_id]["taken"] == {"food"=>{}, "seasoning"=>{}, "utensil"=>{}}
							if (@hash_mode[session_id]["current_estimation_level"] != "probably" || e_input["action"]["object"]["name"] != "water")
								# prev_substepの更新
								unless @hash_mode[session_id]["prev_substep"].last == @hash_mode[session_id]["currnet_substep"]
									@hash_mode[session_id]["prev_substep"].push(@hash_mode[session_id]["currnet_substep"])
								end
								# recommend next substep
								if @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["Extrafood_mixing"]
									@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"], true)
								else
									@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
								end
								@hash_mode[session_id] = updateABLE(@hash_recipe[session_id], @hash_mode[session_id])
								# current substepをis_finished=trueにした場合は，next substepを提示した方が自然
								@hash_mode[session_id] = go2next(@hash_recipe[session_id], @hash_mode[session_id])
								# メディアは再生しない
								# estimation levelの更新
								@hash_mode[session_id]["prev_estimation_level"] = @hash_mode[session_id]["current_estimation_level"]
								@hash_mode[session_id]["current_estimation_level"] = "recommend"
								@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
								return true
							end
						end
					else
						#p "current substep is not finished."
						# current substepが終了ではなかった場合，substepでは何もしない
						# taken_listを参照してsubstepを探索しても，currentなsubstepと同じ値が返ってくるはず
						# levelもprobablyから変更はないはず．
						if media_id == nil
							return false
						end
						@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
						return true
					end
					#else
					#p "we don't validate finished function because put object is food."
					# foodのputは終了判定に関係ないので，substepでは何もしない
					#	if media_id == nil
					#		return false
					#	end
					#	@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time)
					#	return true
					#end
				else
					# 把持->解放（現在）が虚偽的動作だったので，状態を二つ戻す
					# 一つ前のmode（虚偽的把持）をsubmodeに移し，その前のmodeを読み込む
					array_mode = Dir::entries("records/#{session_id}/mode").sort
					array_recipe = Dir::entries("records/#{session_id}/recipe").sort
					`mv records/#{session_id}/mode/#{array_mode[array_mode.size-2]} records/#{session_id}/mode/submode/`
					open("records/#{session_id}/mode/#{array_mode[array_mode.size-3]}", "r"){|io|
						@hash_mode[session_id] = JSON.load(io)
					}
					`mv records/#{session_id}/mode/#{array_mode[array_mode.size-3]} records/#{session_id}/mode/submode/`
					`mv records/#{session_id}/recipe/#{array_recipe[array_recipe.size-2]} records/#{session_id}/recipe/subrecipe/`
					open("records/#{session_id}/recipe/#{array_recipe[array_recipe.size-3]}", "r"){|io|
						@hash_recipe[session_id] = JSON.load(io)
					}
					`mv records/#{session_id}/recipe/#{array_recipe[array_recipe.size-3]} records/#{session_id}/recipe/subrecipe/`
					return true
				end
				#p "put object is only moved."
				# 移動であった場合，current substepのnext substepをsearchSubstepの対象から外す
				next_substep = @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["next_substep"]
				if next_substep == nil
					@hash_recipe[session_id]["step"].each{|step_id, value|
						value["parent"].each{|parent|
							if parent == @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["parent_step"]
								@hash_mode[session_id]["substep"][@hash_recipe[session_id]["step"][step_id]["substep"][0]]["can_be_searched?"] = false
							end
						}
					}
				else
					@hash_mode[session_id]["substep"][next_substep]["can_be_searched?"] = false
				end
				# estimation_levelがexplicitlyであった場合，can_be_searchedがfalseにされたsubstepが存在するので，trueに変更する
				if @hash_mode[session_id]["current_estimation_level"] == "explicitly"
					@hash_recipe[session_id]["step"][@hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["parent_step"]]["parent"].each{|parent|
						@hash_recipe[session_id]["step"][parent]["substep"].each{|substep|
							@hash_mode[session_id]["substep"][substep]["can_be_searched?"] = true
						}
					}
				end
				# 移動であった場合，再度ユーザの挙動に合ったsubstepを探す（probablyかexplicitlyになる）．
				# 移動だったsubstep(prev)はpushしない
				next_substep = nil
				next_substep, level = searchNextSubstep(@hash_recipe[session_id], @hash_mode[session_id], e_input["action"]["object"])
				#p "next substep is #{next_substep}"
				# 見つからなければnext（recommendになる）
				if next_substep == nil
					#p "next substep is nil, so use next function(recommend)."
					# メディアを再生していれば停止しておく
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
					@hash_mode[session_id] = updateABLE(@hash_recipe[session_id], @hash_mode[session_id])
					@hash_mode[session_id] = go2next(@hash_recipe[session_id], @hash_mode[session_id])
					# estimation levelの更新．移動であったsubstepのestimationを上書きする．
					@hash_mode[session_id]["current_estimation_level"] = "recommend"
					@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
					return true
				end
				# estimation levelの更新．移動であったsubstepのestimationを上書きする．
				@hash_mode[session_id]["current_estimation_level"] = level
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
				# 直前のsubstepはただの移動だったので，finishにしてはいけない=>changeしか使わない
				if @hash_mode[session_id]["current_estimation_level"] == "probably"
					# can_be_searchedの更新
					if @hash_recipe[session_id]["substep"][next_substep]["next_substep"] == nil
						@hash_recipe[session_id]["step"].each{|step_id, value|
							flag = false
							value["parent"].each{|parent|
								if parent == @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
									flag = true
								elsif @hash_mode[session_id]["step"][step_id]["is_finished?"]
									flag = true
								else
									flag = false
									break
								end
							}
							if flag == true
								@hash_mode[session_id]["substep"][@hash_recipe[session_id]["step"][step_id]["substep"][0]]["can_be_searched?"] = true
							end
						}
					else
						@hash_mode[session_id]["substep"][@hash_recipe[session_id]["substep"][next_substep]["next_substep"]]["can_be_searched?"] = true
					end
					#p "estimation level is probably, so do not play media."
					# next_substepがis_finished=trueならuncheckすべきだが，probablyではそのようなケースは発生しない．
					@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
				elsif @hash_mode[session_id]["current_estimation_level"] == "explicitly"
					# can_be_searchedの更新
					if @hash_recipe[session_id]["substep"][next_substep]["next_substep"] == nil
						@hash_recipe[session_id]["step"].each{|step_id, value|
							flag = false
							value["parent"].each{|parent|
								if parent == @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
									flag = true
								elsif @hash_mode[session_id]["step"][step_id]["is_finished?"]
									flag = true
								else
									flag = false
									break
								end
							}
							if flag == true
								@hash_mode[session_id]["substep"][@hash_recipe[session_id]["step"][step_id]["substep"][0]]["can_be_searched?"] = true
							end
						}
					else
						@hash_mode[session_id]["substep"][@hash_recipe[session_id]["substep"][next_substep]["next_substep"]]["can_be_searched?"] = true
					end
					#p "estimation level is explicitly, so play media."
					# levelがexplicitlyのときはprev_substepをis_finished?=trueにするので，substepを念のために並べ替える
					prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
					unless prev_substep == nil
						unless @hash_mode[session_id]["substep"][prev_substep]["is_finished?"]
							@hash_recipe[session_id] = sortSubstep(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
							prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
						end
						# next_substepがis_finished=trueならuncheckする
						if @hash_mode[session_id]["substep"][next_substep]["is_finished?"]
							@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
						end
						unless @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"]
							@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], prev_substep)
						end
					end
					@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", next_substep)
					# can_be_searchedの更新
					# parent stepのsubstep群をcan_be_searched=falseにする
					next_step = @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
					#p "next step : #{next_step}"
					@hash_recipe[session_id]["step"][next_step]["parent"].each{|step_id|
						#p "parent step : #{step_id}"
						@hash_recipe[session_id]["step"][step_id]["substep"].each{|substep_id|
							@hash_mode[session_id]["substep"][substep_id]["can_be_searched?"] = false
						}
					}
				end
				@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
				return true
			end
			#p "put object does not relate to current."
			# put objectがcurrent substepに関係なければ，特に何もしない
		end
		# ここにくる場合，substep関係では何もしないということ
		if media_id == nil
			return false
		end
		@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
		return true
	end

	def grabbed(time, e_input, session_id)
		# takenされた物体のnameとtimeを取得
		taken_time = (time["sec"].to_s + time["usec"].to_s).to_i
		@hash_mode[session_id]["taken"][e_input["action"]["object"]["class"]][e_input["action"]["object"]["name"]] = taken_time
		if @hash_mode[session_id]["prev_action"] == "taken" && (taken_time - @hash_mode[session_id]["prev_action_time"]) < 500000
			# 把持->把持（現在）が高速で行われたので，同時に把持されたと解釈．
			# 現在のtaken_listは変更せずに，他の状態をひとつ前に戻し，推定のやり直し．
			current_taken_list = @hash_mode[session_id]["taken"]
			array_mode = Dir::entries("records/#{session_id}/mode").sort
			array_recipe = Dir::entries("records/#{session_id}/recipe").sort
			`mv records/#{session_id}/mode/#{array_mode[array_mode.size-2]} records/#{session_id}/mode/submode/`
			open("records/#{session_id}/mode/#{array_mode[array_mode.size-3]}", "r"){|io|
				@hash_mode[session_id] = JSON.load(io)
			}
			`mv records/#{session_id}/mode/#{array_mode[array_mode.size-3]} records/#{session_id}/mode/submode/`
			`mv records/#{session_id}/recipe/#{array_recipe[array_recipe.size-2]} records/#{session_id}/recipe/subrecipe/`
			open("records/#{session_id}/recipe/#{array_recipe[array_recipe.size-3]}", "r"){|io|
				@hash_recipe[session_id] = JSON.load(io)
			}
			`mv records/#{session_id}/recipe/#{array_recipe[array_recipe.size-3]} records/#{session_id}/recipe/subrecipe/`
			@hash_mode[session_id]["taken"] = current_taken_list
			# 以降では直前の動作の時間を比較に使いたい
			taken_time = @hash_mode[session_id]["prev_action_time"]
		end
		@hash_mode[session_id]["prev_action"] = "taken"
		@hash_mode[session_id]["prev_action_time"] = taken_time
		# メディアの探索
		media_id, timing = searchPlayMedia(@hash_recipe[session_id], @hash_mode[session_id], e_input["action"])
		unless media_id == nil
			if timing == "start"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], [""], "START", media_id)
			elsif timing == "end"
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], [""], "STOP", media_id)
			end
		end
		# taken_listと比較してsubstepを探索
		next_substep, level = searchNextSubstep(@hash_recipe[session_id], @hash_mode[session_id], e_input["action"]["object"])
		if @hash_mode[session_id]["current_substep"] == next_substep
			# can_be_searchedの更新
			if @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["next_substep"] == nil
				@hash_recipe[session_id]["step"].each{|step_id, value|
					flag = false
					value["parent"].each{|parent|
						if parent == @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
							flag = true
						elsif @hash_mode[session_id]["step"][step_id]["is_finished?"]
							flag = true
						else
							flag = false
							break
						end
					}
					if flag == true
						# ["substep"][0]と["substep"][1]が味付け工程だった場合，どちらもtrueにすべきでは？？
						@hash_mode[session_id]["substep"][@hash_recipe[session_id]["step"][step_id]["substep"][0]]["can_be_searched?"] = true
					end
				}
			else
				# [next_substep]["next_substep"]とそのさらにnext_substepが味付け工程だった場合，どちらもtrueにすべきでは？
				@hash_mode[session_id]["substep"][@hash_recipe[session_id]["substep"][next_substep]["next_substep"]]["can_be_searched?"] = true
			end
			# estimation levelの更新．substepに変化はないので，currentのestimation_levelを更新する
			@hash_mode[session_id]["current_estimation_level"] = level
			if @hash_mode[session_id]["current_estimation_level"] == "explicitly"
				# explicitlyの際は，念のために一つ前のsubstepはfinishedにしておく．（finishedでないと本来は取り組めないはず）
				prev_substep = @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["prev_substep"]
				# substepの並べ替え
				unless prev_substep == nil
					# 一つ前のsubstepがfinished出ない場合，味付け工程の影響で順番が入れ替わっている可能性がある．これに対処する．
					unless @hash_mode[session_id]["substep"][prev_substep]["is_finished?"]
						@hash_recipe[session_id] = sortSubstep(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
						prev_substep = @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["prev_substep"]
					end
					unless @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["Extrafood_mixing"]
						@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], prev_substep)
					end
				end
				@hash_mode[session_id] = updateABLE(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_step"], @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", @hash_mode[session_id]["current_substep"])
				# can_be_searchedの更新
				# current stepのparent stepにおけるsubstep群を，can_be_searched=falseにする
				next_step = @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
				@hash_recipe[session_id]["step"][next_step]["parent"].each{|step_id|
					@hash_recipe[session_id]["step"][step_id]["substep"].each{|substep_id|
						@hash_mode[session_id]["substep"][substep_id]["can_be_searched?"] = false
					}
				}
			else
				# levelはprobablyなので，finishedにしたり，メディアを再生したりしない．
			end
			@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
			return true
		end
		unless next_substep == nil
			# next substepはcurrent substepと異なる．
			# estimation levelの更新．substepに変化があるので，prevも更新
			@hash_mode[session_id]["prev_estimation_level"] = @hash_mode[session_id]["current_estimation_level"]
			# can_be_searchedの更新
			if @hash_recipe[session_id]["substep"][next_substep]["next_substep"] == nil
				@hash_recipe[session_id]["step"].each{|step_id, value|
					flag = false
					value["parent"].each{|parent|
						if parent == @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
							flag = true
						elsif @hash_mode[session_id]["step"][step_id]["is_finished?"]
							flag = true
						else
							flag = false
							break
						end
					}
					if flag == true
						@hash_mode[session_id]["substep"][@hash_recipe[session_id]["step"][step_id]["substep"][0]]["can_be_searched?"] = true
					end
				}
			elsif @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"] == false
				@hash_mode[session_id]["substep"][@hash_recipe[session_id]["substep"][next_substep]["next_substep"]]["can_be_searched?"] = true
			end
			# current levelの更新
			@hash_mode[session_id]["current_estimation_level"] = level
			if @hash_mode[session_id]["current_estimation_level"] == "explicitly"
				if @hash_mode[session_id]["prev_estimation_level"] == "explicitly"
					if @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["Extrafood_mixing"]
						@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"], true)
					else
						@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
					end
					unless @hash_mode[session_id]["prev_substep"].last == @hash_mode[session_id]["current_substep"]
						@hash_mode[session_id]["prev_substep"].push(@hash_mode[session_id]["current_substep"])
					end
					# 次のsubstepの一つ前のsubstepは念のためにfinishedにしておく
					prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
					# substepの並べ替え
					if prev_substep == nil
						# next_substepがis_finished=trueならばuncheckする
						if @hash_mode[session_id]["substep"][next_substep]["is_finished?"]
							@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
						end
						unless @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"]
							@hash_recipe[session_id]["step"][@hash_recipe[session_id]["substep"][next_substep]["parent_step"]]["parent"].each{|parent|
								@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], parent)
							}
						end
					else
						unless @hash_mode[session_id]["substep"][prev_substep]["is_finished?"]
							@hash_recipe[session_id] = sortSubstep(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
							prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
						end
						# next_substepがis_finished=trueならばuncheckする
						if @hash_mode[session_id]["substep"][next_substep]["is_finished?"]
							@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
						end
						unless @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"]
							@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], prev_substep)
						end
					end
					@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", next_substep)
					# can_be_searchedの更新
					# parent stepのsubstep群をcan_be_searched=falseにする
					next_step = @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
					#p "next step : #{next_step}"
					@hash_recipe[session_id]["step"][next_step]["parent"].each{|step_id|
						#p "parent_step : #{step_id}"
						@hash_recipe[session_id]["step"][step_id]["substep"].each{|substep_id|
							@hash_mode[session_id]["substep"][substep_id]["can_be_searched?"] = false
						}
					}
				else
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
					unless @hash_mode[session_id]["prev_substep"].last == @hash_mode[session_id]["current_substep"]
						@hash_mode[session_id]["prev_substep"].push(@hash_mode[session_id]["current_substep"])
					end
					# 次のsubstepのprev substepは念のためにfinishedにしておく
					prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
					# substepの並べ替え
					if prev_substep == nil
						# next_substepがis_finished=trueならばuncheckする
						if @hash_mode[session_id]["substep"][next_substep]["is_finished?"]
							@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
						end
						unless @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"]
							@hash_recipe[session_id]["step"][@hash_recipe[session_id]["substep"][next_substep]["parent_step"]]["parent"].each{|parent|
								@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], parent)
							}
						end
					else
						unless @hash_mode[session_id]["substep"][prev_substep]["is_finished?"]
							@hash_recipe[session_id] = sortSubstep(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
							prev_substep = @hash_recipe[session_id]["substep"][next_substep]["prev_substep"]
						end
						# next_substepがis_finished=trueならばuncheckする
						if @hash_mode[session_id]["substep"][next_substep]["is_finished?"]
							@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
						end
						unless @hash_recipe[session_id]["substep"][next_substep]["Extrafood_mixing"]
							@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], prev_substep)
						end
					end
					@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", next_substep)
					# can_be_searchedの更新
					# parent stepのsubstep群をcan_be_searched=falseにする
					next_step = @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
					#p "next_step : #{next_step}"
					@hash_recipe[session_id]["step"][next_step]["parent"].each{|step_id|
						#p "parent step : #{step_id}"
						@hash_recipe[session_id]["step"][step_id]["substep"].each{|substep_id|
							@hash_mode[session_id]["substep"][substep_id]["can_be_searched?"] = false
						}
					}
				end
			else
				# current level == probably
				if @hash_mode[session_id]["prev_estimation_level"] == "explicitly"
					if @hash_recipe[session_id]["substep"][@hash_mode[session_id]["current_substep"]]["Extrafood_mixing"]
						@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"], true)
					else
						@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], @hash_mode[session_id]["current_substep"])
					end
				else
					# prev level == probably
					@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
				end
				unless @hash_mode[session_id]["prev_substep"].last == @hash_mode[session_id]["current_substep"]
					@hash_mode[session_id]["prev_substep"].push(@hash_mode[session_id]["current_substep"])
				end
				# current levelがpobablyなのでメディアの再生なし．一つ前のsubstepのfinishedもなし．
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep)
			end
			@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
			return true
		end
		# next_substep==nilならば，substepに対しては何もしない
		if media_id == nil
			return false
		end
		@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time["sec"])
		return true
	end
end
