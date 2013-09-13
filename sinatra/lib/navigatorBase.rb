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
		if @hash_recipe["step"].key?(id) || @hash_recipe["substep"].key?(id)
			# modeの修正
			modeUpdate_check(jason_input["time"]["sec"], id)
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
		return "success", body
	rescue => e
		return "internal error", e
	end

	def finish(jason_input)
		body = []
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
		body = cancel
		### ChannelSwitch：不要
		### NaviDraw：不要

		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
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

#		session_id = jason_input["session_id"]
#		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
#			io.puts(JSON.pretty_generate(@hash_mode))
#		}
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
		@hash_mode["substep"]["mode"].each{|key, value|
			if value[2] == "CURRENT"
				orders.push({"DetailDraw"=>{"id"=>key}})
				break
			end
		}
		return orders
	end

	# CURRENTなaudioとvideoを再生させるPlay命令．
	def play(time)
		orders = []
		media = ["audio", "video"]
		media.each{|v|
			@hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT"
					# triggerの数が1個以上のとき．
					if @hash_recipe[v][key].key?("trigger")
						# triggerが複数個の場合，どうするのか考えていない．
						orders.push({"Play"=>{"id"=>key, "delay"=>@hash_recipe[v][key]["trigger"][0][2].to_i}})
						finish_time = time + @hash_recipe[v][key]["trigger"][0][2].to_i * 1000
						@hash_mode[v]["mode"][key][1] = finish_time
					else # triggerが0個のとき．
						# triggerが無い場合は再生命令は出さないが，hash_modeはどう変更するのか考えていない．
						# @hash_mode[v]["mode"][key][1] = ?
						return []
					end
				end
			}
		}
		return orders
	end

	# CURRENTなnotificationを再生させるNotify命令．
	def notify(time)
		orders = []
		@hash_mode["notification"]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# notificationはtriggerが必ずある．
				# triggerが複数個の場合，どうするのか考えていない．
				orders.push({"Notify"=>{"id"=>key, "delay"=>@hash_recipe["notification"][key]["trigger"][0][2].to_i}})
				finish_time = time + @hash_recipe["notification"][key]["trigger"][0][2].to_i * 1000
				# notificationは特殊なので，特別にKEEPに変更する．
				@hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
			end
		}
		return orders
	end

	# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
	def cancel(*id)
		orders = []
		# 特に中止させるメディアについて指定が無い場合
		if id == []
			# audioとvideoの処理．
			# Cancelさせるべきものは，STOPになっているはず．
			media = ["audio", "video"]
			media.each{|v|
				if @hash_mode.key?(v)
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOPからFINISHEDに変更．
							@hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notificationの処理．
			# Cancelさせるべきものは，STOPのなっているはず．
			if @hash_mode.key?("notification")
				@hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOPからFINISHEDに変更．
						@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audioをもつnotificationの場合，audioもFINISHEDに変更．
						if @hash_recipe["notification"][key].key?("audio")
							audio_id = @hash_recipe["notification"][key]["audio"]
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # 中止させるメディアについて指定がある場合．
			id.each{|v|
				# 指定されたメディアのelement nameを調査．
				element_name = search_ElementName(@hash_recipe, v)
				# audioとvideoの場合．
				if @hash_recipe["audio"].key?(v) || @hash_recipe["video"].key?(v)
					# 指定されたものが再生待ちかどうかとりあえず調べる，
					if @hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif @hash_recipe["notification"].key?(v) # notificationの場合．
					# 指定されたnotificationが再生待ちかどうかとりあえず調べる．
					if @hash_mode["notification"]["mode"][v][0] == "KEEP"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audioを持つnotificationはaudioもFINISHEDに．
						if @hash_recipe["notification"][v].key?("audio")
							audio_id = @hash_recipe["notification"][v]["audio"]
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				end
			}
		end
		return orders
	end

	# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw
		# sorted_stepの順に表示させる．
		orders = []
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		@hash_recipe["sorted_step"].each{|v|
			id = v[1]
			visual = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual = "CURRENT"
			else
				visual = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
			end
			# CURRENTなstepの場合，substepも表示させる．
			if visual == "CURRENT"
				@hash_recipe["step"][id]["substep"].each{|id|
					visual = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual = "CURRENT"
					else
						visual = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
					else
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
					end
				}
			end
		}
		return orders
	end

	##############################################################
	##### modeのupdate処理が複雑なCHECKメソッドのmodeUpdater #####
	##############################################################

	def modeUpdate_check(time, id)
		# チェックされたものによって場合分け．
		# 上位メソッドで判定しているので，idとしてstepまたはsubstep以外が入力されることはない．
		if @hash_recipe["step"].key?(id)
			# is_finishedまたはNOT_YETの操作．
			if @hash_mode["step"]["mode"][id][1] == "NOT_YET" # NOT_YETならis_finishedに．
				# チェックされたstepをis_finishedに．
				@hash_mode["step"]["mode"][id][1] = "is_finished"
				# チェックされたstepに含まれるsubstepを全てis_finishedに．
				@hash_recipe["step"][id]["substep"].each{|substep_id|
					@hash_mode["substep"]["mode"][substep_id][1] = "is_finished"
					# substepに含まれるメディアをFINISHEDにする．
					# もしも現状でCURRENTまたはKEEPだったら，再生待ちまたは再生中なのでSTOPにする．
					media = ["audio", "video", "notification"]
					media.each{|v|
						if @hash_recipe["substep"][substep_id].key?(v)
							@hash_recipe["substep"][substep_id][v].each{|media_id|
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						end
					}
				}
				#
				# 本当は，チェックされたstepがparentに持つstepもis_finishedにしなければならない．
				#
			else # is_finishedならNOT_YETに．
				# チェックされたstepをNOT_YETに．
				@hash_mode["step"]["mode"][id][1] = "NOT_YET"
				# チェックされたstepに含まれるsubstepを全てNOT_YETに．
				@hash_recipe["step"][id]["substep"].each{|substep_id|
					@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
					# substepに含まれるメディアをNOT_YETにする．
					media = ["audio", "video", "notification"]
					media.each{|v|
						if @hash_recipe["substep"][substep_id].key?(v)
							@hash_recipe["substep"][substep_id][v].each{|media_id|
								@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
							}
						end
					}
				}
				#
				# 本当は，チェックされたstepをparentに持つstepもNOT_YETにしなければならない．
				#
			end
		elsif @hash_recipe["substep"].key?(id)
			# is_finishedまたはNOT_YETの操作．
			if @hash_mode["substep"]["mode"][id][1] == "NOT_YET" # NOT_YETならばis_finishedに．
				parent_step = @hash_recipe["substep"][id]["parent_step"]
				media = ["audio", "video", "notification"]
				# チェックされたsubstepを含めそれ以前のsubstep全てをis_finishedに．
				@hash_recipe["step"][parent_step]["substep"].each{|child_substep|
					@hash_mode["substep"]["mode"][child_substep][1] = "is_finished"
					# そのsubstepに含まれるメディアをFINISHEDに．
					# もしも現状でCURRENTまたはKEEPならば，再生中または再生待ちなのでSTOPに．
					media.each{|v|
						if @hash_recipe["substep"][child_substep].key?(v)
							@hash_recipe["substep"][child_substep][v].each{|media_id|
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						end
					}
					# チェックされたsubstepをis_finishedにしたらループ終了．
					if child_substep == id
						# チェックされたsubstepがstep内の最終substepならば，親ノードもis_finishedにする．
						if @hash_recipe["step"][parent_step]["substep"].last == id
							@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
						end
						break
					end
				}
				#
				# かつ，is_finishedとなったstepがparentにもつstepもis_finishedにしなければならない
				#
			else # is_finishedならばNOT_YETに．
				parent_step = @hash_recipe["substep"][id]["parent_step"]
				media = ["audio", "video", "notification"]
				# チェックされたsubstepを含むそれ以降の（同一step内の）substepをNOT_YETに．
				flag = -1
				@hash_recipe["step"][parent_step]["substep"].each{|child_substep|
					if flag == 1 || child_substep == id
						flag = 1
						@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
						# そのsubstepに含まれるメディアをNOT_YETに．
						media.each{|v|
							if @hash_recipe["substep"][child_substep].key?(v)
								@hash_recipe["substep"][child_substep][v].each{|media_id|
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							end
						}
					end
				}
				# 親ノードのstepを明示的にNOT_YETにする．
				@hash_mode["step"]["mode"][parent_step][1] = "NOT_YET"
				#
				# かつ，NOT_YETとなったstepをparentにもつstepもNOT_YETにしなければならない
				#
			end
		end
		# ABLEまたはOTHERSの操作のために，CURRENTなstepとsubstepのidを調べる．
		current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
		# ABLEまたはOTHERSの操作．
		@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
		# 全てis_finishedならばCURRENT探索はしない
		flag = -1
		@hash_mode["step"]["mode"].each{|key, value|
			if value[1] == "NOT_YET"
				flag = 1
				break
			end
		}
		if flag == 1 # NOT_YETなstepが存在する場合のみ，CURRENTの移動を行う
			# 可能なsubstepに遷移する
			@hash_mode = go2current(@hash_recipe, @hash_mode, current_step, current_substep)
			# 再度ABLEの判定を行う
			current_step, current_substep = search_CURRENT(@hash_recipe, @hash_mode)
			# ABLEまたはOTHERSの操作．
			@hash_mode = set_ABLEorOTHERS(@hash_recipe, @hash_mode, current_step, current_substep)
		end
		# notificationが再生済みかどうかは，隙あらば調べましょう．
		@hash_mode = check_notification_FINISHED(@hash_recipe, @hash_mode, time)
	end
end
