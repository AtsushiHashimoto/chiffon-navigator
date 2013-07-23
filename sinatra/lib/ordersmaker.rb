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

	# Update hash_mode accroding to input from viewer.
	def modeUpdate(sign, time, *id)
		case sign
		when "NAVI_MENU"
			# No need to change is_finished.
			# Change current step(/substep) to Not CURRENT.
			# Change clicked step(/substep) to CURRENT.
			self.modeUpdate_navimenu(time, id[0])
		when "EXTERNAL_INPUT"
			# Change current step(/substep) to is_finished(=1)
			# Decide which step(/substep) will be CURRENT according to external_input.
			# Decide which step(/substep) will be ABLE.
			self.modeUpdate_externalinput(time, id[0])
		when "CHANNEL"
			# Update only media to STOP
			self.modeUpdate_channel(time, id[0])
		when "CHECK"
			# No need to change CURRENT. (because this phase only change is_finished)
			# Update checked step(/substep) to is_finished(=1).
			# If checked step(/substep) is ABLE, change to OTHERS.
			self.modeUpdate_check(time, id[0])
		when "START"
			# All steps, substeps and media is NOT is_finished(=1) or FINISHED.
			# Set some step, substep and media to CURRENT.
			# Set some steps & substep to ABLE.
			self.modeUpdate_start()
		when "END"
			# Update all media to STOP
			# No need to update mode of steps and substep.
			self.modeUpdate_finish()
		else
			return false
		end
		# Update mode.text according to hash_mode.
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return true
	end

	# Make DetaiDraw order about CURRENT substep's html_contents.
	def detailDraw
		orders = []
		flag = 0
		@hash_mode["substep"]["mode"].each{|key, value|
			# CURRENT substep must be one.
			if value[2] == "CURRENT" then
				orders.push({"DetailDraw"=>{"id"=>key}})
				break
#				flag = 1
			end
		}
		return orders
	end

	def play(time)
		orders = []
		media = ["audio", "video"]
		media.each{|v|
			@hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT" then
					# There may be some trigger. Which trigger should we use for playing?
					if @doc.elements["//#{v}[@id=\"#{key}\"]/trigger[1]"] != nil
						@doc.get_elements("//#{v}[@id=\"#{key}\"]/trigger[1]").each{|node|
							orders.push({"Play"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
							finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
							@hash_mode[v]["mode"][key][1] = finish_time
						}
					else
						#@hash_mode[v]["mode"][key][1] = ?
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

	def notify(time)
		orders = []
		@hash_mode["notification"]["mode"].each{|key, value|
			if value[0] == "CURRENT" then
				# There may be some trigger. Which trigger should we use for notifying?
				@doc.get_elements("//notification[@id=\"#{key}\"]/trigger[1]").each{|node|
					orders.push({"Notify"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
					finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
					# Only for notification, we should update it to KEEP as soon as play it.
					@hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
				}
			end
		}
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return orders
	end

	def cancel(*id)
		orders = []
		if id == [] then
			media = ["audio", "video"]
			media.each{|v|
				if @hash_mode.key?(v) then
					@hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP" then
							orders.push({"Cancel"=>{"id"=>key}})
							@hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			if @hash_mode.key?("notification") then
				@hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP" then
						orders.push({"Cancel"=>{"id"=>key}})
						@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						if @doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil then
							audio_id = @doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else
			id.each{|v|
				element_name = searchElementName(@session_id, v)
				if element_name == "audio" or element_name == "video" then
					if @hash_mode[element_name]["mode"][v][0] == "CURRENT" then
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" then
					if @hash_mode["notification"]["mode"][v][0] == "KEEP" then
						orders.push({"Cancel"=>{"id"=>v}})
						@hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						if @doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil then
							audio_id = @doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else
					return [{}]
				end
			}
		end
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
		return orders
	end

	def channelSwitch(ch)
		orders = []
		if ch == "GUIDE" or ch == "MATERIALS" or ch == "OVERVIEW" then
			orders.push({"ChannelSwitch"=>{"channel"=>ch}})
		else
			return [{}] # Input ch is wrong.
		end
		return orders
	end

	def naviDraw
		# Drawing navi according to order of sorted_step.
		orders = Array.new()
		orders.push({"NaviDraw"=>{"steps"=>[]}})
		flag = 0
		@sorted_step.each{|v|
			id = v[1]
			visual = nil
			if @hash_mode["step"]["mode"][id][2] == "CURRENT" then
				visual = "CURRENT"
			elsif @hash_mode["step"]["mode"][id][2] == "NOT_CURRENT" then
				visual = @hash_mode["step"]["mode"][id][0]
			end
			if @hash_mode["step"]["mode"][id][1] == "is_finished" then
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
			elsif @hash_mode["step"]["mode"][id][1] == "NOT_YET" then
				orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
			end
			if visual == "CURRENT" then
				if flag == 1 then
					return [{}] # There are more than one CURRENT step.
				end
				@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
					id = node.attributes.get_attribute("id").value
					visual = nil
					if @hash_mode["substep"]["mode"][id][2] == "CURRENT" then
						visual = "CURRENT"
					elsif @hash_mode["substep"]["mode"][id][2] == "NOT_CURRENT"
						visual = @hash_mode["substep"]["mode"][id][0]
					end
					if @hash_mode["substep"]["mode"][id][1] == "is_finished" then
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
					elsif @hash_mode["substep"]["mode"][id][1] == "NOT_YET" then
						orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
					end
				}
				flag = 1
			end
		}
		return orders
	end

	######################################################################
	# Following 5 functions will be used in only the modeUpdate function.#
	######################################################################
	protected

	def modeUpdate_navimenu(time, id)
		element_name = searchElementName(@session_id, id)
		case element_name
		# When input id is step_id.
		when "step"
			# Update current substep to NOT_CURRENT
			### substep
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT" then
					# May be current substep is ABLE and CURRENT, and we update it to NOT CURRET.
					@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"
					# Update all substep to OTHERS
					parent_step = @doc.elements["//substep[@id=\"#{key}\"]"].parent.attributes.get_attribute("id").value
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						@hash_mode["substep"]["mode"][substep_id][0] = "OTHERS"
					}
					# Also update audio and video to FINISHED
					media = ["audio", "video"]
					media.each{|v|
						@hash_mode[v]["mode"].each{|key, value|
							if value[0] == "CURRENT" then
								@hash_mode[v]["mode"][key][0] = "STOP"
							end
						}
					}
					# No need to update notification to KEEP, because notification was updated to KEEP when it was played.
					break # CURRENT substep must be one.
				end
			}
			### step
			@hash_mode["step"]["mode"].each{|key, value|
				if value[2] == "CURRENT" then
					# Only update CURRENT status.
					# Not update ABLE or OTHERS status,because NAVI_MENU may be called more than one continuouslly.(!!REASON!!)
					# If we update current step to ABLE, every step can become ABLE by NAVI_MENU even if they can't.(!!REASON!!)
					@hash_mode["step"]["mode"][key][2] = "NOT_CURRENT"
					break # CURRENT step must be one
				end
			}
			# Update clicked step to CURRENT.
			# Not update to ABLE or OTHERS, because of above reason.
			@hash_mode["step"]["mode"][id][2] = "CURRENT"
			# If there is substep which is included in above step and NOT is_finished, update that substep to CURRENT.
			# If there is not such un-is_finished substep, first substep of above step to CURRENT.
			substep_id = nil
			@doc.get_elements("//step[@id=\"#{id}\"]/substep").each{|node|
				substep_id = node.attributes.get_attribute("id").value
				if @hash_mode["substep"]["mode"][substep_id][1] == "is_finished" then
					substep_id = nil
				else
					break
				end
			}
			if substep_id != nil then
				# update substep to CURRENT
				@hash_mode["substep"]["mode"][substep_id][2] = "CURRENT"
				# Update CURRENT substep from OTHERS to ABLE
				@hash_mode["substep"]["mode"][substep_id][0] = "ABLE"
				# Update next substep to ABLE
				if @doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node != nil then
					able_substep = @doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node.attributes.get_attribute("id").value
					@hash_mode["substep"]["mode"][able_substep][0] = "ABLE"
				end
			else
				substep_id = @doc.elements["//step[@id=\"#{id}\"]/substep[1]"].attributes.get_attribute("id").value
				@hash_mode["substep"]["mode"][substep_id][2] = "CURRENT"
				# ABLE substep is not exist, because all substep in CURRENT step is is_finished(=1)
			end
			# Not update media to CURRENT which included in above substep even if they are NOT_YET.
			# No need to change is_finished(=1)
		# When input id is substep_id
		when "substep"
			### substep
			@hash_mode["substep"]["mode"].each{|key, value|
				if value[2] == "CURRENT" then
					# Update current substep to NOT_CURRENT.
					@hash_mode["substep"]["mode"][key][2] = "NOT_CURRENT"

					me = @hash_mode["substep"]["mode"][key][0]
					you = @hash_mode["substep"]["mode"][id][0]

					if me == "ABLE" then
						# Keep me in ABLE.
						# Update next substep to OTHERS
						if @doc.elements["//substep[@id=\"#{key}\"]"].next_sibling_node != nil then
							next_substep = @doc.elements["//substep[@id=\"#{key}\"]"].next_sibling_node.attributes.get_attribute("id").value
							@hash_mode["substep"]["mode"][next_substep][0] = "OTHERS"
						end
					end
					if me != you and me == "OTHERS" then
						# Keep you ABLE
						# Update next substep to ABLE
						if @doc.elements["//substep[@id=\"#{id}\"]"].next_sibling_node != nil then
							next_substep = @doc.elements["//substep[@id=\"#{id}\"]"].next_sibling_node.attributes.get_attribute("id").value
							@hash_mode["substep"]["mode"][next_substep][0] = "ABLE"
						end
					end
					# Also update audio and video to FINISHED
					media = ["audio", "video"]
					media.each{|v|
						@hash_mode[v]["mode"].each{|key, value|
							if value[0] == "CURRENT" then
								@hash_mode[v]["mode"][key][0] = "STOP"
							end
						}
					}
					break # CURRENT substep must be one.
				end
			}
			# Update clicked substep to CURRENT even if it is is_finished(=1).
			@hash_mode["substep"]["mode"][id][2] = "CURRENT"
			# Not update media to CURRENT.
			# No need to change is_finished(=1)
		else
			p "error"
		end
		# If notification was presented before this function is called, upload it to FINISHED (Not STOP).
		@hash_mode["notification"]["mode"].each{|key, value|
			if value[0]  == "KEEP" then
				if time > value[1] then
					@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
					# If the notification has audio, also update it to FINISHED
					@doc.get_elements("//notification[@id=\"#{key}\"]/audio").each{|node|
						audio_id = node.attributes.get_attribute("id").value
						if audio_id != nil then
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					}
				end
			end
		}
	end

	def modeUpdate_externalinput(time, id)
		element_name = searchElementName(@session_id, id)
		if element_name == "notification"
			if @hash_mode["notification"]["mode"][id][0] == "NOT_YET"
				@hash_mode["notification"]["mode"][id][0] = "CURRENT"
			elsif @hash_mode["notification"]["mode"][id][0] == "KEEP"
				@hash_mode["notification"]["mode"][id][0] = "STOP"
			end
		else
			# Find substep which use input object as trigger.
			next_substep = nil
			@sorted_step.each{|v|
				flag = -1
				# Find substep from step which is NOT is_finished.
				if @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" and @hash_mode["step"]["mode"][v[1]][0] == "ABLE" then
					@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET" then
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
								if node2.attributes.get_attribute("ref").value == id then
									next_substep = node2.parent.attributes.get_attribute("id").value
									flag = 1
									break
								end
							}
						end
						if flag == 1 then
							break
						end
					}
				elsif @hash_mode["step"]["mode"][v[1]][1] == "NOT_YET" and @hash_mode["step"]["mode"][v[1]][2] == "CURRENT" then
					@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET" and @hash_mode["substep"]["mode"][substep_id][0] == "ABLE" then
							@doc.get_elements("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
								if node2.attributes.get_attribute("ref").value == id then
									next_substep = node2.parent.attributes.get_attribute("id").value
									flag = 1
									break
								end
							}
						end
						if flag == 1 then
							break
						end
					}
				end
				if flag == 1 then
					break
				end
			}
			current_substep = nil
			if next_substep == nil then
#				current_substep = nil
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT" then
						current_substep = key
						break
					end
				}
				if @hash_mode["substep"]["mode"][current_substep][0] == "ABLE"
					if @doc.elements["//substep[@id=\"#{current_substep}\"]"].next_sibling_node != nil
						next_substep = @doc.elements["//substep[@id=\"#{current_substep}\"]"].next_sibling_node.attributes.get_attribute("id").value
					else
						parent_id = @doc.elements["//substep[@id=\"#{current_substep}\"]"].parent.attributes.get_attribute("id").value
						@sorted_step.each{|v|
							if parent_id != v[1] and @hash_mode["step"]["mode"][v[1]][0] == "ABLE"
								@doc.get_elements("//step[@id=\"#{v[1]}\"]/substep").each{|node|
									substep_id = node.attributes.get_attribute("id").value
									if @hash_mode["substep"]["mode"][substep_id][1] == "NOT_YET"
										next_substep = substep_id
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
									next_substep = substep_id
									break
								end
							}
							break
						end
					}
				end
			end
			if next_substep == nil
				# Do nothing
			else
				current_substep = nil
				@hash_mode["substep"]["mode"].each{|key, value|
					if value[2] == "CURRENT" then
						current_substep = key
						break
					end
				}
				# If current substep is next substep, no need to change CURRENT.
				# Update CURRENT if current substep is NOT next substep.
				if next_substep != current_substep then
					# Update current substep to is_finihsed(=1) and OTHERS and NOT_CURRENT.
					@hash_mode["substep"]["mode"][current_substep][0] = "OTHERS"
					@hash_mode["substep"]["mode"][current_substep][1] = "is_finished"
					@hash_mode["substep"]["mode"][current_substep][2] = "NOT_CURRENT"
					current_step = @doc.elements["//substep[@id=\"#{current_substep}\"]"].parent.attributes.get_attribute("id").value
					media = ["audio", "video"]
					media.each{|v|
						@doc.get_elements("//substep[@id=\"#{current_substep}\"]/#{v}").each{|node|
							media_id = node.attributes.get_attribute("id").value
							if @hash_mode[v]["mode"][media_id][0] == "CURRENT"
								@hash_mode[v]["mode"][media_id][0] = "STOP"
							end
						}
					}
					# Update current step to NOT_CURRENT
					@hash_mode["step"]["mode"][current_step][2] = "NOT_CURRENT"
					# If current substep is last in parent step, update parent step to is_finished(=1)
					if @doc.elements["//substep[@id=\"#{current_substep}\"]"].next_sibling_node == nil then
						@hash_mode["step"]["mode"][current_step][0] = "OTHERS"
						@hash_mode["step"]["mode"][current_step][1] = "is_finished"
					end
					# Update next substep to CURRENT
					@hash_mode["substep"]["mode"][next_substep][2] = "CURRENT"
					@hash_mode["substep"]["mode"][next_substep][0] = "ABLE"
					# Update next step to CURRENT if above substep is first of the step
					next_parent = @doc.elements["//substep[@id=\"#{next_substep}\"]"].parent.attributes.get_attribute("id").value
					if @hash_mode["step"]["mode"][next_parent][2] == "NOT_CURRENT" then
						@hash_mode["step"]["mode"][next_parent][2] = "CURRENT"
						@hash_mode["step"]["mode"][next_parent][0] = "ABLE"
					end
					# Update media to CURRENT if it is not FINISHED
					media = ["audio", "video", "notification"]
					media.each{|v|
						@doc.get_elements("//substep[@id=\"#{next_substep}\"]/#{v}").each{|node|
							media_id = node.attributes.get_attribute("id").value
							if @hash_mode[v]["mode"][media_id][0] == "NOT_YET" then
								@hash_mode[v]["mode"][media_id][0] = "CURRENT"
							end
						}
					}
				else
					@hash_mode["substep"]["mode"][next_substep][0] = "ABLE"
					@hash_mode["substep"]["mode"][next_substep][2] = "CURRENT"
					next_step = @doc.elements["//substep[@id=\"#{next_substep}\"]"].parent.attributes.get_attribute("id").value
					@hash_mode["step"]["mode"][next_step][0] = "ABLE"
					@hash_mode["step"]["mode"][next_step][2] = "CURRENT"
					# Update media to CURRENT if it is not FINISHED
					media = ["audio", "video", "notification"]
					media.each{|v|
						@doc.get_elements("//substep[@id=\"#{next_substep}\"]/#{v}").each{|node|
							media_id = node.attributes.get_attribute("id").value
							if @hash_mode[v]["mode"][media_id][0] == "NOT_YET" then
								@hash_mode[v]["mode"][media_id][0] = "CURRENT"
							end
						}
					}
				end
				# Update some step and substep to ABLE
				### step
				next_step = @doc.elements["//substep[@id=\"#{next_substep}\"]"].parent.attributes.get_attribute("id").value
				@hash_mode["step"]["mode"].each{|key, value|
					# Search ABLE step from steps which is NOT is_finished(=1).
					if value[1] == "NOT_YET" then
						# Search from except CURRENT step.
						if value[0] == "NOT_CURRENT" then
							# If the step has no parent step, update it to ABLE.
							if @doc.elements["//step[@id=\"#{key}\"]/parent"] == nil then
								@hash_mode["step"]["mode"][key][0] = "ABLE"
							else
								flag = -1
								@doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
									if @hash_mode["step"]["mode"].key?(v) then
										if @hash_mode["step"]["mode"][v][1] == "is_finished" then
											flag = 1
										else
											if v == next_step and @hash_mode["step"]["mode"][current_step][0] == "ABLE" then
												flag = 1
											else
												flag = -1
											end
										end
									end
								}
								if flag == 1 then
									@hash_mode["step"]["mode"][key][0] = "ABLE"
								end
							end
						end
					end
				}
				### substep
				if @doc.elements["//substep[@id=\"#{next_substep}\"]"].next_sibling_node != nil then
					able_substep = @doc.elements["//substep[@id=\"#{next_substep}\"]"].next_sibling_node.attributes.get_attribute("id").value
					@hash_mode["substep"]["mode"][able_substep][0] = "ABLE"
				end
				# If notification was presented before this function is called, upload it to FINISHED (Not STOP).
				@hash_mode["notification"]["mode"].each{|key, value|
					if value[0]  == "KEEP" then
						if time > value[1] then
							@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
							# If the notification has audio, also update it to FINISHED
							@doc.get_elements("//notification[@id=\"#{key}\"]/audio").each{|node|
								audio_id = node.attributes.get_attribute("id").value
								if audio_id != nil then
									@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
								end
							}
						end
					end
				}
			end
		end
	end

	def modeUpdate_channel(time, flag)
		# Flag is 1 when channel is OVERVIEW or MATERIALS.
		# In thosse case, some CURRENT media should be updated to STOP.
		if flag == 1 then
			# Update audio and video to STOP for canceling them.
			media = ["audio", "video"]
			media.each{|v|
				@hash_mode[v]["mode"].each{|key, value|
					if value[0] == "CURRENT" then
						@hash_mode[v]["mode"][key][0] = "STOP"
					end
				}
			}
		end
		# If notification was presented before this function is called, upload it to FINISHED (Not STOP).
		@hash_mode["notification"]["mode"].each{|key, value|
			if value[0]  == "KEEP" then
				if time > value[1] then
					@hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
					# If the notification has audio, also update it to FINISHED
					@doc.get_elements("//notification[@id=\"#{key}\"]/audio").each{|node|
						audio_id = node.attributes.get_attribute("id").value
						if audio_id != nil then
							@hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					}
				end
			end
		}
	end

	def modeUpdate_check(time, id)
		element_name = searchElementName(@session_id, id)
		# チェックされたものによって場合分け．
		case element_name
		when "audio" # 再生待ちをSTOPに．
			@hash_mode["audio"]["mode"][id][0] = "STOP"
		when "video" # 再生待ちをSTOPに．
			@hash_mode["video"]["mode"][id][0] = "STOP"
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
				# チェックされたstepをparentに持つis_finishedなstepを全てNOT_YETにする．
				@hash_mode["step"]["mode"].each{|key, value|
					if value[1] == "is_finished"
						if @doc.elements["//step[@id=\"#{key}\"]/parent"] != nil then
							@doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value.split(" ").each{|v|
								if v == id
									@hash_mode["step"]["mode"][key][1] = "NOT_YET"
									# NOT_YETにされたstepに含まれるsubstepを全てNOT_YETに．
									@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
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
									break
								end
							}
						end
					end
				}
			end
			# ABLEまたはOTHERSの操作のために，CURRENTなstepとsubstepのidを調べる．
			current_step = nil
			current_substep = nil
			@hash_mode["step"]["mode"].each{|key, value|
				if @hash_mode["step"]["mode"][key][2] == "CURRENT"
					current_step = key
					@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
							current_substep = substep_id
							break
						end
					}
					break
				end
			}
			# ABLEまたはOTHERSの操作．
			@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
			# 可能なsubstepに遷移する
			@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
			# 再度ABLEの判定を行う
			current_step = nil
			current_substep = nil
			@hash_mode["step"]["mode"].each{|key, value|
				if @hash_mode["step"]["mode"][key][2] == "CURRENT"
					current_step = key
					@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
							current_substep = substep_id
							break
						end
					}
					break
				end
			}
			# ABLEまたはOTHERSの操作．
			@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
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
						break
					end
				}
				# 全てのsubstepがis_finishedならば，親ノードのstepもis_finishedにする．
				flag = -1
				@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node|
					child_substep = node.attributes.get_attribute("id").value
					# NOT_YETなsubstepがいれば，親ノードのstepはis_finishedにならないので直ちにbreak．
					if @hash_mode["substep"]["mode"][child_substep][1] == "NOT_YET"
						flag = 1
						break
					end
				}
				# stepがis_finishedに変更されたら，ABLEの計算もし直す．
				if flag == -1 then
					@hash_mode["step"]["mode"][parent_step][1] = "is_finished"
					# current_substepの探索．（current_stepはparent_stepに一致）
					current_substep = nil
					@doc.get_elements("//step[@id=\"#{parent_step}\"]/substep").each{|node|
						substep_id = node.attributes.get_attribute("id").value
						if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
							current_substep = substep_id
							break
						end
					}
					# stepとsubstepを適切にABLEに．
					@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, parent_step, current_substep)
				end
				current_step = nil
				current_substep = nil
				@hash_mode["step"]["mode"].each{|key, value|
					if @hash_mode["step"]["mode"][key][2] == "CURRENT"
						current_step = key
						@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
				# 可能なsubstepに遷移する
				@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
				# 再度ABLEの判定を行う．
				current_step = nil
				current_substep = nil
				@hash_mode["step"]["mode"].each{|key, value|
					if @hash_mode["step"]["mode"][key][2] == "CURRENT"
						current_step = key
						@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
				# ABLEまたはOTHERSの操作．
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
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
						# チェックされたsubstepが同一step内の最終substepならば，親ノードのstepをNOT_YETにして，ABLEの操作をする．
						if node.next_sibling_node == nil
							@hash_mode["step"]["mode"][parent_step][1] = "NOT_YET"
							@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, parent_step, id)
						end
					end
				}
				# 可能なsubstepに遷移する
				current_step = nil
				current_substep = nil
				@hash_mode["step"]["mode"].each{|key, value|
					if @hash_mode["step"]["mode"][key][2] == "CURRENT"
						current_step = key
						@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
				@hash_mode = go2current(@doc, @hash_mode, @sorted_step, current_step, current_substep)
				# 再度ABLEの判定を行う．
				current_step = nil
				current_substep = nil
				@hash_mode["step"]["mode"].each{|key, value|
					if @hash_mode["step"]["mode"][key][2] == "CURRENT"
						current_step = key
						@doc.get_elements("//step[@id=\"#{key}\"]/substep").each{|node|
							substep_id = node.attributes.get_attribute("id").value
							if @hash_mode["substep"]["mode"][substep_id][2] == "CURRENT"
								current_substep = substep_id
								break
							end
						}
						break
					end
				}
				@hash_mode = set_ABLEorOTHERS(@doc, @hash_mode, current_step, current_substep)
			end
		else
			errorLOG()
		end
		# notificationが再生済みかどうかは，隙あらば調べましょう．
		@hash_mode = check_notification_FINISHED(@doc, @hash_mode, time)
		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(@hash_mode))
		}
	end

	def modeUpdate_start()
		# Update highest priority step and substep to CURRENT
		step_id = @sorted_step[0][1]
		substep_id = @doc.elements["//step[@id=\"#{step_id}\"]/substep[1]"].attributes.get_attribute("id").value
		@hash_mode["step"]["mode"][step_id][2] = "CURRENT"
		@hash_mode["step"]["mode"][step_id][0] = "ABLE" # CURRENT step is also ABLE.
		@hash_mode["substep"]["mode"][substep_id][2] = "CURRENT"
		@hash_mode["substep"]["mode"][substep_id][0] = "ABLE" # CURRENT substep is also ABLE.
		# Also update media which are included in above substep to CURRENT
		media = ["audio", "video", "notification"]
		media.each{|v|
			@doc.get_elements("//substep[@id=\"#{substep_id}\"]/#{v}").each{|node|
				media_id = node.attributes.get_attribute("id").value
				@hash_mode[v]["mode"][media_id][0] = "CURRENT"
			}
		}
		# Update next step and substep to ABLE
		### step
		@hash_mode["step"]["mode"].each{|key, value|
			# Step has no parent step
			if @doc.elements["//step[@id=\"#{key}\"]/parent"] == nil then
				if key != step_id then
					@hash_mode["step"]["mode"][key][0] = "ABLE"
				end
			elsif @doc.elements["//step[@id=\"#{key}\"]/parent"].attributes.get_attribute("ref").value == step_id then
				@hash_mode["step"]["mode"][key][0] = "ABLE"
			end
		}
		### substep
		if @doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node != nil then
			able_substep = @doc.elements["//substep[@id=\"#{substep_id}\"]"].next_sibling_node.attributes.get_attribute("id").value
			@hash_mode["substep"]["mode"][able_substep][0] = "ABLE"
		end
		# No need to update all step(/substep) to is_finished(=1)
	end

	def modeUpdate_finish()
		# Update all (even if notification) CURRENT media to STOP
		media = ["audio", "video", "notification"]
		media.each{|v|
			@hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT" then
					@hash_mode[v]["mode"][key][0] = "STOP"
				end
			}
		}
	end
end
