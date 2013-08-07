#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

# CURRENTなsubstepのhtml_contentsを表示させるDetailDraw命令．
def detailDraw(hash_mode)
	begin
		orders = []
		hash_mode["substep"]["mode"].each{|key, value|
			# CURRENなsubstepは一つだけ（のはず）．
			if value[2] == "CURRENT"
				orders.push({"DetailDraw"=>{"id"=>key}})
				break
			end
		}
	rescue => e
		p e
		return [], false
	end

	return orders, true
end

# CURRENTなaudioとvideoを再生させるPlay命令．
def play(time)
	orders = []
	media = ["audio", "video"]
	media.each{|v|
		@hash_mode[v]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# triggerの数が1個以上のとき．
				if @doc.emelents["//#{v}[@id=\"#{key}\"]/trigger[1]"] != nil
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


# 再生待ち状態のaudio，video，notificationを中止するCancel命令．
def cancel(session_id, doc, hash_mode, *id)
	begin
		orders = []
		# 特に中止させるメディアについて指定が無い場合
		if id == []
			# audioとvideoの処理．
			# Cancelさせるべきものは，STOPになっているはず．
			media = ["audio", "video"]
			media.each{|v|
				if hash_mode.key?(v)
					hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOPからFINISHEDに変更．
							hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notificationの処理．
			# Cancelさせるべきものは，STOPのなっているはず．
			if hash_mode.key?("notification")
				hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOPからFINISHEDに変更．
						hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audioをもつnotificationの場合，audioもFINISHEDに変更．
						if doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # 中止させるメディアについて指定がある場合．
			id.each{|v|
				# 指定されたメディアのelement nameを調査．
				element_name = searchElementName(session_id, v)
				# audioとvideoの場合．
				if element_name == "audio" || element_name == "video"
					# 指定されたものが再生待ちかどうかとりあえず調べる，
					if hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notificationの場合．
					# 指定されたnotificationが再生待ちかどうかとりあえず調べる．
					if hash_mode["notification"]["mode"][v][0] == "KEEP"
						# CancelしてFINISHEDに．
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audioを持つnotificationはaudioもFINISHEDに．
						if doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # 指定されたものがaudio，video，notificationで無い場合．
					return [], "invalid_params"
				end
			}
		end
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_mode))
		}
	rescue => e
		p e
		return [], "internal_error"
	end

	return orders, "success"
end
