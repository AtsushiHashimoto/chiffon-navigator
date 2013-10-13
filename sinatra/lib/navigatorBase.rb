#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/xmlParser.rb'
require 'lib/modeInitializer.rb'
require 'lib/utils.rb'

class NavigatorBase
	def initialize
		@hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		@hash_mode = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		@hash_body = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		@body_parts = {"DetailDraw"=>false,"Play"=>false,"Notify"=>false,"Cancel"=>false,"ChannelSwitch"=>false,"NaviDraw"=>false}
	end

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
			status, body = check(jason_input, session_id)
		when "START"
			status, body, fo = start(jason_input, session_id)
		when "END"
			fo = lock(session_id)
			status, body = finish(jason_input, session_id)
		when "PLAY_CONTROL"
			fo = lock(session_id)
			status, body = play_control(jason_input, session_id)
		else
			p "invalid params : jason_input['situation'] is wrong."
			logger()
			status = "invalid params"
		end

		outputHashMode(session_id, @hash_mode[session_id])

		if status == "internal error"
			p body.class
			p body.message
			p body.backtrace
			logger()
			orders = {"status"=>status}
		elsif status == "internal error in 'system'"
			p "Cannot make some directory and files"
			logger()
			orders = {"status"=>"internal error"}
		elsif status == "invalid params"
			orders = {"status"=>status}
		elsif status == "success"
			logger()
			orders = {"status"=>status, "body"=>body}
		else
			p "internal error"
			p "navigatorBase.rb: parameter 'status' is wrong."
			logger()
			orders = {"status"=>"internal error"}
		end
		unlock(fo)
		return orders
	rescue => e
		p e.class
		p e.message
		p e.backtrace
		logger()
		unlock(fo)
		return {"status"=>"internal error"}
	end

	private

	######################################################
	##### situationに合わせて動作する7メソッドの内， #####
	##### 動作が決まっている5メソッド                #####
	######################################################

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
			# modeの修正
			media = ["audio", "video"]
			media.each{|media_name|
				@hash_mode[session_id][media_name].each{|media_id, value|
					if value["PLAY_MODE"] == "PLAY"
						@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
			# notificationが再生済みかどうかは，隙あらば調べましょう．
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

		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	def check(jason_input, session_id)
		body = []

		id = jason_input["operation_contents"]
		# element_nameの確認
		if @hash_recipe[session_id]["step"].key?(id)
			# modeの修正
			if @hash_mode[session_id]["step"][id]["is_finished?"]
				@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], id)
			else
				@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], id)
			end
			current_step = @hash_mode[session_id]["current_step"]
			current_substep = @hash_mode[session_id]["current_substep"]
			@hash_mode[session_id] = set_ABLEorOTHERS(@hash_recipe[session_id], @hash_mode[session_id], current_step, current_substep)
			@hash_recipe[session_id]["step"].each{|step_id, value|
				unless @hash_mode[session_id]["step"][step_id]["is_finished?"]
					@hash_mode[session_id]["step"][current_step]["CURRENT?"] = false
					@hash_mode[session_id]["substep"][current_substep]["CURRENT?"] = false
					@hash_mode[session_id]["prev_step"] = current_step
					@hash_mode[session_id]["prev_substep"] = current_substep
					@hash_mode[session_id], next_step, next_substep = go2next(@hash_recipe[session_id], @hash_mode[session_id])
					@hash_mode[session_id] = set_ABLEorOTHERS(@hash_recipe[session_id], @hash_mode[session_id], next_step, next_substep)
					break
				end
			}
		elsif @hash_recipe[session_id]["substep"].key?(id)
			# modeの修正
			if @hash_mode[session_id]["substep"][id]["is_finished?"]
				@hash_mode[session_id] = uncheck_isFinished(@hash_recipe[session_id], @hash_mode[session_id], id)
			else
				@hash_mode[session_id] = check_isFinished(@hash_recipe[session_id], @hash_mode[session_id], id)
			end
			current_step = @hash_mode[session_id]["current_step"]
			current_substep = @hash_mode[session_id]["current_substep"]
			@hash_mode[session_id] = set_ABLEorOTHERS(@hash_recipe[session_id], @hash_mode[session_id], current_step, current_substep)
			@hash_recipe[session_id]["step"].each{|step_id, value|
				unless @hash_mode[session_id]["step"][step_id]["is_finished?"]
					@hash_mode[session_id]["step"][current_step]["CURRENT?"] = false
					@hash_mode[session_id]["substep"][current_substep]["CURRENT?"] = false
					@hash_mode[session_id]["prev_step"] = current_step
					@hash_mode[session_id]["prev_substep"] = current_substep
					@hash_mode[session_id], next_step, next_substep = go2next(@hash_recipe[session_id], @hash_mode[session_id], current_step)
					@hash_mode[session_id] = set_ABLEorOTHERS(@hash_recipe[session_id], @hash_mode[session_id], next_step, next_substep)
					break
				end
			}
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHECK."
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

	def start(jason_input, session_id)
		body = []
		# Navigationに必要なファイルを作成
		unless system("mkdir -p records/#{session_id}")
			return "internal error in 'system'", body
		end
		fo = lock(session_id)
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

		# stepやmediaの管理をするhahs_modeの作成及び初期設定
		@hash_mode[session_id] = initialize_mode(@hash_recipe[session_id])

		@hash_body[session_id] = @body_parts

		@hash_body[session_id].each{|key, value|
			if key == "ChannelSwitch"
				@hash_body[session_id][key] = true
			else
				@hash_body[session_id][key] = false
			end
		}
		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)

		open("records/#{session_id}/recipe.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_recipe[session_id]))
		}
		return "success", body, fo
	rescue => e
		return "internal error", e, fo
	end

	def finish(jason_input, session_id)
		body = []
		# mediaをSTOPにする．
		session_id = jason_input["session_id"]
		media = ["audio", "video", "notification"]
		media.each{|media_name|
			@hash_mode[session_id][media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "PLAY"
					@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "STOP"
				end
			}
		}

		@hash_body[session_id].each{|key, value|
			if key == "Cancel"
				@hash_body[session_id][key] = true
			else
				@hash_body[session_id][key] = false
			end
		}
		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)
		@hash_recipe.delete(session_id)
		@hash_mode.delete(session_id)
		@hash_body.delete(session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

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
				p "invalid params : jason_input['operation_contents']['operation'] is wrong when situation is PLAY_CONTROL."
				logger()
				return "invalid params", body
			end
		else
			p "invalid params : jason_input['operation_contents']['id'] is wrong when situation is PLAY_CONTROL."
			logger()
			return "invalid params", body
		end

		@hash_body[session_id].each{|key, value|
			@hash_body[session_id][key] = false
		}
		body = bodyMaker(@hash_mode[session_id], @hash_body[session_id], jason_input["time"]["sec"], session_id)

		return "success", body
	rescue => e
		return "internal error", e
	end

	#####################################
	##### 各命令を生成する5メソッド #####
	#####################################

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
						return []
					else
						orders.push({"Play"=>{"id"=>media_id, "delay"=>@hash_recipe[session_id][media_name][media_id]["trigger"][0][2].to_i}})
						finish_time = time + @hash_recipe[session_id][media_name][media_id]["trigger"][0][2].to_i * 1000
						@hash_mode[session_id][media_name][media_id]["time"] = finish_time
						@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "PLAY"
					end
				end
			}
		}
		return orders
	end

	# CURRENTなnotificationを再生させるNotify命令．
	def notify(time, session_id)
		orders = []
		@hash_mode[session_id]["notification"].each{|id, value|
			if value["PLAY_MODE"] == "START"
				orders.push({"Notify"=>{"id"=>id, "delay"=>@hash_recipe[session_id]["notification"][id]["trigger"][0][2].to_i}})
				finish_time = time + @hash_recipe[session_id]["notification"][id]["trigger"][0][2].to_i * 1000
				@hash_mode[session_id]["notification"][id]["time"] = finish_time
				@hash_mode[session_id]["notification"][id]["PLAY_MODE"] = "PLAY"
				@hash_recipe[session_id]["notification"][id]["audio"].each{|audio_id|
					@hash_mode[session_id]["audio"][audio_id]["time"] = finish_time
				}
			end
		}
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
					@hash_mode[session_id][media_name][media_id]["PLAY_MODE"] = "---"
					@hash_mode[session_id][media_name][media_id]["time"] = -1
				end
			}
		}
		if @hash_mode[session_id].key?("notification")
			@hash_mode[session_id]["notification"].each{|id, value|
				if value["PLAY_MODE"] == "STOP"
					orders.push({"Cancel"=>{"id"=>id}})
					@hash_mode[session_id]["notification"][id]["PLAY_MODE"] = "---"
					@hash_mode[session_id]["notification"][id]["time"] = -1
					@hash_recipe[session_id]["notification"][id]["audio"].each{|audio_id|
						@hash_mode[session_id]["audio"][audio_id]["PLAY_MODE"] == "---"
						@hash_mode[session_id]["audio"][audio_id]["time"] = -1
					}
				end
			}
		end
		return orders
	end

	# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw(session_id)
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe[session_id]["sorted_step"].each{|v|
			step_id = v[1]
			visual = nil
			if @hash_mode[session_id]["step"][step_id]["CURRENT?"]
				visual = "CURRENT"
			elsif @hash_mode[session_id]["step"][step_id]["ABLE?"]
				visual = "ABLE"
			else
				visual = "OTHERS"
			end
			if @hash_mode[session_id]["step"][step_id]["is_finished?"]
				orders[0]["NaviDraw"]["steps"].push({"id"=>step_id, "visual"=>visual, "is_finished"=>1})
			else
				orders[0]["NaviDraw"]["steps"].push({"id"=>step_id, "visual"=>visual, "is_finished"=>0})
			end
			if @hash_mode[session_id]["step"][step_id]["open?"]
				@hash_recipe[session_id]["step"][step_id]["substep"].each{|substep_id|
					visual = nil
					if @hash_mode[session_id]["substep"][substep_id]["CURRENT?"]
						visual = "CURRENT"
					elsif @hash_mode[session_id]["substep"][substep_id]["ABLE?"]
						visual = "ABLE"
					else
						visual = "OTHERS"
					end
					if @hash_mode[session_id]["substep"][substep_id]["is_finished?"]
						orders[0]["NaviDraw"]["steps"].push({"id"=>substep_id, "visual"=>visual, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>substep_id, "visual"=>visual, "is_finished"=>0})
					end
				}
			end
		}
		return orders
	end
end
