#!/usr/bin/ruby

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'
require 'lib/startaction.rb'
require 'lib/ordersmaker.rb'
require 'lib/finishaction.rb'

def navi_menu(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])
		# modeの修正
		result = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		orders = []
		# DetailDraw：入力されたstepをCURRENTとして提示
		orders.concat(maker.detailDraw())
		# Play：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
		# Notify：不要．クリックされたstepの調理行動を始めれば，EXTERNAL_INPUTで再生される
		# Cancel：再生待ちコンテンツがあればキャンセル
		orders.concat(maker.cancel())
		# ChannelSwitch：不要
		# NaviDraw：適切にvisualを書き換えたものを提示
		orders.concat(maker.naviDraw())

		# 履歴ファイルを書き込む
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def external_input(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])
		# modeの修正
		result = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		orders = []
		# DetailDraw：調理者がとったものに合わせたsubstepのidを提示
		orders.concat(maker.detailDraw)
		# Play：substep内にコンテンツが存在すれば再生命令を送る
		orders.concat(maker.play(jason_input["time"]["sec"]))
		# Notify：substep内にコンテンツが存在すれば再生命令を送る
		orders.concat(maker.notify(jason_input["time"]["sec"]))
		# Cancel：再生待ちコンテンツがあればキャンセル
		orders.concat(maker.cancel())
		# ChannelSwitch：不要
		# NaviDraw：適切にvisualを書き換えたものを提示
		orders.concat(maker.naviDraw())

		# 履歴ファイルを書き込む
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def channel(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])

		orders = []
		case jason_input["operation_contents"]
		when "GUIDE"
			# modeの修正
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "GUIDE")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw：modeUpdateしないので，最近送ったオーダーと同じDetailDrawを送ることになる．
			orders.concat(maker.detailDraw())
			# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
			orders.concat(maker.play(jason_input["time"]["sec"]))
			# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
			orders.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel：不要．再生待ちコンテンツは存在しない．
			# ChannelSwitch：GUIDEを指定
			orders.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
			# NaviDraw：直近のナビ画面と同じものを返すことになる．
			orders.concat(maker.naviDraw())

			# 履歴ファイル書き込む
			logger()
		when "MATERIALS"
			# modeの修正
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "MATERIALS")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw：不要．Detailは描画されない
			# Play：不要．再生コンテンツは存在しない
			# Notify：不要．再生コンテンツは存在しない
			# Cancel：再生待ちコンテンツがあればキャンセル
			orders.concat(maker.cancel())
			# ChannelSwitch：MATERIALSを指定
			orders.push({"ChannelSwitch"=>{"channel"=>"MATERIALS"}})
			# NaviDraw：不要．Naviは描画されない

			# 履歴ファイルを書き込む
			logger()
		when "OVERVIEW"
			# modeの更新
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "OVERVIEW")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw：不要．Detailは描画されない
			# Play：不要．再生コンテンツは存在しない
			# Notify：不要．再生コンテンツは存在しない
			# Cancel：再生待ちコンテンツがあればキャンセル
			orders.concat(maker.cancel())
			# ChannelSwitch：OVERVIEWを指定
			orders.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
			# NaviDraw：不要．Naviは描画されない

			# 履歴ファイルを書き込む
			logger()
		else
			# 履歴ファイルに書き込む
			logger()
			errorLOG()
			return {"status"=>"invalid params"}
		end
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def check(jason_input)
	begin
		orders = []
		maker = OrdersMaker.new(jason_input["session_id"])
		# element_nameの確認
		element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"])

		if element_name == "step" || element_name == "substep"
			# modeの修正
			result = maker.modeUpdate_check(jason_input["time"]["sec"], jason_input["operation_contents"])
			if result == "interlan_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw：
			orders.concat(maker.detailDraw())
			# Play：不要．チェックを入れるだけで大きな画面遷移ではない
			orders.concat(maker.play(jason_input["time"]["sec"]))
			# Notify：不要．チェックを入れるだけで大きな画面遷移ではない不要．
			orders.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel：CURRENTなsubstepをチェックされた場合，メディアを終了する必要がある．
			orders.concat(maker.cancel())
			# ChannelSwitch：不要．
			# NaviDraw：チェックされたものをis_fisnishedに書き替え，visualを適切に書き換えたものを提示
			orders.concat(maker.naviDraw())

			# 履歴ファイルを書き込む
			logger()
		else
			# 履歴ファイルを書き込む
			logger()
			errorLOG()
			return {"status"=>"invalid params"}
		end
	rescue => e
		 p e
		 return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def start(jason_input)
	# Navigationに必要なファイル（詳細はクラスファイル内）を作成
	# modeUpdateもこの関数でやってしまう
	result = start_action(jason_input["session_id"], jason_input["operation_contents"])
	if result == "internal_error"
		return {"status"=>"internal error"}
	elsif result == "invalid_params"
		return {"status"=>"invalid params"}
	end

	orders = []
	### DetailDraw：不要．Detailは描画されない
	### Play：不要．再生コンテンツは存在しない
	### Notify：不要．再生コンテンツは存在しない
	### Cancel：不要．再生待ちコンテンツは存在しない
	### ChannelSwitch：OVERVIEWを指定
	orders.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
	### NaviDraw：不要．Naviは描画されない

	# 履歴ファイルに書き込む
	logger()
	return {"status"=>"success","body"=>orders}
end

def finish(jason_input)
	begin
		# mediaをSTOPにする．
		hash_mode, result = finish_action(jason_input["session_id"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		doc = REXML::Document.new(open("records/#{jason_input["session_id"]}/#{jason_input["session_id"]}_recipe.xml"))

		### DetailDraw：不要．Detailは描画されない
		### Play：不要．再生コンテンツは存在しない
		### Notify：不要．再生コンテンツは存在しない
		### Cancel：再生待ちコンテンツが存在すればキャンセル
		orders, result = cancel(jason_input["session_id"], doc, hash_mode)
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end
		### ChannelSwitch：不要
		### NaviDraw：不要．Naviは描画されない

		# 履歴ファイルに書き込む
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def play_control(jason_input)
	begin
		element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"]["id"])
		if element_name == "audio" || element_name == "video"
			case jason_input["operation_contents"]["operation"]
			when "PLAY"
			when "PAUSE"
			when "JUMP"
			when "TO_THE_END"
			when "FULL_SCREEN"
			when "MUTE"
			when "VOLUME"
			else
				return {"status"=>"invalid params"}
			end
		else
			return {"status"=>"invalid params"}
		end

		orders = []
		### DetailDraw：不要．Detailは描画されない
		### Play：
		### Notify：
		### Cancel：
		### ChannelSwitch：不要
		### NaviDraw：不要．Naviは描画されない
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end
