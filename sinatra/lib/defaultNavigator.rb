#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/navigatorBase.rb'
require 'lib/ordersmaker.rb'
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
		status = nil
		body = []
		begin
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe, @hash_mode)

			case jason_input["operation_contents"]
			when "GUIDE"
				# modeの修正
				status, @hash_mode = maker.modeUpdate_channel(jason_input["time"]["sec"], "GUIDE")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：modeUpdateしないので，最近送ったオーダーと同じDetailDrawを送ることになる．
				parts, @hash_mode = maker.detailDraw()
				body.concat(parts)
				# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				parts, @hash_mode = maker.play(jason_input["time"]["sec"])
				body.concat(parts)
				# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				parts, @hash_mode = maker.notify(jason_input["time"]["sec"])
				body.concat(parts)
				# Cancel：不要．再生待ちコンテンツは存在しない．
				# ChannelSwitch：GUIDEを指定
				body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
				# NaviDraw：直近のナビ画面と同じものを返すことになる．
				parts, @hash_mode = maker.naviDraw()
				body.concat(parts)

				# 履歴ファイル書き込む
				logger()
				session_id = jason_input["session_id"]
				open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
					io.puts(JSON.pretty_generate(@hash_mode))
				}
			when "MATERIALS"
				# modeの修正
				status, @hash_mode = maker.modeUpdate_channel(jason_input["time"]["sec"], "MATERIALS")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：不要．Detailは描画されない
				# Play：不要．再生コンテンツは存在しない
				# Notify：不要．再生コンテンツは存在しない
				# Cancel：再生待ちコンテンツがあればキャンセル
				parts, @hash_mode = maker.cancel()
				body.concat(parts)
				# ChannelSwitch：MATERIALSを指定
				body.push({"ChannelSwitch"=>{"channel"=>"MATERIALS"}})
				# NaviDraw：不要．Naviは描画されない

				# 履歴ファイルを書き込む
				logger()
				session_id = jason_input["session_id"]
				open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
					io.puts(JSON.pretty_generate(@hash_mode))
				}
			when "OVERVIEW"
				# modeの更新
				status, @hash_mode = maker.modeUpdate_channel(jason_input["time"]["sec"], "OVERVIEW")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：不要．Detailは描画されない
				# Play：不要．再生コンテンツは存在しない
				# Notify：不要．再生コンテンツは存在しない
				# Cancel：再生待ちコンテンツがあればキャンセル
				parts, @hash_mode = maker.cancel()
				body.concat(parts)
				# ChannelSwitch：OVERVIEWを指定
				body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
				# NaviDraw：不要．Naviは描画されない

				# 履歴ファイルを書き込む
				logger()
				session_id = jason_input["session_id"]
				open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
					io.puts(JSON.pretty_generate(@hash_mode))
				}
			else
				# 履歴ファイルに書き込む
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
