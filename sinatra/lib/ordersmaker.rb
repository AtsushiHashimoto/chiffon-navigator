#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

class OrdersMaker
	def initialize(input)
		@session_id = input
		@hash_mode = Hash.new()
		open("records/#{@session_id}/#{@session_id}_mode.txt", "r"){|io|
			@hash_mode = JSON.load(io)
		}
		@sorted_step = []
		open("records/#{@session_id}/#{@session_id}_sortedstep.txt", "r"){|io|
			@sorted_step = JSON.load(io)
		}
		@doc = REXML::Document.new(open("records/#{@session_id}/#{@session_id}_recipe.xml"))
	end

	# CURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
	def detailDraw
		orders = []
		@hash_mode["substep"]["mode"].each{|key, value|
			# CURRENなsubstepは一つだけ（のはず）．
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
					if @doc.elements["//#{v}[@id=\"#{key}\"]/trigger[1]"] != nil
						# triggerが複数個の場合，どうするのか考えていない．
						@doc.get_elements("//#{v}[@id=\"#{key}\"]/trigger[1]").each{|node|
							orders.push({"Play"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
							finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
							@hash_mode[v]["mode"][key][1] = finish_time
						}
					else # triggerが0個のとき．
						# triggerが無い場合は再生命令は出さないが，hash_modeはどう変更するのか考えていない．
						# @hash_mode[v]["mode"][key][1] = ?
						return []
					end
				end
			}
		}
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
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
				@doc.get_elements("//notification[@id=\"#{key}\"]/trigger[1]").each{|node|
					orders.push({"Notify"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
					finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
					# notificationは特殊なので，特別にKEEPに変更する．
					@hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
				}
			end
		}
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
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
						if @doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = @doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # 中止させるメディアについて指定がある場合．
			id.each{|v|
				# 指定されたメディアのelement nameを調査．
				element_name = searchElementName(@session_id, v)
				# audioとvideoの場合．
				if element_name == "audio" || element_name == "video"
					# 指定されたものが再生待ちかどうかとりあえず調べる，
					if @hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notificationの場合．
					# 指定されたnotificationが再生待ちかどうかとりあえず調べる．
					if @hash_mode["notification"]["mode"][v][0] == "KEEP"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audioを持つnotificationはaudioもFINISHEDに．
						if @doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = @doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # 指定されたものがaudio，video，notificationで無い場合．
					return [{}]
				end
			}
		end
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return orders
	end

	# ナビ画面の表示を決定するNaviDraw命令．
	def naviDraw
		# sorted_stepの順に表示させる．
		orders = Array.new()
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		flag = 0
		@sorted_step.each{|v|
			id = v[1]
			visual = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT"
				visual = "CURRENT"
			elsif @hash_mode["step"]["mode"][id][2] == "NOT_CURRENT"
				visual = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET"
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
			end
			# CURRENTなstepの場合，substepも表示させる．
			if visual == "CURRENT"
				if flag == 1
					p "error" # CURRENTなstepが複数個ある場合，エラーを吐く？考えていない．
				end
				@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
					id = node.attributes.get_attribute("id").value
					visual = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT"
						visual = "CURRENT"
					elsif @hash_mode["substep"]["mode"][id][2] == "NOT_CURRENT"
						visual = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
					elsif @hash_mode["substep"]["mode"][id][1] == "NOT_YET"
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
					end
				}
				flag = 1
			end
		}
		return orders
	end

	# NAVI_MENUリクエストの場合のmodeアップデート
	def modeUpdate_navimenu(time, id)
		begin
			unless @hash_mode["display"] == "GUIDE"
				p "#{@hash_mode["display"]} is displayed now."
				return "invalid_params"
			end
			element_name = searchElementName(@session_id, id)
			# 遷移要求先がstepかsubstepかで場合分け
			case element_name
			when "step"
				# まずは，CURRENT，NOT_CURRENTの操作．
				# 現状でCURRENTなsubstepをNOT_CURRENTにする．
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
						# substepに含まれるaudio，videoは再生済み・再生中・再生待ち関わらずSTOPに．
						media = ["audio", "video"]
						media.each{|v|
							@hash_mode[v]["mode"].each{|key, value|
								if value[0] == "CURRENT"
									@hash_mode[v]["mode"][key][0] = "STOP"
								end
							}
						}
						break # CURRENTなsubstepは一つだけのはず．
					end
				}
				# 現状でCURRENTだったstepをNOT_CURRENTにする．
				@hash_mode["step"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["step"]["mode"][key][2] = "NOT_CURRENT"
						break # CURRENTなstepは一つだけのはず．
					end
				}
				# クリックされたstepをCURRENTに．
				@hash_mode["step"]["mode"][id][2] = "CURRENT"
				# クリックされたstep内でNOT_YETなsubstepの一番目をCURRENTに．
				# NOT_YETなsubstepが存在しなければ，第一番目のsubstepをCURRENTに．
				current_substep = nil
				@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
					substep_id = node.attributes.get_attribute("id").value
					if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
						current_substep = node.attributes.get_attribute("id").value
						break
					else
						next
					end
				}
				if current_substep != nil # NOT_YETなsubstepが存在する．
					# 一番目にNOT_YETなsubstepをCURRENTに．
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
				else # NOT_YETなsubstepが存在しない．
					# 一番目の(is_finishedな)substepをCURRENTに．
					current_substep = @doc.elements["//step[@id=\"#{id}\"]/substep[1]"].attributes.get_attribute("id").value
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
				end
				# クリックされた先のメディアは再生させない．
				# stepとsubstepを適切にABLEにする．
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, id, current_substep)
			when "substep"
				# まずは，CURRENT，NOT_CURRENTの操作．
				# 現状でCURRENTなsubstepをNOT_CURRENTに．
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT"
						@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
						# substepに含まれるaudio，videoは再生済み・再生中・再生待ち関わらずSTOPに．
						media = ["audio", "video"]
						media.each{|v|
							@hash_mode[v]["mode"].each{|key, value|
								if value[0] == "CURRENT"
									@hash_mode[v]["mode"][key][0] = "STOP"
								end
							}
						}
						break
					end
				}
				# クリックされたsubstepをCURRENTに．
				@hash_mode["substep"]["mode"][id][2] = "CURRENT"
				# CURRENTなstepの探索．
				current_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
				# stepとsubstepを適切にABLEにする．
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, id)
			else # 遷移要求先がおかしい．
				return "invalid_params"
			end
			# notificationが再生済みかどうかは，隙あらば調べましょう．
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	# EXTERNAL_INPUTリクエストの場合のmodeアップデート
	def modeUpdate_externalinput(time, id)
		begin
			element_name = searchElementName(@session_id, id)
			# 入力されたidがnotificationの場合．
			if element_name == "notification"
				# 指定されたnotificationが未再生なら再生命令と判断してCURRENTに．
				if @hash_mode["notification"]["mode"][id][0] == "NOT_YET"
					@hash_mode["notification"]["mode"][id][0] = "CURRENT"
				elsif @hash_mode["notification"]["mode"][id][0] == "KEEP" # 指定されたnotificationが再生待機中ならCancel命令と判断してSTOPに．
					@hash_mode["notification"]["mode"][id][0] = "STOP"
				end
			else
				# 優先度順に，入力されたオブジェクトをトリガーとするsubstepを探索．
				current_substep = nil
				@sorted_step.each{|v|
					flag = -1
					# ABLEなstepの中のNOT_YETなsubstepから探索．（現状でCURRENTなsubstepも探索対象．一旦オブジェクトを置いてまたやり始めただけかもしれない．）
					if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
						@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node1|
							substep_id = node1.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
								@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
									if node2.attributes.get_attribute("ref").value == id
										current_substep = node2.parent.attributes.get_attribute("id").value
										flag = 1
										break # trigger探索からのbreak
									end
								}
							end
							if flag == 1
								break # substep探索からのbreak
							end
						}
					elsif @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" && @hash_mode["step"]["mode"][v[1]][2] == "CURRENT" # ABLEでなくても，navi_menu等でCURRENTなstepも探索対象
						@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
								@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
									if node2.attributes.get_attribute("ref").value == id
										current_substep = node2.parent.attributes.get_attribute("id").value
										flag = 1
										break
									end
								}
							end
							if flag == 1
								break
							end
						}
					end
					if flag == 1
						break # step探索からのbreak
					end
				}
				previous_substep = nil
				if current_substep == nil
					@hash_mode["substep"]["mode"].each{|key, value|
						if value[2] == "CURRENT"
							previous_substep = key
							break
						end
					}
					if @hash_mode["substep"]["mode"][previous_substep][0] == "ABLE"
						if @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node != nil
							current_substep = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node.attributes.get_attribute("id").value
						else
							parent_id = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].parent.attributes.get_attribute("id").value
							@sorted_step.each{|v|
								if v[1] != parent_id && @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
									@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
										substep_id = node.attributes.get_attribute("id").value
										if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
											current_substep = substep_id
											break
										end
									}
									break
								end
							}
						end
					else
						@sorted_step.each{|v|
							if @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
								@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
									substep_id = node.attributes.get_attribute("id").value
									if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
										previous_substep = substep_id
										break
									end
								}
								break
							end
						}
					end
				end
				if current_substep == nil
					# Do nothing
				else
					# 現状でCURRENTなsubstepをNOT_CURRENTかつis_finishedに．
					previous_substep = nil
					@hash_mode["substep"]["mode"].each{|key, value|
						if value[2] == "CURRENT"
							previous_substep = key
							if previous_substep != current_substep
								@hash_mode["substep"]["mode"][previous_substep][2] = "NOT_CURRENT"
								@hash_mode["substep"]["mode"][previous_substep][1] = "is_finished"
								# 子の時点ではメディアはSTOPしない．
								# 親ノードもNOT_CURRENTにする．かつ，上記のsubstepがstep内で最後のsubstepであれば，stepをis_finishedにする．
								parent_step = @doc.elements["//substep[@id=\"#{previous_substep}\"]"].parent.attributes.get_attribute("id").value
								@hash_mode["step"]["mode"][parent_step][2] = "NOT_CURRENT"
								if @doc.elements["//substep[@id=\"#{previous_substep}\"]"].next_sibling_node == nil
									@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
								end
							end
							break
						end
					}
					# 次にCURRENTとなるsubstepをCURRENTに．
					@hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
					current_step = @doc.elements["//substep[@id=\"#{current_substep}\"]"].parent.attributes.get_attribute("id").value
					@hash_mode["step"]["mode"][current_step][2] = "CURRENT"
					# 現状でCURRENTなsubstepと次にCURRENTなsubstepが異なる場合は，メディアを再生させる．
					if current_substep != previous_substep
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{current_substep}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "CURRENT"
								end
							}
						}
						# previous_substepのメディアはSTOPする．
						media = ["audio", "video"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{previous_substep}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								@hash_mode[v]["mode"][media_id][0] = "STOP"
							}
						}
					end
					# stepとsubstepを適切にABLEに．
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
					# notificationが再生済みかどうかは，隙あらば調べましょう
					@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
				end
			end
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	# CHANNELリクエストの場合のmpodeアップデート
	def modeUpdate_channel(time, flag)
		begin
			if @hash_mode["display"] == flag
				p "#{@hash_mode["display"]} is displayed now. You try to display same one."
				return "invalid_params"
			end
			# CURRENTなaudioとvideoをSTOPする．
			# notificationはSTOPしない．
			if flag == "MATERIALS" || flag == "OVERVIEW"
				media = ["audio", "video"]
				media.each{|v|
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "CURRENT"
							@hash_mode[v]["mode"][key][0] = "STOP"
						end
					}
				}
			end
			# notificationが再生済みかどうかは，隙あらば調べましょう．
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			# チャンネルの切り替え
			@hash_mode["display"] = flag
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			p e
			return "internal_error"
		end

		return "success"
	end

	def modeUpdate_check(time, id)
		begin
			unless @hash_mode["display"] == "GUIDE"
				p "#{@hash_mode["display"]} is displayed now."
				return "invalid_params"
			end
			element_name = searchElementName(@session_id, id)
			# チェックされたものによって場合分け．
			case element_name
			when "step"
				# is_finishedまたはNOT_YETの操作．
				if @hash_mode["step"]["mode"][id][1] == "NOT_YET" # NOT_YETならis_finishedに．
					# チェックされたstepをis_finishedに．
					@hash_mode["step"]["mode"][id][1] = "is_finished"
					# チェックされたstepに含まれるsubstepを全てis_finishedに．
					@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][substep_id][1] = "is_finished"
						# substepに含まれるメディアをFINISHEDにする．
						# もしも現状でCURRENTまたはKEEPだったら，再生待ちまたは再生中なのでSTOPにする．
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						}
					}
					#
					#
					# 本当は，チェックされたstepがparentに持つstepもis_finishedにしなければならない．
					#
					#
				else # is_finishedならNOT_YETに．
					# チェックされたstepをNOT_YETに．
					@hash_mode["step"]["mode"][id][1] = "NOT_YET"
					# チェックされたstepに含まれるsubstepを全てNOT_YETに．
					@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
						# substepに含まれるメディアをNOT_YETにする．
						media = ["audio", "video", "notification"]
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
								media_id = node.attributes.get_attribute("id").value
								@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
							}
						}
					}
					#
					#
					# 本当は，チェックされたstepをparentに持つstepもNOT_YETにしなければならない．
					#
					#
#					@hash_mode["step"]["mode"].each{|key, value|
#						if value[1] == "is_finished"
#							if @doc.elements["//step[@id=\"#{key}\"]/parent"] != nil
#								@doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
#									if v == id
#										@hash_mode["step"]["mode"][key][1] = "NOT_YET"
#										# NOT_YETにされたstepに含まれるsubstepを全てNOT_YETに．
#										@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
#											substep_id = node.attributes.get_attribute("id").value
#											@hash_mode["substep"]["mode"][substep_id][1] = "NOT_YET"
#											# substepに含まれるメディアをNOT_YETにする．
#											media = ["audio", "video", "notification"]
#											media.each{|v|
#												@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
#													media_id = node.attributes.get_attribute("id").value
#													@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
#												}
#											}
#										}
#										break
#									end
#								}
#							end
#						end
#					}
				end
				# ABLEまたはOTHERSの操作のために，CURRENTなstepとsubstepのidを調べる．
				current_step, current_substep = search_CURRENT(@doc, @hash_mode)
				# ABLEまたはOTHERSの操作．
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
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
					@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
					# 再度ABLEの判定を行う
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# ABLEまたはOTHERSの操作．
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
				end
			when "substep"
				# is_finishedまたはNOT_YETの操作．
				if @hash_mode["substep"]["mode"][id][1] == "NOT_YET" # NOT_YETならばis_finishedに．
					parent_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
					media = ["audio", "video", "notification"]
					# チェックされたsubstepを含めそれ以前のsubstep全てをis_finishedに．
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node1|
						child_substep = node1.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][child_substep][1] = "is_finished"
						# そのsubstepに含まれるメディアをFINISHEDに．
						# もしも現状でCURRENTまたはKEEPならば，再生中または再生待ちなのでSTOPに．
						media.each{|v|
							@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
								media_id = node2.attributes.get_attribute("id").value
								if @hash_mode[v]["mode"][media_id][0] == "NOT_YET"
									@hash_mode[v]["mode"][media_id][0] = "FINISHED"
								elsif @hash_mode[v]["mode"][media_id][0] == "CURRENT" || @hash_mode[v]["mode"][media_id][0] == "KEEP"
									@hash_mode[v]["mode"][media_id][0] = "STOP"
								end
							}
						}
						# チェックされたsubstepをis_finishedにしたらループ終了．
						if child_substep == id
							# チェックされたsubstepがstep内の最終substepならば，親ノードもis_finishedにする．
							if node1.next_sibling_node == nil
								@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
							end
							break
						end
					}
					# currentの探索
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# stepとsubstepを適切にABLEに．
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
					#
					#
					# かつ，is_finishedとなったstepがparentにもつstepもis_finishedにしなければならない
					#
					#
				else # is_finishedならばNOT_YETに．
					parent_step = @doc.elements["//substep[@id=\"#{id}\"]"].parent.attributes.get_attribute("id").value
					media = ["audio", "video", "notification"]
					# チェックされたsubstepを含むそれ以降の（同一step内の）substepをNOT_YETに．
					flag = -1
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node|
						child_substep = node.attributes.get_attribute("id").value
						if flag == 1
							@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
							# そのsubstepに含まれるメディアをNOT_YETに．
							media.each{|v|
								@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
									media_id = node2.attributes.get_attribute("id").value
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							}
						end
						if child_substep == id
							flag = 1
							@hash_mode["substep"]["mode"][child_substep][1] = "NOT_YET"
							# そのsubstepに含まれるメディアをNOT_YETに．
							media.each{|v|
								@doc.get_elements("//substep[@id=\"#{child_substep}\"]/#{v}").each{|node2|
									media_id = node2.attributes.get_attribute("id").value
									@hash_mode[v]["mode"][media_id][0] = "NOT_YET"
								}
							}
						end
					}
					# 親ノードのstepを明示的にNOT_YETにして，ABLEの操作をする．
					@hash_mode["step"]["mode"][parent_step][1] = "NOT_YET"
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, parent_step, id)
					#
					#
					# かつ，NOT_YETとなったstepをparentにもつstepもNOT_YETにしなければならない
					#
					#
				end
				flag = -1
				@hash_mode["step"]["mode"].each{|key,value|
					if value[1] == "NOT_YET"
						flag = 1
						break
					end
				}
				if flag == 1
					# currentの探索
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# 可能なsubstepに遷移する
					@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
					# 再度currentの探索
					current_step, current_substep = search_CURRENT(@doc, @hash_mode)
					# ABLEの設定
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
				end
			else
				return "invalid_params"
			end
			# notificationが再生済みかどうかは，隙あらば調べましょう．
			@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
			open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
				io.puts(JSON.pretty_generate(@hash_mode))
			}
		rescue => e
			 p e
			 return "internal_error"
		end

		return "success"
	end
end
