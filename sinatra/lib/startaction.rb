#!/usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'
require 'lib/xmlParser.rb'
require 'nokogiri'


def start_action(session_id, contents)
	begin
		unless system("mkdir -p records/#{session_id}")
			p "Cannot mkdir"
			return "internal error", {}
		end
		unless system("touch records/#{session_id}/#{session_id}.log")
			p "Cannot touch log file"
			return "internal error", {}
		end
		unless system("touch records/#{session_id}/#{session_id}_error.log")
			p "Cannot touch error_log file"
			return "internal error", {}
		end

		unless system("touch records/#{session_id}/#{session_id}_recipe.xml")
			p "Cannot touch recipe file"
			return "internal error", {}
		end
		open("records/#{session_id}/hoge.xml", "w"){|io|
			io.puts(contents)
		}
		unless system("cat records/#{session_id}/hoge.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			p "Cannot 'tr' hoge file"
			return "internal error", {}
		end
		unless system("rm records/#{session_id}/hoge.xml")
			p "Cannot remove hoge file"
			return "internal error", {}
		end

		doc = Nokogiri::XML(open("records/#{session_id}/#{session_id}_recipe.xml"))
		# xmlParserを使用する
		hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
		hash_recipe = get_step(doc, hash_recipe)
		# directions/substepの書き出し
		doc.xpath("//directions/substep").each{|node|
			substep_id = node["id"]
			hash_recipe = get_substep(doc, hash_recipe, nil, substep_id)
		}
		# recipe/notificationの書き出し
		doc.xpath("//recipe/notification").each{|node|
			notification_id = node["id"]
			hash_recipe = get_notification(doc, hash_recipe, nil, notification_id)
		}
		# recipe/eventの書き出し
		doc.xpath("//recipe/event").each{|node|
			event_id = node["id"]
			hash_recipe["event"][event_id] = 1
		}

		hash_mode = Hash.new{|h, k| h[k] = Hash.new(&h.default_proc)}
		sorted_step = []

		# modeファイル及びsortedファイ作成
		if hash_recipe.key?("step")
			hash_recipe["step"].each{|key, value|
				priority = hash_recipe["step"][key]["priority"]
				hash_mode["step"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
				sorted_step.push([priority, key])
			}
			sorted_step.sort!{|v1, v2|
				v2[0] <=> v1[0]
			}
		else
			p "Given recipe.xml does not have 'step'"
			return "invalid params", {}
		end

		if hash_recipe.key?("substep")
			hash_recipe["substep"].each{|key, value|
				hash_mode["substep"]["mode"][key] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			}
		else
			p "Given recipe.xml does not have 'substep'"
			return "invalid params", {}
		end

		# recipeの中身の確認は，stepとsubstepの有る無しだけに留めておく．（最悪それ以外はなくても支援できる）

		if hash_recipe.key?("audio")
			hash_recipe["audio"].each{|key, value|
				hash_mode["audio"]["mode"][key] = ["NOT_YET", -1]
			}
		end
		if hash_recipe.key?("video")
			hash_recipe["video"].each{|key, value|
				hash_mode["video"]["mode"][key] = ["NOT_YET", -1]
			}
		end
		if hash_recipe.key?("notification")
			hash_recipe["notification"].each{|key, value|
				hash_mode["notification"]["mode"][key] = ["NOT_YET", -1]
			}
		end

		# 表示されている画面の管理のために（START時はOVERVIEW）
		hash_mode["display"] = "OVERVIEW"

		# modeUpdate
		# 優先度の最も高いstepをCURRENTとし，その一番目のsubstepもCURRENTにする．
		current_step = sorted_step[0][1]
		current_substep = hash_recipe["step"][current_step]["substep"][0]

		hash_mode["step"]["mode"][current_step][2] = "CURRENT"
		hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
		# stepとsubstepを適切にABLEにする．
		hash_mode = set_ABLEorOTHERS(hash_recipe, hash_mode, current_step, current_substep)
		# STARTなので，is_finishedなものはない．
		# CURRENTとなったsubstepがABLEならばメディアの再生準備としてCURRENTにする．
		if hash_mode["substep"]["mode"][current_substep][0] == "ABLE"
			media = ["audio", "video", "notification"]
			media.each{|v|
				if hash_recipe["substep"][current_substep].key?(v)
					hash_recipe["substep"][current_substep][v].each{|media_id|
						hash_mode[v]["mode"][media_id][0] = "CURRENT"
					}
				end
			}
		end
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_mode))
		}
		open("records/#{session_id}/#{session_id}_sortedstep.txt", "w"){|io|
			io.puts(JSON.pretty_generate(sorted_step))
		}
		open("records/#{session_id}/#{session_id}_recipe.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_recipe))
		}
	rescue => e
		p e
		return "internal error", {}
	end

	return "success", hash_recipe
end
