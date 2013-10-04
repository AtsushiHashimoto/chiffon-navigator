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

	def navi_menu(jason_input)
		body = []
		unless @hash_mode["display"] == "GUIDE"
			p "invalid params : #{@hash_mode["display"]} is displayed now."
			logger()
			return "invalid params", body
		end

		id = jason_input["operation_contents"]
		unless @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
			p "invalid params : jason_input['operation_contents'] is wrong when situation is NAVI_MENU."
			logger()
			return "invalid params", body
		end
		# modeの修正
		modeUpdate_navimenu(jason_input["time"]["sec"], id)

		# DetailDraw：入力されたstepをCURRENTとして提示
		body.concat(detailDraw())
		# Play：不要．
		# Notify：不要．
		# Cancel：再生待ちコンテンツがあればキャンセル
		body.concat(cancel())
		# ChannelSwitch：不要
		# NaviDraw：適切にvisualを書き換えたものを提示
		body.concat(naviDraw())

		return "success", body
	rescue => e
		return "internal error", e
	end

	def external_input(jason_input)
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
		result, message = inputChecker_externalinput(@hash_recipe, @hash_mode, e_input)
		unless result
			p "EXTERNAL_INPUT is wrong."
			p message
			logger()
			return "invalid params", body
		end
		# modeの修正
		modeUpdate_externalinput(jason_input["time"]["sec"], e_input)

		# DetailDraw：調理者がとったものに合わせたsubstepのidを提示
		body.concat(detailDraw())
		# Play：substep内にコンテンツが存在すれば再生命令を送る
		body.concat(play(jason_input["time"]["sec"]))
		# Notify：substep内にコンテンツが存在すれば再生命令を送る
		body.concat(notify(jason_input["time"]["sec"]))
		# Cancel：再生待ちコンテンツがあればキャンセル
		body.concat(cancel())
		# ChannelSwitch：不要
		# NaviDraw：適切にvisualを書き換えたものを提示
		body.concat(naviDraw())

		return "success", body
	rescue => e
		return "internal error", e
	end

	###########################################
	##### EXTERNAL_INPUT時の入力のchecker #####
	###########################################

	def inputChecker_externalinput(hash_recipe, hash_mode, e_input)
	unless e_input.key?("navigator") && e_input.key?("mode")
		message =  "EXTERNAL_INPUT must have keys, 'navigator' and 'mode'."
		return false, message
	end
	case e_input["mode"]
	when "debug"
		unless e_input.key?("action")
			message = "When 'mode' is 'debug', EXTERNAL_INPUT must have key, 'action'."
			return false, message
		end
		unless e_input["action"] == "next" || e_input["action"] = "jump"
			message = "When 'mode' is 'debug', 'action' must be 'next' or 'jump'."
			return false, message
		end
		if e_input["action"] == "jump"
			unless e_input.key?("destination")
				message = "When 'action' is 'jump', EXTERNAL_INPUT must have key, 'destination'."
				return false, message
			end
			substep_id = e_input["destination"]
			unless hash_recipe["substep"].key?(substep_id)
				message = "#{substep_id} : No such substep in recipe.xml"
				return false, message
			end
			unless hash_mode["substep"][substep_id]["ABLE?"]
				message = "Can not jump to #{substep_id}, because #{substep_id} is not ABLE."
				return false, message
			end
		end
	when "recognizer"
		unless e_input.key?("tool") && e_input.key?("action")
			message = "When 'mode' is 'recognizer', EXTERNAL_INPUT must have keys, 'tool' and 'action'."
			return false, message
		end
		unless e_input["action"] == "taken" || e_input["action"] == "put"
			message = "When 'mode' is 'recognizer', 'action' must be 'taken' or 'put'."
			return false, message
		end
		if e_input["action"] == "taken" && hash_mode["taken"].size > 1
			message = "System user may not be able to take more than 2 tool."
			return false, message
		end
		if e_input["action"] == "taken" && (hash_recipe["object"].value?(e_input["tool"]) || hash_recipe["event"].value?(e_input["tool"]))
			message = "#{e_input["tool"]} : No such tool in recipe."
			return false, message
		end
		if e_input["action"] == "put" && !hash_mode["taken"].include?(e_input["tool"])
			message = "#{e_input["tool"]} : System user does not take such tool."
			return false, message
		end
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

	##########################################################
	##### modeのupdate処理が複雑な2メソッドのmodeUpdater #####
	##########################################################

	def modeUpdate_navimenu(time, id)
		if @hash_recipe["step"].key?(id)
			unless @hash_mode["step"][id]["CURRENT?"]
				if @hash_mode["step"][id]["open?"]
					@hash_mode["step"][id]["open?"] = false
				else
					@hash_mode["step"][id]["open?"] = true
				end
			end
		elsif @hash_recipe["substep"].key?(id)
			# substepがクリックされた場合のみ，detailDrawが変化するので，動画と音声を停止する．
			shown_substep = @hash_mode["shown"]
			# substepに含まれるaudio，videoは再生済み・再生中・再生待ち関わらずSTOPに．
			media = ["audio", "video"]
			media.each{|media_name|
				@hash_recipe["substep"][shown_substep][media_name].each{|media_id|
					if @hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
						@hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
			# クリックされたsubstepをshownにする
			@hash_mode["shown"] = id
		end
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, e_input)
		next_step = nil
		next_substep = nil
		case e_input["mode"]
		when "debug"
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			@hash_mode["substep"][current_substep]["CURRENT?"] = false
			@hash_mode["step"][current_step]["CURRENT?"] = false
			@hash_mode = check_isFinished(@hash_recipe, @hash_mode, current_substep)
			if e_input["action"] == "next"
				@hash_mode, next_step, next_substep = go2next(@hash_recipe, @hash_mode, current_step)
			elsif e_input["action"] == "jump"
				next_substep = e_input["destination"]
				next_step = @hash_recipe["substep"][next_substep]["parent_step"]
				@hash_mode = jump2substep(@hash_recipe, @hash_mode, next_step, next_substep)
			end
		when "recognizer"
			if e_input["action"] == "put"
				@hash_mode["taken"].delete_if{|x| x == e_input["tool"]}
			elsif e_input["action"] == "taken"
				@hash_mode["taken"].push(e_input["tool"])
			end

			next_substep = searchNextSubstep(@hash_recipe, @hash_mode)
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			if current_substep == next_substep
				next_substep = nil
			end
			unless next_substep == nil
				next_step = @hash_recipe["substep"][next_substep]["parent_step"]
				@hash_mode["step"][current_step]["CURRENT?"] = false
				@hash_mode["substep"][current_substep]["CURRENT?"] = false
				@hash_mode = check_isFinished(@hash_recipe, @hash_mode, current_substep)
				@hash_mode = jump2substep(@hash_recipe, @hash_mode, next_step, next_substep)
			end
		end
		p next_step
		p next_substep
		if next_step != nil && next_substep != nil
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, next_step, next_substep)
		end
		@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
	end

	###################################################
	##### NAVI_MENU用の特別なnaviDrawを再定義する #####
	###################################################

		# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw
		# sorted_stepの順に表示させる．
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			id = v[1]
			visual_step = nil
			is_finished = -1
			is_open = -1
			if @hash_mode["step"][id]["CURRENT?"]
				visual_step = "CURRENT"
			elsif @hash_mode["step"][id]["ABLE?"]
				visual_step = "ABLE"
			else
				visual_step = "OTHERS"
			end
			if @hash_mode["step"][id]["is_finished?"]
				is_finished = 1
			else
				is_finished = 0
			end
			if @hash_mode["step"][id]["open?"]
				is_open = 1
			else
				is_open = 0
			end
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>is_finished, "is_open"=>is_open})
			# CURRENTなstepの場合，substepも表示させる．
			if @hash_mode["step"][id]["open?"]
				@hash_recipe["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode["substep"][id]["CURRENT?"]
						visual_substep = "CURRENT"
					elsif @hash_mode["substep"][id]["ABLE?"]
						visual_substep = "ABLE"
					else
						visual_substep = "OTHERS"
					end
					if @hash_mode["substep"][id]["is_finished?"]
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
