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
	end

	def counsel(jason_input)
		status = nil
		body = []
		orders = {}

		if jason_input["situation"] == nil || jason_input["situation"] == ""
			p "invalid params : jason_input['situation'] is wrong."
			logger()
			status = "invalid params"
		else
			case jason_input["situation"]
			when "NAVI_MENU"
				status, body = navi_menu(jason_input)
			when "EXTERNAL_INPUT"
				status, body = external_input(jason_input)
			when "CHANNEL"
				status, body = channel(jason_input)
			when "CHECK"
				status, body = check(jason_input)
			when "START"
				status, body = start(jason_input)
			when "END"
				status, body = finish(jason_input)
			when "PLAY_CONTROL"
				status, body = play_control(jason_input)
			else
				p "invalid params : jason_input['situation'] is wrong."
				logger()
				status = "invalid params"
			end
		end

		session_id = jason_input["session_id"]
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}

		if status == "internal error"
			p body.class
			p body.message
			p body.backtrace
			logger()
			orders = {"status"=>status}
		elsif status == "internal error in 'system'"
			p "Cannot make some directory and files"
			logger()
			return {"status"=>"internal error"}
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
		p orders
		return orders
	rescue => e
		p e.class
		p e.message
		p e.backtrace
		logger()
		return {"status"=>"internal error"}
	end

	private

	######################################################
	##### situationに合わせて動作する7メソッドの内， #####
	##### 動作が決まっている5メソッド                #####
	######################################################

	def channel(jason_input)
		body = []
		if @hash_mode["display"] == jason_input["operation_contents"]
			p "invalid params : #{@hash_mode["display"]} is displayed now. You try to display same one."
			logger()
			return "invalid params", body
		end

		case jason_input["operation_contents"]
		when "GUIDE"
			# notificationが再生済みかチェック．
			@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
			# チャンネルの切り替え
			@hash_mode["display"] = jason_input["operation_contents"]

			# DetailDraw：modeUpdateしないので，最近送ったオーダーと同じDetailDrawを送ることになる．
			parts = detailDraw
			body.concat(parts)
			# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
			parts = play(jason_input["time"]["sec"])
			body.concat(parts)
			# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
			parts = notify(jason_input["time"]["sec"])
			body.concat(parts)
			# Cancel：不要．再生待ちコンテンツは存在しない．
			# ChannelSwitch：GUIDEを指定
			body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
			# NaviDraw：直近のナビ画面と同じものを返すことになる．
			parts = naviDraw
			body.concat(parts)
		when "MATERIALS", "OVERVIEW"
			# modeの修正
			media = ["audio", "video"]
			media.each{|media_name|
				@hash_mode[media_name].each{|media_id, value|
					if value["PLAY_MODE"] == "PLAY"
						@hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
					end
				}
			}
			# notificationが再生済みかどうかは，隙あらば調べましょう．
			@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
			# チャンネルの切り替え
			@hash_mode["display"] = jason_input["operation_contents"]

			# DetailDraw：不要．Detailは描画されない
			# Play：不要．再生コンテンツは存在しない
			# Notify：不要．再生コンテンツは存在しない
			# Cancel：再生待ちコンテンツがあればキャンセル
			parts = cancel()
			body.concat(parts)
			# ChannelSwitch：MATERIALSを指定
			body.push({"ChannelSwitch"=>{"channel"=>"#{jason_input["operation_contents"]}"}})
			# NaviDraw：不要．Naviは描画されない
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHANNEL."
			return "invalid params", body
		end

		return "success", body
	rescue => e
		return "internal error", e
	end

	def check(jason_input)
		body = []
		unless @hash_mode["display"] == "GUIDE"
			p "invalid params : #{@hash_mode["display"]} is displayed now."
			logger()
			return "invalid params", body
		end

		id = jason_input["operation_contents"]
		# element_nameの確認
		if @hash_recipe["step"].key?(id)
			# modeの修正
			if @hash_mode["step"][id]["is_finished?"]
				@hash_mode = uncheck_isFinished(@hash_recipe, @hash_mode, id)
			else
				@hash_mode = check_isFinished(@hash_recipe, @hash_mode, id)
			end
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			@hash_recipe["step"].each{|step_id, value|
				unless @hash_mode["step"][step_id]["is_finished?"]
					@hash_mode["step"][current_step]["CURRENT?"] = false
					@hash_mode["substep"][current_substep]["CURRENT?"] = false
					@hash_mode, next_step, next_substep = go2next(@hash_recipe, @hash_mode)
					@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, next_step, next_substep)
					break
				end
			}
			# DetailDraw：別のsubstepに遷移するかもしれないので必要．
			body.concat(detailDraw())
			# Play：別のsubstepに遷移するかもしれないので必要．
			body.concat(play(jason_input["time"]["sec"]))
			# Notify：別のsubstepに遷移するかもしれないので必要．
			body.concat(notify(jason_input["time"]["sec"]))
			# Cancel：別のsubstepに遷移するかもしれないので必要．
			body.concat(cancel())
			# ChannelSwitch：不要．
			# NaviDraw：チェックされたものをis_fisnishedに書き替え，visualを適切に書き換えたものを提示
			body.concat(naviDraw())
		elsif @hash_recipe["substep"].key?(id)
			# modeの修正
			if @hash_mode["substep"][id]["is_finished?"]
				@hash_mode = uncheck_isFinished(@hash_recipe, @hash_mode, id)
			else
				@hash_mode = check_isFinished(@hash_recipe, @hash_mode, id)
			end
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			@hash_recipe["step"].each{|step_id, value|
				unless @hash_mode["step"][step_id]["is_finished?"]
					@hash_mode["step"][current_step]["CURRENT?"] = false
					@hash_mode["substep"][current_substep]["CURRENT?"] = false
					@hash_mode, next_step, next_substep = go2next(@hash_recipe, @hash_mode, current_step)
					@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, next_step, next_substep)
					break
				end
			}
			# DetailDraw：別のsubstepに遷移するかもしれないので必要．
			body.concat(detailDraw())
			# Play：別のsubstepに遷移するかもしれないので必要．
			body.concat(play(jason_input["time"]["sec"]))
			# Notify：別のsubstepに遷移するかもしれないので必要．
			body.concat(notify(jason_input["time"]["sec"]))
			# Cancel：別のsubstepに遷移するかもしれないので必要．
			body.concat(cancel())
			# ChannelSwitch：不要．
			# NaviDraw：チェックされたものをis_fisnishedに書き替え，visualを適切に書き換えたものを提示
			body.concat(naviDraw())
		else
			p "invalid params : jason_input['operation_contents'] is wrong when situation is CHECK."
			logger()
			return "invalid params", body
		end

		return "success", body
	rescue => e
		return "internal error", e
	end

	def start(jason_input)
		body = []
		session_id = jason_input["session_id"]
		# Navigationに必要なファイルを作成
		unless system("mkdir -p records/#{session_id}")
			return "internal error in 'system'", body
		end
		unless system("touch records/#{session_id}/#{session_id}.log")
			return "internal error in 'system'", body
		end
		unless system("touch records/#{session_id}/#{session_id}_recipe.xml")
			return "internal error in 'system'", body
		end
		open("records/#{session_id}/temp.xml", "w"){|io|
			io.puts(jason_input["operation_contents"])
		}
		unless system("cat records/#{session_id}/temp.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			return "internal error in 'system'", body
		end
		unless system("rm records/#{session_id}/temp.xml")
			return "internal error in 'system'", body
		end

		# recipe.xmlをパースし，hash_recipeに格納する
		@hash_recipe = parse_xml("records/#{session_id}/#{session_id}_recipe.xml")

		# stepやmediaの管理をするhahs_modeの作成及び初期設定
		@hash_mode = initialize_mode(@hash_recipe)

		### DetailDraw：不要
		### Play：不要
		### Notify：不要
		### Cancel：不要
		### ChannelSwitch：OVERVIEWを指定
		body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
		### NaviDraw：不要

		open("records/#{session_id}/#{session_id}_recipe.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_recipe))
		}
		return "success", body
	rescue => e
		return "internal error", e
	end

	def finish(jason_input)
		body = []
		# mediaをSTOPにする．
		session_id = jason_input["session_id"]
		media = ["audio", "video", "notification"]
		media.each{|media_name|
			@hash_mode[media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "PLAY"
					@hash_mode[media_name][media_id]["PLAY_MODE"] = "STOP"
				end
			}
		}

		### DetailDraw：不要
		### Play：不要
		### Notify：不要
		### Cancel：再生待ちコンテンツが存在すればキャンセル
		body = cancel
		### ChannelSwitch：不要
		### NaviDraw：不要

		return "success", body
	rescue => e
		return "internal error", e
	end

	def play_control(jason_input)
		body = []
		id = jason_input["operation_contents"]["id"]
		if @hash_recipe["audio"].key?(id) || @hash_recipe["video"].key?(id)
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

		### DetailDraw：不要
		### Play：不要
		### Notify：不要
		### Cancel：不要
		### ChannelSwitch：不要
		### NaviDraw：不要

		return "success", body
	rescue => e
		return "internal error", e
	end

	#####################################
	##### 各命令を生成する5メソッド #####
	#####################################

	# CURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
	def detailDraw
		orders = []
		shown_substep = @hash_mode["shown"]
		@hash_mode["substep"].each{|substep_id, value|
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
	def play(time)
		orders = []
		media = ["audio", "video"]
		media.each{|media_name|
			@hash_mode[media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "START"
					if @hash_recipe[media_name][media_id]["trigger"].empty?
						@hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
						return []
					else
						orders.push({"Play"=>{"id"=>media_id, "delay"=>@hash_recipe[media_name][media_id]["trigger"][0][2].to_i}})
						finish_time = time + @hash_recipe[media_name][media_id]["trigger"][0][2].to_i * 1000
						@hash_mode[media_name][media_id]["time"] = finish_time
						@hash_mode[media_name][media_id]["PLAY_MODE"] = "PLAY"
					end
				end
			}
		}
		return orders
	end

	# CURRENTなnotificationを再生させるNotify命令．
	def notify(time)
		orders = []
		@hash_mode["notification"].each{|id, value|
			if value["PLAY_MODE"] == "START"
				orders.push({"Notify"=>{"id"=>id, "delay"=>@hash_recipe["notification"][id]["trigger"][0][2].to_i}})
				finish_time = time + @hash_recipe["notification"][id]["trigger"][0][2].to_i * 1000
				@hash_mode["notification"][id]["time"] = finish_time
				@hash_mode["notification"][id]["PLAY_MODE"] = "PLAY"
				@hash_recipe["notification"][id]["audio"].each{|audio_id|
					@hash_mode["audio"][audio_id]["time"] = finish_time
				}
			end
		}
		return orders
	end

	# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
	def cancel
		orders = []
		media = ["audio", "video"]
		media.each{|media_name|
			@hash_mode[media_name].each{|media_id, value|
				if value["PLAY_MODE"] == "STOP"
					orders.push({"Cancel"=>{"id"=>media_id}})
					@hash_mode[media_name][media_id]["PLAY_MODE"] = "---"
					@hash_mode[media_name][media_id]["time"] = -1
				end
			}
		}
		if @hash_mode.key?("notification")
			@hash_mode["notification"].each{|id, value|
				if value["PLAY_MODE"] == "STOP"
					orders.push({"Cancel"=>{"id"=>id}})
					@hash_mode["notification"][id]["PLAY_MODE"] = "---"
					@hash_mode["notification"][id]["time"] = -1
					@hash_recipe["notification"][id]["audio"].each{|audio_id|
						@hash_mode["audio"][audio_id]["PLAY_MODE"] == "---"
						@hash_mode["audio"][audio_id]["time"] = -1
					}
				end
			}
		end
		return orders
	end

	# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			step_id = v[1]
			visual = nil
			if @hash_mode["step"][step_id]["CURRENT?"]
				visual = "CURRENT"
			elsif @hash_mode["step"][step_id]["ABLE?"]
				visual = "ABLE"
			else
				visual = "OTHERS"
			end
			if @hash_mode["step"][step_id]["is_finished?"]
				orders[0]["NaviDraw"]["steps"].push({"id"=>step_id, "visual"=>visual, "is_finished"=>1})
			else
				orders[0]["NaviDraw"]["steps"].push({"id"=>step_id, "visual"=>visual, "is_finished"=>0})
			end
			if @hash_mode["step"][step_id]["open?"]
				@hash_recipe["step"][step_id]["substep"].each{|substep_id|
					visual = nil
					if @hash_mode["substep"][substep_id]["CURRENT?"]
						visual = "CURRENT"
					elsif @hash_mode["substep"][substep_id]["ABLE?"]
						visual = "ABLE"
					else
						visual = "OTHERS"
					end
					if @hash_mode["substep"][substep_id]["is_finished?"]
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
