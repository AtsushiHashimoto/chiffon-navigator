#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/ordersmaker.rb'
require 'lib/modeUpdater.rb'
require 'lib/utils.rb'

class DefaultNavigator < NavigatorBase
	def navi_menu(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# modeの修正
			status, @hash_mode = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw：入力されたstepをCURRENTとして提示
			parts, @hash_mode = maker.detailDraw()
			body.concat(parts)
			# Play：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
			# Notify：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
			# Cancel：再生待ちコンテンツがあればキャンセル
			parts, @hash_mode = maker.cancel()
			body.concat(parts)
			# ChannelSwitch：不要
			# NaviDraw：適切にvisualを書き換えたものを提示
			parts, @hash_mode = maker.naviDraw()
			body.concat(parts)

			# 履歴ファイルを書き込む
			logger()
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def external_input(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# modeの修正
			status, @hash_mode = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw：調理者がとったものに合わせたsubstepのidを提示
			parts, @hash_mode = maker.detailDraw()
			body.concat(parts)
			# Play：substep内にコンテンツが存在すれば再生命令を送る
			parts, @hash_mode = maker.play(jason_input["time"]["sec"])
			body.concat(parts)
			# Notify：substep内にコンテンツが存在すれば再生命令を送る
			parts, @hash_mode = maker.notify(jason_input["time"]["sec"])
			body.concat(parts)
			# Cancel：再生待ちコンテンツがあればキャンセル
			parts, @hash_mode = maker.cancel()
			body.concat(parts)
			# ChannelSwitch：不要
			# NaviDraw：適切にvisualを書き換えたものを提示
			parts, @hash_mode = maker.naviDraw()
			body.concat(parts)

			# 履歴ファイルを書き込む
			logger()
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end

	def channel(jason_input)
#		status = nil
		body = []
		begin
			if @hash_mode["display"] == jason_input["operation_contents"]
				p "#{@hash_mode["display"]} is displayed now. You try to display same one."
				# 履歴
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
				parts = detailDraw(@hash_mode)
				body.concat(parts)
				# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				parts, @hash_mode = play(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				body.concat(parts)
				# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				parts, @hash_mode = notify(@hash_recipe, @hash_mode, jason_input["time"]["sec"])
				body.concat(parts)
				# Cancel：不要．再生待ちコンテンツは存在しない．
				# ChannelSwitch：GUIDEを指定
				body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
				# NaviDraw：直近のナビ画面と同じものを返すことになる．
				parts = naviDraw(@hash_recipe, @hash_mode)
				body.concat(parts)
			when "MATERIALS", "OVERVIEW"
				# modeの修正
				media = ["audio", "video"]
				media.each{|v|
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "CURRENT"
							@hash_mode[v]["mode"][key][0] = "STOP"
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
				parts, @hash_mode, status = cancel(@hash_recipe, @hash_mode)
				body.concat(parts)
				# ChannelSwitch：MATERIALSを指定
				body.push({"ChannelSwitch"=>{"channel"=>"#{jason_input["operation_contents"]}"}})
				# NaviDraw：不要．Naviは描画されない
			else
				# 履歴
				logger()
				return "invalid params", body
			end
			session_id = jason_input["session_id"]
			open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
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

	def check(jason_input)
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)
			# element_nameの確認
			id = jason_input["operation_contents"]
			if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
				# modeの修正
				status, @hash_mode = maker.modeUpdate_check(jason_input["time"]["sec"], id)
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：別のsubstepに遷移するかもしれないので必要．
				parts, @hash_mode = maker.detailDraw()
				body.concat(parts)
				# Play：別のsubstepに遷移するかもしれないので必要．
				parts, @hash_mode = maker.play(jason_input["time"]["sec"])
				body.concat(parts)
				# Notify：別のsubstepに遷移するかもしれないので必要．
				parts, @hash_mode = maker.notify(jason_input["time"]["sec"])
				body.concat(parts)
				# Cancel：別のsubstepに遷移するかもしれないので必要．
				parts, @hash_mode = maker.cancel()
				body.concat(parts)
				# ChannelSwitch：不要．
				# NaviDraw：チェックされたものをis_fisnishedに書き替え，visualを適切に書き換えたものを提示
				parts, @hash_mode = maker.naviDraw()
				body.concat(parts)

				# 履歴ファイルを書き込む
				logger()
				session_id = jason_input["session_id"]
				open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
					io.puts(JSON.pretty_generate(@hash_mode))
				}
			else
				# 履歴ファイルを書き込む
				logger()
				errorLOG()
				return "invalid params", body
			end
		rescue => e
			p e
			return "internal error", body
		end

		return status, body
	end
end
