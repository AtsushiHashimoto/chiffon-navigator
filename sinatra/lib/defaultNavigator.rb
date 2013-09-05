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
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# modeの修正
			status = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw：入力されたstepをCURRENTとして提示
			body.concat(maker.detailDraw())
			# Play：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
			# Notify：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
			# Cancel：再生待ちコンテンツがあればキャンセル
			body.concat(maker.cancel())
			# ChannelSwitch：不要
			# NaviDraw：適切にvisualを書き換えたものを提示
			body.concat(maker.naviDraw())

			# 履歴ファイルを書き込む
			logger()
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
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# modeの修正
			status = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
			if status == "internal error"
				return status, body
			elsif status == "invalid params"
				return status, body
			end

			# DetailDraw：調理者がとったものに合わせたsubstepのidを提示
			body.concat(maker.detailDraw)
			# Play：substep内にコンテンツが存在すれば再生命令を送る
			body.concat(maker.play(jason_input["time"]["sec"]))
			# Notify：substep内にコンテンツが存在すれば再生命令を送る
			body.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel：再生待ちコンテンツがあればキャンセル
			body.concat(maker.cancel())
			# ChannelSwitch：不要
			# NaviDraw：適切にvisualを書き換えたものを提示
			body.concat(maker.naviDraw())

			# 履歴ファイルを書き込む
			logger()
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
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)

			case jason_input["operation_contents"]
			when "GUIDE"
				# modeの修正
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "GUIDE")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：modeUpdateしないので，最近送ったオーダーと同じDetailDrawを送ることになる．
				body.concat(maker.detailDraw())
				# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				body.concat(maker.play(jason_input["time"]["sec"]))
				# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
				body.concat(maker.notify(jason_input["time"]["sec"]))
				# Cancel：不要．再生待ちコンテンツは存在しない．
				# ChannelSwitch：GUIDEを指定
				body.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
				# NaviDraw：直近のナビ画面と同じものを返すことになる．
				body.concat(maker.naviDraw())

				# 履歴ファイル書き込む
				logger()
			when "MATERIALS"
				# modeの修正
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "MATERIALS")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：不要．Detailは描画されない
				# Play：不要．再生コンテンツは存在しない
				# Notify：不要．再生コンテンツは存在しない
				# Cancel：再生待ちコンテンツがあればキャンセル
				body.concat(maker.cancel())
				# ChannelSwitch：MATERIALSを指定
				body.push({"ChannelSwitch"=>{"channel"=>"MATERIALS"}})
				# NaviDraw：不要．Naviは描画されない

				# 履歴ファイルを書き込む
				logger()
			when "OVERVIEW"
				# modeの更新
				status = maker.modeUpdate_channel(jason_input["time"]["sec"], "OVERVIEW")
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：不要．Detailは描画されない
				# Play：不要．再生コンテンツは存在しない
				# Notify：不要．再生コンテンツは存在しない
				# Cancel：再生待ちコンテンツがあればキャンセル
				body.concat(maker.cancel())
				# ChannelSwitch：OVERVIEWを指定
				body.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
				# NaviDraw：不要．Naviは描画されない

				# 履歴ファイルを書き込む
				logger()
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
			maker = OrdersMaker.new(jason_input["session_id"], @hash_recipe)
			# element_nameの確認
			id = jason_input["operation_contents"]
			if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
				# modeの修正
				status = maker.modeUpdate_check(jason_input["time"]["sec"], id)
				if status == "internal error"
					return status, body
				elsif status == "invalid params"
					return status, body
				end

				# DetailDraw：別のsubstepに遷移するかもしれないので必要．
				body.concat(maker.detailDraw())
				# Play：別のsubstepに遷移するかもしれないので必要．
				body.concat(maker.play(jason_input["time"]["sec"]))
				# Notify：別のsubstepに遷移するかもしれないので必要．
				body.concat(maker.notify(jason_input["time"]["sec"]))
				# Cancel：別のsubstepに遷移するかもしれないので必要．
				body.concat(maker.cancel())
				# ChannelSwitch：不要．
				# NaviDraw：チェックされたものをis_fisnishedに書き替え，visualを適切に書き換えたものを提示
				body.concat(maker.naviDraw())

				# 履歴ファイルを書き込む
				logger()
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
