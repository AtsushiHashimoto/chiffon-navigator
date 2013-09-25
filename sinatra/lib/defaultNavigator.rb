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
		p jason_input["operation_contents"]
		body = []
		# modeの修正
		modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])

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

	##########################################################
	##### modeのupdate処理が複雑な2メソッドのmodeUpdater #####
	##########################################################

	def modeUpdate_navimenu(time, id)
		# 現状でCURRENTなstep，substepに関しては何の処理もしない
		# clicked_with_NAVI_MENUはCURRENT，NOT_CURRENTと同じ場所で管理する
		if @hash_recipe["step"].key?(id)
			unless @hash_mode["step"][id]["CURRENT?"]
				# クリックされたstepがclicked_with_NAVI_MENUならばNOT_CURRENTに戻す．
				if @hash_mode["step"][id]["open?"]
					@hash_mode["step"][id]["open?"] = false
				else
					@hash_mode["step"][id]["open?"] = true
				end
			end
		elsif @hash_recipe["substep"].key?(id)
			# substepがクリックされた場合のみ，detailDrawが変化するので，動画と音声を停止する．
			@hash_mode["substep"].each{|substep_id, value|
				if value["is_shown?"]
					# substepに含まれるaudio，videoは再生済み・再生中・再生待ち関わらずSTOPに．
					media = ["audio", "video"]
					media.each{|media_name|
						@hash_recipe["substep"][substep_id][media_name].each{|media_id|
							if @hash_mode[media_name][media_id]["PLAY_MODE"] == "PLAY"
								@hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
							end
						}
					}
					@hash_mode["substep"][substep_id]["is_shown?"] = false
					break
				end
			}
			# クリックされたsubstepをclicked_with_NAVI_MENUにする
			@hash_mode["substep"][id]["is_shown?"] = true
		end
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, id)
		# 優先度順に，入力されたオブジェクトをトリガーとするsubstepを探索．
		current_substep = nil
		@hash_recipe["sorted_step"].each{|v|
			flag = -1
			# ABLEなstepの中のNOT_YETなsubstepから探索．（現状でCURRENTなsubstepも探索対象．一旦オブジェクトを置いてまたやり始めただけかもしれない．）
			if @hash_mode["step"][v[1]]["ABLE?"]
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					unless @hash_mode["substep"][substep_id]["is_finished?"]
						if @hash_recipe["substep"][substep_id].key?("trigger")
							@hash_recipe["substep"][substep_id]["trigger"].each{|v|
								if v[1] == id
									current_substep = substep_id
									flag = 1
									break # trigger探索からのbreak
								end
							}
						end
					end
					if flag == 1
						break # substep探索からのbreak
					end
				}
			elsif !@hash_mode["step"][v[1]]["is_finished?"] && @hash_mode["step"][v[1]]["CURRENT?"] # ABLEでなくても，navi_menu等でCURRENTなstepも探索対象
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					unless @hash_mode["substep"][substep_id]["is_finished?"]
						if @hash_recipe["substep"][substep_id].key?("trigger")
							@hash_recipe["substep"][substep_id]["trigger"].each{|v|
								if v[1] == id
									current_substep = substep_id
									flag = 1
									break
								end
							}
						end
					end
					if flag == 1
						break
					end
				}
			end
			if flag == 1
				break # step探索からのbreak
			end
		}
		previous_substep = nil
		if current_substep == nil
			@hash_mode["substep"].each{|key, value|
				if value["CURRENT?"]
					previous_substep = key
					break
				end
			}
			if @hash_mode["substep"][previous_substep]["ABLE?"]
				unless @hash_recipe["substep"][previous_substep]["next_substep"] == nil
					current_substep = @hash_recipe["substep"][previous_substep]["next_substep"]
				else
					parent_id = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_recipe["sorted_step"].each{|v|
						if v[1] != parent_id && @hash_mode["step"][v[1]]["ABLE?"]
							@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
								unless @hash_mode["substep"][substep_id]["is_finished?"]
									current_substep = substep_id
									break
								end
							}
							break
						end
					}
				end
			else
				@hash_recipe["sorted_step"].each{|v|
					if @hash_mode["step"][v[1]]["ABLE?"]
						@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
							unless @hash_mode["substep"][substep_id]["is_finished?"]
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
			end
		end
		if current_substep == nil
			previous_substep = nil
			parent_step = nil
			# 全てのsubstepが終了下と考えられる．
			@hash_mode["substep"].each{|key, value|
				if value["CURRENT?"]
					previous_substep = key
					@hash_mode["substep"][previous_substep]["is_finished?"] = true
					parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_mode["step"][parent_step]["is_finished?"] = true
					break
				end
			}
			media = ["audio", "video", "notification"]
			media.each{|v|
				@hash_recipe["substep"][previous_substep][v].each{|media_id|
					if @hash_mode[v][media_id]["PLAY_MODE"] == "PLAY"
						@hash_mode[v][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, parent_step, previous_substep)

		else
			# 現状でCURRENTなsubstepをNOT_CURRENTかつis_finishedに．
			previous_substep = nil
			@hash_mode["substep"].each{|key, value|
				if value["CURRENT?"]
					previous_substep = key
					if previous_substep != current_substep
						@hash_mode["substep"][previous_substep]["CURRENT?"] = false
						@hash_mode["substep"][previous_substep]["is_finished?"] = true
						@hash_mode["substep"].each{|substep_id, value|
							if value["is_shown?"]
								@hash_mode["substep"][substep_id]["is_shown?"] = false
							end
						}
						# previous_substepのメディアはSTOPする．
						media = ["audio", "video"]
						media.each{|v|
							@hash_recipe["substep"][previous_substep][v].each{|media_id|
								@hash_mode[v][media_id]["PLAY_MODE"] = "STOP"
							}
						}
						# 親ノードもNOT_CURRENTにする．かつ，上記のsubstepがstep内で最後のsubstepであれば，stepをis_finishedにする．
						parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
						@hash_mode["step"][parent_step]["CURRENT?"] = false
						@hash_mode["step"][parent_step]["open?"] = false
						if @hash_recipe["substep"][previous_substep]["next_substep"] == nil
							@hash_mode["step"][parent_step]["is_finished?"] = true
						end
					end
					break
				end
			}
			# 次にCURRENTとなるsubstepをCURRENTに．
			@hash_mode["substep"][current_substep]["CURRENT?"] = true
			@hash_mode["substep"][current_substep]["is_shown?"] = true
			current_step = @hash_recipe["substep"][current_substep]["parent_step"]
			@hash_mode["step"][current_step]["CURRENT?"] = true
			@hash_mode["step"][current_step]["open?"] = true
			media = ["audio", "video", "notification"]
			media.each{|v|
				@hash_recipe["substep"][current_substep][v].each{|media_id|
					@hash_mode[v][media_id]["PLAY_MODE"] = "START"
				}
			}
			# stepとsubstepを適切にABLEに．
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			# notificationが再生済みかどうかは，隙あらば調べましょう
			@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
		end
	end

	#################################################################
	##### NAVI_MENU用の特別なnaviDrawを再定義する #####
	#################################################################

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
