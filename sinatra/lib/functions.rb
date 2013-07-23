#!/usr/bin/ruby

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'
require 'lib/startaction.rb'
require 'lib/ordersmaker.rb'

def navi_menu(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])
	# modeの修正
	maker.modeUpdate("NAVI_MENU", jason_input["time"]["sec"], jason_input["operation_contents"])

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

	return orders
end

def external_input(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])
	# modeの修正
	maker.modeUpdate("EXTERNAL_INPUT", jason_input["time"]["sec"], jason_input["operation_contents"])

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

	return orders
end

def channel(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])

	orders = []
	case jason_input["operation_contents"]
	when "GUIDE"
		# modeの修正
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 0)

		# DetailDraw：modeUpdateしないので，最近送ったオーダーと同じDetailDrawを送ることになる．
		orders.concat(maker.detailDraw())
		# Play：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
		orders.concat(maker.play(jason_input["time"]["sec"]))
		# Notify：STARTからoverviewを経てguideに移る場合，メディアの再生が必要かもしれない．
		orders.concat(maker.notify(jason_input["time"]["sec"]))
		# Cancel：不要．再生待ちコンテンツは存在しない．
		# ChannelSwitch：GUIDEを指定
		orders.concat(maker.channelSwitch("GUIDE"))
		# NaviDraw：直近のナビ画面と同じものを返すことになる．
		orders.concat(maker.naviDraw())

		# 履歴ファイル書き込む
		logger()
	when "MATERIALS"
		# modeの修正
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 1)

		# DetailDraw：不要．Detailは描画されない
		# Play：不要．再生コンテンツは存在しない
		# Notify：不要．再生コンテンツは存在しない
		# Cancel：再生待ちコンテンツがあればキャンセル
		orders.concat(maker.cancel())
		# ChannelSwitch：MATERIALSを指定
		orders.concat(maker.channelSwitch("MATERIALS"))
		# NaviDraw：不要．Naviは描画されない

		# 履歴ファイルを書き込む
		logger()
	when "OVERVIEW"
		# modeの更新
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 1)

		# DetailDraw：不要．Detailは描画されない
		# Play：不要．再生コンテンツは存在しない
		# Notify：不要．再生コンテンツは存在しない
		# Cancel：再生待ちコンテンツがあればキャンセル
		orders.concat(maker.cancel())
		# ChannelSwitch：OVERVIEWを指定
		orders.concat(maker.channelSwitch("OVERVIEW"))
		# NaviDraw：不要．Naviは描画されない

		# 履歴ファイルを書き込む
		logger()
	else
		# 全てのOrderが不要．空のOrderを返す？
		orders = [{}]
		# 履歴ファイルに書き込む
		logger()
		errorLOG()
	end
	return orders
end

def check(jason_input)
	orders = []
	maker = OrdersMaker.new(jason_input["session_id"])
	# element_nameの確認
	element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"])

	if element_name == "audio" or element_name == "video" then
		# modeの修正
		# idをcancelに直接ぶち込んでもいいが，notificationが終わっているかの確認をmodeUpdateの中でやるので仕方なく
		maker.modeUpdate("CHECK", jason_input["time"]["sec"], jason_input["operation_contents"])

		# DetailDraw：不要
		# Play：不要
		# Notify：不要
		# Cancel：指定されたidをキャンセル
		orders.concat(maker.cancel())
		# ChannelSwitch：不要．
		# NaviDraw：不要

		# 履歴ファイルを書き込む
		logger()
	elsif element_name == "step" or element_name == "substep" then
		# modeの修正
		maker.modeUpdate("CHECK", jason_input["time"]["sec"], jason_input["operation_contents"])

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
		# 全てのOrderが不要．空のOrderを返す？
		orders = [{}]

		# 履歴ファイルを書き込む
		logger()
		errorLOG()
	end
	return orders
end

def start(jason_input)
	# Navigationに必要なファイル（詳細はクラスファイル内）を作成
	start_action(jason_input["session_id"], jason_input["operation_contents"])
	maker = OrdersMaker.new(jason_input["session_id"])
	# modeファイルをSTARTな状態に設定
	maker.modeUpdate("START", jason_input["time"]["sec"])

	orders = []
	### DetailDraw：不要．Detailは描画されない
	### Play：不要．再生コンテンツは存在しない
	### Notify：不要．再生コンテンツは存在しない
	### Cancel：不要．再生待ちコンテンツは存在しない
	### ChannelSwitch：OVERVIEWを指定
	orders.concat(maker.channelSwitch("OVERVIEW"))
	### NaviDraw：不要．Naviは描画されない

	# 履歴ファイルに書き込む
	logger()
	return orders
end

def finish(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])

	# mediaをSTOPにする
	maker.modeUpdate("END", jason_input["time"]["sec"])

	orders = []
	### DetailDraw：不要．Detailは描画されない
	### Play：不要．再生コンテンツは存在しない
	### Notify：不要．再生コンテンツは存在しない
	### Cancel：再生待ちコンテンツが存在すればキャンセル
	orders.concat(maker.cancel())
	### ChannelSwitch：不要
	### NaviDraw：不要．Naviは描画されない

	# 履歴ファイルに書き込む
	logger()
	return orders
end
