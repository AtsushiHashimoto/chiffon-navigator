#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase

	private

	########################################################
	##### situationに合わせて動作する7メソッドの内，   #####
	##### navigatorの仕様に合わせて変更すべき3メソッド #####
	########################################################

	def navi_menu(jason_input, session_id)
		body = []

		id = jason_input["operation_contents"]
		if @hash_recipe[session_id]["step"].key?(id)
			unless @hash_mode[session_id]["step"][id]["CURRENT?"]
				@hash_mode[session_id]["step"][id]["open?"] = (not @hash_mode[session_id]["step"][id]["open?"])
			end
		elsif @hash_recipe[session_id]["substep"].key?(id)
			if @hash_mode[session_id]["substep"][id]["ABLE?"]
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], id, "initialize", false)
			end
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is NAVI_MENU."
			logger()
			return "invalid params", body
		end

		@hash_body[session_id].each{|key, value|
			if key == "ChannelSwitch"
				@hash_body[session_id][key] = false
			else
				@hash_body[session_id][key] = true
			end
		}
		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	def external_input(jason_input, session_id)
		body = []
		# EXTERNALINPUTのチェック
		e_input = nil
		p jason_input["operation_contents"]
		begin
			e_input = JSON.load(jason_input["operation_contents"])
		rescue
			p "EXTERNAL_INPUT is wrong."
			p "EXTERNAL_INPUT must be {\"navigator\":hoge,\"mode\":\"hogehoge\",...}"
			logger()
			return "invalid params", body
		end
		# inputのチェック
		result, message = inputChecker_externalinput(@hash_recipe[session_id], @hash_mode[session_id], e_input)
		unless result
			p "EXTERNAL_INPUT is wrong."
			p message
			logger()
			return "invalid params", body
		end
		# modeの修正
		modeUpdate_externalinput(jason_input["time"]["sec"], e_input, session_id)

		@hash_body[session_id].each{|key, value|
			if key == "ChannelSwitch"
				@hash_body[session_id][key] = false
			else
				@hash_body[session_id][key] = true
			end
		}
		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)

		return "success", body
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
		case e_input["action"]["name"]
		when "put"
			unless e_input["action"].key?("tool")
				message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'tool'."
				return false, message
			end
			unless hash_mode["taken"].include?(e_input["action"]["tool"])
				message = "#{e_input["action"]["tool"]} : System user does not take such tool."
				return false, message
			end
		when "taken"
			unless e_input["action"].key?("tool")
				message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'tool'."
				return false, message
			end
			if hash_mode["taken"].size > 1
				message = "System user may not be able to take more than 2 tool."
				return false, message
			end
			unless hash_recipe["object"].key?(e_input["action"]["tool"]) || hash_recipe["event"].key?(e_input["action"]["tool"])
				message = "#{e_input["action"]["tool"]} : No such tool in recipe."
				return false, message
			end
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

	def searchNextSubstep(hash_recipe, hash_mode)
		hash_recipe["substep"].each{|substep_id, value|
			if hash_mode["substep"][substep_id]["ABLE?"]
				value["trigger"].each{|value2|
					flag = -1
					array_trigger = value2[1]
					array_trigger.each{|ref|
						if hash_mode["taken"].include?(ref)
							flag = 1
						else
							flag = 0
							break
						end
					}
					if flag == 1
						return substep_id
					end
				}
			end
		}
		return nil
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, e_input, session_id)
		next_step = nil
		next_substep = nil
		case e_input["mode"]
		when "order"
			if e_input["action"]["name"] == "next"
				@hash_mode[session_id] = go2next(@hash_recipe[session_id], @hash_mode[session_id])
			elsif e_input["action"]["name"] == "prev"
				@hash_mode[session_id] = prev(@hash_recipe[session_id], @hash_mode[session_id])
			elsif e_input["action"]["name"] == "jump"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], target, "finish", false)
			elsif e_input["action"]["name"] == "change"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], target, "initialize", false)
			elsif e_input["action"]["name"] == "check"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = check(@hash_recipe[session_id], @hash_mode[session_id], target)
			elsif e_input["action"]["name"] == "uncheck"
				target = e_input["action"]["target"]
				@hash_mode[session_id] = uncheck(@hash_recipe[session_id], @hash_mode[session_id], target)
			end
		when "recognizer"
			if e_input["action"]["name"] == "put"
				@hash_mode[session_id]["taken"].delete_if{|x| x == e_input["action"]["tool"]}
			elsif e_input["action"]["name"] == "taken"
				@hash_mode[session_id]["taken"].push(e_input["action"]["tool"])
			end

			next_substep = searchNextSubstep(@hash_recipe[session_id], @hash_mode[session_id])
			current_substep = @hash_mode[session_id]["current_substep"]
			if current_substep == next_substep
				next_substep = nil
			end
			unless next_substep == nil
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], next_substep, "FINISH")
			end
		end
		if next_substep != nil
			next_step = @hash_recipe[session_id]["substep"][next_substep]["parent_step"]
			@hash_mode[session_id] = updateABLE(@hash_recipe[session_id], @hash_mode[session_id], next_step, next_substep)
		end
		@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], time)
	end

	###################################################
	##### NAVI_MENU用の特別なnaviDrawを再定義する #####
	###################################################

		# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw(session_id)
		# sorted_stepの順に表示させる．
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe[session_id]["sorted_step"].each{|v|
			id = v[1]
			visual_step = nil
			is_finished = -1
			is_open = -1
			if @hash_mode[session_id]["step"][id]["CURRENT?"]
				visual_step = "CURRENT"
			elsif @hash_mode[session_id]["step"][id]["ABLE?"]
				visual_step = "ABLE"
			else
				visual_step = "OTHERS"
			end
			if @hash_mode[session_id]["step"][id]["is_finished?"]
				is_finished = 1
			else
				is_finished = 0
			end
			if @hash_mode[session_id]["step"][id]["open?"]
				is_open = 1
			else
				is_open = 0
			end
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>is_finished, "is_open"=>is_open})
			# CURRENTなstepの場合，substepも表示させる．
			if @hash_mode[session_id]["step"][id]["open?"]
				@hash_recipe[session_id]["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode[session_id]["substep"][id]["CURRENT?"]
						visual_substep = "CURRENT"
					elsif @hash_mode[session_id]["substep"][id]["ABLE?"]
						visual_substep = "ABLE"
					else
						visual_substep = "OTHERS"
					end
					if @hash_mode[session_id]["substep"][id]["is_finished?"]
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>0})
					end
				}
			end
		}
		return orders
	end

end
