#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/xmlParser.rb'
require 'lib/modeInitializer.rb'
require 'lib/utils.rb'

class NavigatorBase
	def initialize
		# recipe.xmlのパース結果
		@hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		# step，substep，audio等の状態管理
		@hash_mode = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		# 命令body生成管理（詳しくはstart関数を参照）
		@hash_body = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		@body_parts = {"DetailDraw"=>false,"Play"=>false,"Notify"=>false,"Cancel"=>false,"ChannelSwitch"=>false,"NaviDraw"=>false}
	end

	# viewerからの入力を受け付け，振り分ける
	def counsel(jason_input)
		status = nil
		body = []
		orders = {}
		session_id = jason_input["session_id"]
		fo = nil

		case jason_input["situation"]
		when "NAVI_MENU"
			fo = lock(session_id)
			status, body = navi_menu(jason_input, session_id)
		when "EXTERNAL_INPUT"
			fo = lock(session_id)
			status, body = external_input(jason_input, session_id)
		when "CHANNEL"
			fo = lock(session_id)
			status, body = channel(jason_input, session_id)
		when "CHECK"
			fo = lock(session_id)
			status, body = check_uncheck(jason_input, session_id)
		when "START"
			status, body, fo = start(jason_input, session_id)
		when "END"
			fo = lock(session_id)
			status, body = finish(jason_input, session_id)
		when "PLAY_CONTROL"
			fo = lock(session_id)
			status, body = play_control(jason_input, session_id)
		else
			message = "invalid params : jason_input['situation'] is wrong."
			p message
			logger(jason_input, "invalid params", message)
			status = "invalid params"
		end

		outputHashMode(session_id, jason_input["time"], @hash_mode[session_id])

		if status == "internal error"
			p body.class
			p body.message
			p body.backtrace
			logger(jason_input, "internal error", body.message)
			orders = {"status"=>status}
		elsif status == "internal error in 'system'"
			message = "Cannot make some directory and files"
			p message
			logger(jason_input, "internal error in 'system'", message)
			orders = {"status"=>"internal error"}
		elsif status == "invalid params"
			orders = {"status"=>status}
		elsif status == "success"
			logger(jason_input, "success", body, @hash_mode[session_id]["current_estimation_level"])
			orders = {"status"=>status, "body"=>body}
		else
			p "internal error"
			message = "navigatorBase.rb: parameter 'status' is wrong."
			p message
			logger(jason_input, "internal error", message)
			orders = {"status"=>"internal error"}
		end
		unlock(fo)
		return orders
	rescue => e
		p e.class
		p e.message
		p e.backtrace
		logger(jason_input, "internal error", e.message)
		unlock(fo)
		return {"status"=>"internal error"}
	end

	private

	######################################################
	##### situationに合わせて動作する7メソッドの内， #####
	##### 動作が決まっている6メソッド                #####
	######################################################

	# ユーザの画面操作に合わせ，stepのプルダウンやsubstepの切り替えを行う．
	def navi_menu(jason_input, session_id)
		body = []

		clicked_id = jason_input["operation_contents"]
		if @hash_recipe[session_id]["step"].key?(clicked_id)
			unless @hash_mode[session_id]["step"][clicked_id]["CURRENT?"]
				@hash_mode[session_id]["step"][clicked_id]["open?"] = (not @hash_mode[session_id]["step"][clicked_id]["open?"])
			end
		elsif @hash_recipe[session_id]["substep"].key?(clicked_id)
			if @hash_mode[session_id]["substep"][clicked_id]["ABLE?"]
				# 遷移先のsubstepにおいて，prev_substepがis_finished?==falseであった場合，substepを並べ替えhash_recipeを更新．
				prev_of_clicked = @hash_recipe[session_id]["substep"][clicked_id]["prev_substep"]
				unless @hash_mode[session_id]["substep"][prev_of_clicked]["is_finished?"]
					@hash_recipe[session_id] = sortSubstep(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
					open("records/#{session_id}/recipe.txt", "w"){|io|
						io.puts(JSON.pretty_generate(@hash_recipe[session_id]))
					}
				end
				# substepをchangeする．遷移元のsubstepはinitialize．
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP", @hash_mode[session_id]["current_substep"])
				@hash_mode[session_id] = jump(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
				@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "START", clicked_id)
				# ユーザのsubstep切り替え操作はestimationのレベルが高くなる
				@hash_mode[session_id]["current_estimation_level"] = "explicitly"
				# 過去の遷移履歴は初期化してしまう．
				@hash_mode[session_id]["prev_substep"] = []
				@hash_mode[session_id]["prev_estimation_level"] = nil
			end
		else
			message = "invalid params : jason_input['operation_contents'] is wrong when situation is NAVI_MENU."
			p message
			logger(jason_input, "invalid params", message)
			return "invalid params", body
		end

		@hash_body[session_id].each{|key, value|
			if key == "ChannelSwitch"
				@hash_body[session_id][key] = false
			else
				@hash_body[session_id][key] = true
			end
		}
		body = bodyMaker(jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	# ユーザの画面操作に合わせて，概観，材料表，詳細を切り替える．
	def channel(jason_input, session_id)
		body = []

		case jason_input["operation_contents"]
		when "GUIDE"
			# notificationが再生済みかチェック．
			@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], jason_input["time"]["sec"])
			# チャンネルの切り替え
			@hash_mode[session_id]["display"] = jason_input["operation_contents"]
			@hash_body[session_id].each{|key,value|
				@hash_body[session_id][key] = true
			}
		when "MATERIALS", "OVERVIEW"
			# メディアを停止する
			@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], ["audio", "video"], "STOP", @hash_mode[session_id]["current_substep"])
			# notificationが再生済みかチェック．
			@hash_mode[session_id] = check_notification_FINISHED(@hash_recipe[session_id], @hash_mode[session_id], jason_input["time"]["sec"])
			# チャンネルの切り替え
			@hash_mode[session_id]["display"] = jason_input["operation_contents"]
			@hash_body[session_id].each{|key,value|
				if key == "Cancel" || key == "ChannelSwitch"
					@hash_body[session_id][key] = true
				else
					@hash_body[session_id][key] = false
				end
			}
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHANNEL."
			return "invalid params", body
		end

		body = bodyMaker(jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	# ユーザの画面操作に合わせて，step，substepを終了（check），初期化（uncheck）する
	def check_uncheck(jason_input, session_id)
		body = []

		clicked_id = jason_input["operation_contents"]
		prev_substep = @hash_mode[session_id]["current_substep"]
		if @hash_recipe[session_id]["step"].key?(clicked_id)
			if @hash_mode[session_id]["step"][clicked_id]["is_finished?"]
				@hash_mode[session_id] = uncheck(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
			else
				@hash_mode[session_id] = check(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
			end
		elsif @hash_recipe[session_id]["substep"].key?(clicked_id)
			if @hash_mode[session_id]["substep"][clicked_id]["is_finished?"]
				@hash_mode[session_id] = uncheck(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
			else
				@hash_mode[session_id] = check(@hash_recipe[session_id], @hash_mode[session_id], clicked_id)
			end
		else
			message =  "invalid params : jason_input['operation_contents'] is wrong when situation is CHECK."
			p message
			logger(jason_input, "invalid params", message)
			return "invalid params", body
		end

		# check, uncheckの結果substepが遷移した場合，過去の履歴を初期化し，estimation levelを上げる
		if prev_substep != @hash_mode[session_id]["current_substep"]
			@hash_mode[session_id]["current_estimation_level"] = "explicitly"
			@hash_mode[session_id]["prev_substep"] = []
			@hash_mode[session_id]["prev_estimation_level"] = nil
		end

		@hash_body[session_id].each{|key, value|
			if key == "ChannelSwitch"
				@hash_body[session_id][key] = false
			else
				@hash_body[session_id][key] = true
			end
		}
		body = bodyMaker(jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	# ユーザの調理開始時に，Navigatorの状態の初期設定を行う
	def start(jason_input, session_id)
		body = []
		# Navigationに必要なファイルを作成
		unless system("mkdir -p records/#{session_id}")
			return "internal error in 'system'", body
		end
		fo = lock(session_id)
		unless system("mkdir -p records/#{session_id}/mode")
			return "internal error in 'system'", body
		end
		unless system("touch records/#{session_id}/log.txt")
			return "internal error in 'system'", body, fo
		end
		unless system("touch records/#{session_id}/recipe.xml")
			return "internal error in 'system'", body, fo
		end
		open("records/#{session_id}/temp.xml", "w"){|io|
			io.puts(jason_input["operation_contents"])
		}
		unless system("cat records/#{session_id}/temp.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/recipe.xml")
			return "internal error in 'system'", body, fo
		end
		unless system("rm records/#{session_id}/temp.xml")
			return "internal error in 'system'", body, fo
		end

		# recipe.xmlをパースし，hash_recipeに格納する
		@hash_recipe[session_id] = parse_xml("records/#{session_id}/recipe.xml")

		# stepやmediaの管理をするhash_modeの作成及び初期設定
		@hash_mode[session_id] = initialize_mode(@hash_recipe[session_id])

		# 命令bodyを管理するhash_bodyの初期化
		# hash_bodyの各keyをtrueにすれば，その命令はbodyが生成される．
		@hash_body[session_id] = @body_parts

		# START時は概観を表示するだけなので，NotifyとChannelSwitch以外の命令は不要．
		@hash_body[session_id].each{|key, value|
			if key == "Notify" || key == "ChannelSwitch"
				@hash_body[session_id][key] = true
			else
				@hash_body[session_id][key] = false
			end
		}
		# START時に再生すべきnotificationが無いか調べる
		notification_id = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], ["notification"], "FIRST")
		if notification_id == nil
			body = bodyMaker(jason_input["time"]["sec"], session_id)
		else
			body = bodyMaker(jason_input["time"]["sec"], session_id, notification_id)
		end

		open("records/#{session_id}/recipe.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_recipe[session_id]))
		}
		return "success", body, fo
	rescue => e
		return "internal error", e, fo
	end

	# ユーザの調理終了時に，Navigatorが保持していたユーザ情報を消す
	def finish(jason_input, session_id)
		body = []
		# mediaをSTOPにする．
		session_id = jason_input["session_id"]
		@hash_mode[session_id] = controlMedia(@hash_recipe[session_id], @hash_mode[session_id], "all", "STOP")

		@hash_body[session_id].each{|key, value|
			if key == "Cancel"
				@hash_body[session_id][key] = true
			else
				@hash_body[session_id][key] = false
			end
		}
		body = bodyMaker(jason_input["time"]["sec"], session_id)

		@hash_recipe.delete(session_id)
		@hash_mode.delete(session_id)
		@hash_body.delete(session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	# ユーザが画面操作により音声や動画を操作したときに，それをログに残す
	def play_control(jason_input, session_id)
		body = []
		id = jason_input["operation_contents"]["id"]
		if @hash_recipe[session_id]["audio"].key?(id) || @hash_recipe[session_id]["video"].key?(id)
			case jason_input["operation_contents"]["operation"]
			when "PLAY"
			when "PAUSE"
			when "JUMP"
			when "TO_THE_END"
			when "FULL_SCREEN"
			when "MUTE"
			when "VOLUME"
			else
				message ="invalid params : jason_input['operation_contents']['operation'] is wrong when situation is PLAY_CONTROL."
				p message
				logger(jason_input, "invalid params", )
				return "invalid params", body
			end
		else
			message = "invalid params : jason_input['operation_contents']['id'] is wrong when situation is PLAY_CONTROL."
			p message
			logger(jason_input, "invalid params", message)
			return "invalid params", body
		end

		@hash_body[session_id].each{|key, value|
			@hash_body[session_id][key] = false
		}
		body = bodyMaker(jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	##################################################################
	##### 命令生成メソッドを管理する1メソッドと5つの生成メソッド #####
	##################################################################

	# hash_bodyに従って命令を生成
	def bodyMaker(time, session_id, *notification_id)
		body = []
		if @hash_body[session_id]["DetailDraw"]
			body.concat(detailDraw(session_id))
		end
		if @hash_body[session_id]["Play"]
			body.concat(play(time, session_id))
		end
		if @hash_body[session_id]["Notify"]
			if notification_id == []
				body.concat(notify(time, session_id))
			else
				body.concat(notify(time, session_id, notification_id[0]))
			end
		end
		if @hash_body[session_id]["Cancel"]
			body.concat(cancel(session_id))
		end
		if @hash_body[session_id]["ChannelSwitch"]
			body.push({"ChannelSwitch"=>{"channel"=>@hash_mode[session_id]["display"]}})
		end
		if @hash_body[session_id]["NaviDraw"]
			body.concat(naviDraw(session_id))
		end
		return body
	end

	# CURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
	def detailDraw(session_id)
		orders = []
		shown_substep = @hash_mode[session_id]["shown"]
		@hash_mode[session_id]["substep"].each{|substep_id, value|
			unless value["is_finished?"]
				orders.push({"DetailDraw"=>{"id"=>shown_substep}})
				break
			end
		}
		if orders.empty?
			orders.push({"DetailDraw"=>{}})
		end
		return orders
	end

	# CURRENTなaudioとvideoを再生させるPlay命令．
	def play(time, session_id)
		orders = []
		media = ["audio", "video"]
		media.each{|media_name|
			@hash_mode[session_id][media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "START"
					if @hash_recipe[session_id][media_name][media_id]["trigger"].empty?
						@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "---"
						next
					else
						orders.push({"Play"=>{"id"=>media_id, "delay"=>@hash_recipe[session_id][media_name][media_id]["trigger"][0]["delay"].to_i}})
						finish_time = time + @hash_recipe[session_id][media_name][media_id]["trigger"][0]["delay"].to_i * 1000
						@hash_mode[session_id][media_name][media_id]["time"] = finish_time
						@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "PLAY"
					end
				end
			}
		}
		return orders
	end

	# CURRENTなnotificationを再生させるNotify命令．
	def notify(time, session_id, *id)
		orders = []
		if id == []
			@hash_mode[session_id]["notification"].each{|id, value|
				if value["PLAY_MODE"] == "START"
					orders.push({"Notify"=>{"id"=>id, "delay"=>@hash_recipe[session_id]["notification"][id]["trigger"][0]["delay"].to_i}})
					finish_time = time + @hash_recipe[session_id]["notification"][id]["trigger"][0]["delay"].to_i * 1000
					@hash_mode[session_id]["notification"][id]["time"] = finish_time
					@hash_mode[session_id]["notification"][id]["PLAY_MODE"] = "PLAY"
					@hash_recipe[session_id]["notification"][id]["audio"].each{|audio_id|
						@hash_mode[session_id]["audio"][audio_id]["time"] = finish_time
					}
				end
			}
		else
			# START時に流すnotificationへの対応
			orders.push({"Notify"=>{"id"=>id[0], "delay"=>@hash_recipe[session_id]["notification"][id[0]]["trigger"][0]["delay"].to_i}})
			finish_time = time + @hash_recipe[session_id]["notification"][id[0]]["trigger"][0]["delay"].to_i * 1000
			@hash_mode[session_id]["notification"][id[0]]["time"] = finish_time
			@hash_mode[session_id]["notification"][id[0]]["PLAY_MODE"] = "PLAY"
			@hash_recipe[session_id]["notification"][id[0]]["audio"].each{|audio_id|
				@hash_mode[session_id]["audio"][audio_id]["time"] = finish_time
			}
		end
		return orders
	end

	# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
	def cancel(session_id)
		orders = []
		media = ["audio", "video"]
		media.each{|media_name|
			@hash_mode[session_id][media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "STOP"
					orders.push({"Cancel"=>{"id"=>media_id}})
					@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "PLAYED"
					@hash_mode[session_id][media_name][media_id]["time"] = -1
				end
			}
		}
		if @hash_mode[session_id].key?("notification")
			@hash_mode[session_id]["notification"].each{|id, value|
				if value["PLAY_MODE"] == "STOP"
					orders.push({"Cancel"=>{"id"=>id}})
					@hash_mode[session_id]["notification"][id]["PLAY_MODE"] = "PLAYED"
					@hash_mode[session_id]["notification"][id]["time"] = -1
					@hash_recipe[session_id]["notification"][id]["audio"].each{|audio_id|
						@hash_mode[session_id]["audio"][audio_id]["PLAY_MODE"] == "PLAYED"
						@hash_mode[session_id]["audio"][audio_id]["time"] = -1
					}
				end
			}
		end
		return orders
	end

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
