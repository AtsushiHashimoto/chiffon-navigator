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

		session_id = jason_input["session_id"]
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	def external_input(jason_input)
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

		session_id = jason_input["session_id"]
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
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
			# クリックされたstepがclicked_with_NAVI_MENUならばNOT_CURRENTに戻す．
			if @hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
				@hash_mode["step"]["mode"][id][2] = "NOT_CURRENT"
			else # クリックされたstepがNOT_CURRENTならばclicked_with_NAVI_MENUにする
				@hash_mode["step"]["mode"][id][2] = "clicked_with_NAVI_MENU"
			end
		elsif @hash_recipe["substep"].key?(id)
			# クリックされたsubstepをclicked_with_NAVI_MENUにする
			@hash_mode["substep"]["mode"][id][2] = "clicked_with_NAVI_MENU"
			# substepがクリックされた場合のみ，detailDrawが変化するので，動画と音声を停止する．
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					# substepに含まれるaudio，videoは再生済み・再生中・再生待ち関わらずSTOPに．
					media = ["audio", "video"]
					media.each{|v|
						@hash_mode[v]["mode"].each{|key, value|
							if value[0] == "CURRENT"
								@hash_mode[v]["mode"][key][0] = "STOP"
							end
						}
					}
					break
				end
			}
		end
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, id)
		# 優先度順に，入力されたオブジェクトをトリガーとするsubstepを探索．
		current_substep = nil
		@hash_recipe["sorted_step"].each{|v|
			flag = -1
			# ABLEなstepの中のNOT_YETなsubstepから探索．（現状でCURRENTなsubstepも探索対象．一旦オブジェクトを置いてまたやり始めただけかもしれない．）
			if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
						if @hash_recipe["substep"][substep_id].key?("trigger")
							@hash_recipe["substep"][substep_id]["trigger"].each{|v|
								if v[1] == id
									current_substep = node2.parent.attributes.get_attribute("id").value
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
			elsif @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" && @hash_mode["step"]["mode"][v[1]][2] == "CURRENT" # ABLEでなくても，navi_menu等でCURRENTなstepも探索対象
				@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
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
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					break
				end
			}
			if @hash_mode["substep"]["mode"][previous_substep][0] == "ABLE"
				if @hash_recipe["substep"][previous_substep].key?("next_substep")
					current_substep = @hash_recipe["substep"][previous_substep]["next_substep"]
				else
					parent_id = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_recipe["sorted_step"].each{|v|
						if v[1] != parent_id && @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
							@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
								if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
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
					if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
						@hash_recipe["step"][v[1]]["substep"].each{|substep_id|
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
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
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					@hash_mode["substep"]["mode"][previous_substep][1] = "is_finished"
					parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
					@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
					break
				end
			}
			media = ["audio", "video", "notification"]
			media.each{|v|
				if @hash_recipe["substep"][previous_substep].key?(v)
					@hash_recipe["substep"][previous_substep][v].each{|media_id|
						if @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
							@hash_mode[v]["mode"][media_id][0] = "STOP"
						end
					}
				end
			}
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, parent_step, previous_substep)

		else
			# 現状でCURRENTなsubstepをNOT_CURRENTかつis_finishedに．
			previous_substep = nil
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT"
					previous_substep = key
					if previous_substep != current_substep
						@hash_mode["substep"]["mode"][previous_substep][2] = "NOT_CURRENT"
						@hash_mode["substep"]["mode"][previous_substep][1] = "is_finished"
						# 子の時点ではメディアはSTOPしない．
						# 親ノードもNOT_CURRENTにする．かつ，上記のsubstepがstep内で最後のsubstepであれば，stepをis_finishedにする．
						parent_step = @hash_recipe["substep"][previous_substep]["parent_step"]
						@hash_mode["step"]["mode"][parent_step][2] = "NOT_CURRENT"
						unless @hash_recipe["substep"][previous_substep].key?("next_substep")
							@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
						end
					end
					break
				end
			}
			# 次にCURRENTとなるsubstepをCURRENTに．
			@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
			current_step = @hash_recipe["substep"][current_substep]["parent_step"]
			@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
			# 現状でCURRENTなsubstepと次にCURRENTなsubstepが異なる場合は，メディアを再生させる．
			if current_substep != previous_substep
				media = ["audio", "video", "notification"]
				media.each{|v|
					if @hash_recipe["substep"][current_substep].key?(v)
						@hash_recipe["substep"][current_substep][v].each{|media_id|
							if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
								@hash_mode[v]["mode"][media_id][0] = "CURRENT"
							end
						}
					end
				}
				# previous_substepのメディアはSTOPする．
				media = ["audio", "video"]
				media.each{|v|
					if @hash_recipe["substep"][previous_substep].key?(v)
						@hash_recipe["substep"][previous_substep][v].each{|media_id|
							@hash_mode[v]["mode"][media_id][0] = "STOP"
						}
					end
				}
			end
			# stepとsubstepを適切にABLEに．
			p current_step
			p current_substep
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			# notificationが再生済みかどうかは，隙あらば調べましょう
			@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
		end
	end

	#################################################################
	##### NAVI_MENU用の特別なdetailDraw及びnaviDrawを再定義する #####
	#################################################################

	# clicked_with_NAVI_MENUまたはCURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
	# clicked_with_NAVI_MENUの方が優先度は高い
	# clicked_with_NAVI_MENUは一度処理するとNOT_CURRENTに戻る
	def detailDraw
		orders = []
		@hash_mode["substep"]["mode"].each{|key, value|
			if value[2] == "CURRENT"
				orders = [{"DetailDraw"=>{"id"=>key}}]
			end
			if value[2] == "clicked_with_NAVI_MENU"
				orders = [{"DetailDraw"=>{"id"=>key}}]
				@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
				break
			end
		}
		return orders
	end

		# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw
		# sorted_stepの順に表示させる．
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			id = v[1]
			visual_step = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual_step = "CURRENT"
			else
				visual_step = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_step, "is_finished"=>0})
			end
			# CURRENTなstepの場合，substepも表示させる．
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				@hash_recipe["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual_substep = "CURRENT"
					else
						visual_substep = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual_substep, "is_finished"=>0})
					end
				}
			elsif @hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
				# NAVI_MENUで選択されたものも，substepを表示させる．
				@hash_recipe["step"][id]["substep"].each{|id|
					visual_substep = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual_substep = "CURRENT"
					else
						visual_substep = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
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
