#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/xmlParser.rb'
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
				status = "invalid params"
			end
		end

		if status == "internal error" || status == "invalid params"
			orders = {"status"=>status}
		elsif status == "success"
			orders = {"status"=>status, "body"=>body}
		else
			orders = {"status"=>"internal error"}
		end

		return orders
	end

	def start(jason_input)
#		status = nil
		body = []
		begin
			session_id = jason_input["session_id"]
			# Navigationに必要なファイルを作成
			result = system("mkdir -p records/#{session_id}")
			result = system("touch records/#{session_id}/#{session_id}.log")
			result = system("touch records/#{session_id}/#{session_id}_recipe.xml")
			open("records/#{session_id}/temp.xml", "w"){|io|
				io.puts(jason_input["operation_contents"])
			}
			result = system("cat records/#{session_id}/temp.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			result = system("rm records/#{session_id}/temp.xml")
			unless result
				p "Permission denied."
				p "Cannot make directory or files."
				return "internal error", body
			end

			# recipe.xmlをパースし，hash_recipeに格納する
			@hash_recipe = parse_xml("records/#{session_id}/#{session_id}_recipe.xml")

			# stepやmediaの管理をするhahs_modeの作成
			if @hash_recipe.key?("step")
				@hash_recipe["step"].each{|key, value|
					@hash_mode["step"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
				}
			end
			if @hash_recipe.key?("substep")
				@hash_recipe["substep"].each{|key, value|
					@hash_mode["substep"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
				}
			end
			if @hash_recipe.key?("audio")
				@hash_recipe["audio"].each{|key, value|
					@hash_mode["audio"]["mode"][key] = ["NOT_YET", -1]
				}
			end
			if @hash_recipe.key?("video")
				@hash_recipe["video"].each{|key, value|
					@hash_mode["video"]["mode"][key] = ["NOT_YET", -1]
				}
			end
			if @hash_recipe.key?("notification")
				@hash_recipe["notification"].each{|key, value|
					@hash_mode["notification"]["mode"][key] = ["NOT_YET", -1]
				}
			end
			# 表示されている画面の管理のために（START時はOVERVIEW）
			@hash_mode["display"] = "OVERVIEW"

			# hahs_modeにおける各要素の初期設定
			# 優先度の最も高いstepをCURRENTとし，その一番目のsubstepもCURRENTにする．
			current_step = @hash_recipe["sorted_step"][0][1]
			current_substep = @hash_recipe["step"][current_step]["substep"][0]
			@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
			@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
			# stepとsubstepを適切にABLEにする．
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
			# STARTなので，is_finishedなものはない．
			# CURRENTとなったsubstepがABLEならばメディアの再生準備としてCURRENTにする．
			if @hash_mode["substep"]["mode"][current_substep][0] == "ABLE"
				media = ["audio", "video", "notification"]
				media.each{|v|
					if @hash_recipe["substep"][current_substep].key?(v)
						@hash_recipe["substep"][current_substep][v].each{|media_id|
							@hash_mode[v]["mode"][media_id][0] = "CURRENT"
						}
					end
				}
			end

			### DetailDraw：不要
			### Play：不要
			### Notify：不要
			### Cancel：不要
			### ChannelSwitch：OVERVIEWを指定
			body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
			### NaviDraw：不要

			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
			open("records/#{session_id}/#{session_id}_recipe.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_recipe))
			}
		rescue => e
			p e
			# 履歴
			logger()
			return "internal error", body
		end

		# 履歴
		logger()
		return "success", body
	end

	def finish(jason_input)
		status = nil
		body = []
		begin
			# mediaをSTOPにする．
			session_id = jason_input["session_id"]
			media = ["audio", "video", "notification"]
			media.each{|v|
				@hash_mode[v]["mode"].each{|key, value|
					if value[0] == "CURRENT"
						@hash_mode[v]["mode"][key][0] = "STOP"
					end
				}
			}

			### DetailDraw：不要
			### Play：不要
			### Notify：不要
			### Cancel：再生待ちコンテンツが存在すればキャンセル
			body, @hash_mode, status = cancel(jason_input["session_id"], @hash_recipe, @hash_mode)
			if status == "internal error"
				# 履歴
				logger()
				return status, body
			elsif status == "invalid params"
				# 履歴
				logger()
				return status, body
			end
			### ChannelSwitch：不要
			### NaviDraw：不要


			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			# 履歴
			logger()
			return "internal error", body
		end

		# 履歴
		logger()
		return status, body
	end

	def play_control(jason_input)
#		status = nil
		body = []
		begin
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
					# 履歴
					logger()
					return "invalid params", body
				end
			else
				# 履歴
				logger()
				return "invalid params", body
			end

			### DetailDraw：不要
			### Play：不要
			### Notify：不要
			### Cancel：不要
			### ChannelSwitch：不要
			### NaviDraw：不要

			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			# 履歴
			logger()
			return "internal error", body
		end

		# 履歴
		logger()
		return "success", body
	end
end
