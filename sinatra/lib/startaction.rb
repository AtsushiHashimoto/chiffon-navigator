#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

def start_action(session_id, contents)
	begin
		unless system("mkdir -p records/#{session_id}")
			p "Cannot mkdir"
			return "internal_error"
		end
		unless system("touch records/#{session_id}/#{session_id}.log")
			p "Cannot touch log file"
			return "internal_error"
		end
		unless system("touch records/#{session_id}/#{session_id}_error.log")
			p "Cannot touch error_log file"
			return "internal_error"
		end
		unless system("touch records/#{session_id}/#{session_id}_recipe.xml")
			p "Cannot touch recipe file"
			return "internal_error"
		end
		open("records/#{session_id}/hoge.xml", "w"){|io|
			io.puts(contents)
		}
		unless system("cat records/#{session_id}/hoge.xml | tr -d '\r' | tr -d '\n'  | tr -d '\t' > records/#{session_id}/#{session_id}_recipe.xml")
			p "Cannot 'tr' hoge file"
			return "internal_error"
		end

		doc = REXML::Document.new(open("records/#{session_id}/#{session_id}_recipe.xml"))

		# id$B%F!<%V%k%U%!%$%k$N:n@.(B
		hash_id = Hash.new{|h, k| h[k] = {}}
		doc.get_elements("//*").each{|node|
			if node.attributes.get_attribute("id") != nil
				if hash_id.key?("#{node.name}")
					hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
				else
					hash_id["#{node.name}"]["id"] = []
					hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
				end
			end
		}
		if hash_id == {}
			p "Given recipe.xml seems to be empty"
			return "invalid_params"
		end

		hash_mode = Hash.new{|h, k| h[k] = Hash.new(&h.default_proc)}
		sorted_step = []

		# mode$B%U%!%$%k5Z$S(Bsorted$B%U%!%$:n@.(B
		if hash_id.key?("step")
			hash_id["step"]["id"].each{|value|
				priority = 100
				if doc.elements["//step[@id=\"#{value}\"]"].attributes.get_attribute("priority") != nil
					priority = doc.elements["//step[@id=\"#{value}\"]"].attributes.get_attribute("priority").value.to_i
				end
				hash_mode["step"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
				sorted_step.push([priority, value])
			}
			sorted_step.sort!{|v1, v2|
				v2[0] <=> v1[0]
			}
		else
			p "Given recipe.xml does not have 'step'"
			return "invalid_params"
		end

		if hash_id.key?("substep")
			hash_id["substep"]["id"].each{|value|
				hash_mode["substep"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			}
		else
			p "Given recipe.xml does not have 'substep'"
			return "invalid_params"
		end

		# recipe$B$NCf?H$N3NG'$O!$(Bstep$B$H(Bsubstep$B$NM-$kL5$7$@$1$KN1$a$F$*$/!%!J:G0-$=$l0J30$O$J$/$F$b;Y1g$G$-$k!K(B

		if hash_id.key?("audio")
			hash_id["audio"]["id"].each{|value|
				hash_mode["audio"]["mode"][value] = ["NOT_YET", -1]
			}
		end
		if hash_id.key?("video")
			hash_id["video"]["id"].each{|value|
				hash_mode["video"]["mode"][value] = ["NOT_YET", -1]
			}
		end
		if hash_id.key?("notification")
			hash_id["notification"]["id"].each{|value|
				hash_mode["notification"]["mode"][value] = ["NOT_YET", -1]
			}
		end

		# modeUpdate
		# $BM%@hEY$N:G$b9b$$(Bstep$B$r(BCURRENT$B$H$7!$$=$N0lHVL\$N(Bsubstep$B$b(BCURRENT$B$K$9$k!%(B
		current_step = sorted_step[0][1]
		current_substep = nil
		if doc.elements["//step[@id=\"#{current_step}\"]/substep[1]"].attributes.get_attribute("id") != nil
			current_substep = doc.elements["//step[@id=\"#{current_step}\"]/substep[1]"].attributes.get_attribute("id").value
		else
			p "substep does not have 'id'"
			return "invalid_params"
		end
		hash_mode["step"]["mode"][current_step][2] = "CURRENT"
		hash_mode["substep"]["mode"][current_substep][2] = "CURRENT"
		# step$B$H(Bsubstep$B$rE,@Z$K(BABLE$B$K$9$k!%(B
		hash_mode = set_ABLEorOTHERS(doc, hash_mode, current_step, current_substep)
		# START$B$J$N$G!$(Bis_finished$B$J$b$N$O$J$$!%(B
		# CURRENT$B$H$J$C$?(Bsubstep$B$,(BABLE$B$J$i$P%a%G%#%"$N:F@8=`Hw$H$7$F(BCURRENT$B$K$9$k!%(B
		if hash_mode["substep"]["mode"][current_substep][0] == "ABLE"
			media = ["audio", "video", "notification"]
			media.each{|v|
				doc.get_elements("//substep[@id=\"#{current_substep}\"]/#{v}").each{|node|
					media_id = node.attributes.get_attribute("id").value
					hash_mode[v]["mode"][media_id][0] = "CURRENT"
				}
			}
		end
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_mode))
		}
		open("records/#{session_id}/#{session_id}_sortedstep.txt", "w"){|io|
			io.puts(JSON.pretty_generate(sorted_step))
		}
		open("records/#{session_id}/#{session_id}_table.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_id))
		}
	rescue => e
		p e
		return "internal_error"
	end

	return "success"
end
