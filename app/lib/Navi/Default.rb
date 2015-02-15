module Navi
    class Default
        def initialize(app)
            @app = app
        end
				def log_error(str)
					raise str
				end

    
##########################
# Default Recommendation
##########################
        def recommend(recipe,progress, prior_target)
            # set change[:recommended_order] and change[:state]

            # follow the order directed in XML whenever the attr 'priority' exist.
            steps = recipe.xpath('//step').to_a
            raise "empty steps in the recipe in ... \n#{recipe.to_xml}" if steps.empty?
            
            directed_steps = []
            prior_target = @app.current_step(recipe,progress[:state]) if prior_target == nil
            unless nil == prior_target then
                directed_steps, steps = steps.partition{|v| v == prior_target}
                @app.log_error "no directed id '#{prior_id}' in the step list." if directed_steps.empty?
                @app.log_error "several steps has same id '#{prior_id}' in the step list." if directed_steps.size > 1
            end
            raise "empty steps in the recipe in ... \n#{recipe.to_xml}" if (directed_steps.empty? and steps.empty?)

            states = progress[:state]
            finished_steps, notyet_steps = steps.partition{|v| states[v.id][:is_finished]}
            
            notyet_steps.sort_by!{|v| v.attributes.include?('priority') ? -v['priority'].to_i : 1 } # discending order
            return finished_steps + directed_steps + notyet_steps
        end

##########################
# Default External Input
##########################

        def route(session_data,ex_input)
						case ex_input[:action][:name]
                when "next" then
                    return self.next(session_data,ex_input)
                when "prev", "undo" then
                    return self._prev(session_data,ex_input)
                when "redo" then
                    return self.redo(session_data,ex_input)
                when "jump" then
                    return self.jump(session_data,ex_input)
                when "change" then
                    return self.change(session_data,ex_input)
                when "check" then
                    return self.check(session_data,ex_input)
                when "uncheck" then
                    return self.uncheck(session_data,ex_input)
                when "event" then
                    return self.event(session_data,ex_input)
                when "channel" then
                    return self.channel(session_data,ex_input)
                else
                    log_error "Unknown action for default algorithm: '#{ex_input[:action][:name]}' is directed by external input."
            end
            return result
        end

##########################
# Basic Operation by External Input
##########################

        def next(session_data,ex_input = nil)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”next”}}
            recipe = session_data[:recipe]
            ref_state = session_data[:progress][:state]
            c_ss = @app.current_substep(recipe,ref_state)
            session_data[:json_data]["operation_contents"] = c_ss.id.to_s
            return @app.check(session_data,nil,true)
        end
    

        def _prev(session_data,ex_input)
					if ex_input['action'].include?('index') then
						tar_index = ex_input['action']['index'].to_i
					else
						tar_index = nil
					end
					prev(session_data,tar_index)
				end
				
				def prev(session_data,tar_index=nil)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”prev”}}
						STDERR.puts "Default::prev"
            iter_index = session_data[:progress][:iter_index].to_i
						
						if nil == tar_index then
							tar_index = iter_index-1
						end
						
						change = Recipe::StateChange.new
						
						while tar_index < iter_index do
							STDERR.puts iter_index
							break if 0>=iter_index
							
							delta_file = @app.generate_progress_diff_filename(session_data[:session_dir],iter_index)
							@app.log_error "The delta file is not found." unless File.exist?(delta_file)
							delta = Recipe::Delta.new
							delta.parse(File.open(delta_file,"r").read)
							
							#STDERR.puts delta_file
							#STDERR.puts "delta.before"
							#STDERR.puts delta.before
							change.deep_merge!(delta.before)
							#STDERR.puts "change"
							#STDERR.puts change
							iter_index = change[:iter_index].to_i
						end
						#STDERR.puts "prev end"
            return "success", change
        end
        
        def redo(session_data,ex_input)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”prev”}}
            iter_index = session_data[:progress][:iter_index].to_i + 1

            delta_file = @app.generate_progress_diff_filename(session_data[:session_dir],iter_index)
            return "Redo failed. No more operation history.", Recipe::StateChange.new unless File.exist?(delta_file)
            
            delta = Recipe::Delta.new
            delta.parse(File.open(delta_file,"r").read)
            return "success", delta.after
        end


        def jump(session_data,ex_input)            
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”jump”,”target”:”substep01_01}}
            session_data[:json_data]["operation_contents"] = ex_input[:action][:target]

            recipe = session_data[:recipe]
            ref_progress = session_data[:progress].deep_dup
            ref_states = ref_progress[:state]
            
            # check current substep to make it finished state.
						c_ss = @app.current_substep(recipe,ref_progress[:state])
						
            change = Recipe::StateChange.new
						if !ex_input[:action].include?(:check) or ex_input[:action][:check] == "true" then
              # checkが指定されていない，またはtrueとなっている場合
              unless nil==c_ss then
                change[:state] = @app.check_substep(c_ss,true,recipe, ref_states)
                ref_progress.deep_merge!(change)
              end
            end


						
            target_step = recipe.getByID(ex_input[:action][:target])
            target_substep = nil
            if 'substep' == target_step.name then
                target_substep = target_step
                target_step = target_substep.parent
            else
                default_order = recipe.max_order
                target_substep = @app.first_unfinished_substep(target_step,recipe,ref_progress[:state])
                target_substep = target_step.to_sub.sort_by{|v|v.order(default_order)}.last if nil == target_substep
            end
						
						change[:recommended_order], temp = @app.update_recommended_order(recipe,ref_progress,self, target_step)
						change[:state].deep_merge!(temp)


            # チェックがついている先へjumpする場合はしっかり関連するsubstepのcheckを全部外す
            if ref_progress[:state][target_substep.id][:is_finished] then
              temp_state = @app.check_substep(target_substep,false,recipe, ref_states)
              change[:state].deep_merge!(temp_state)
            end

						#ref_progress.deep_merge!(change)
						temp = @app.set_current_substep(recipe,ref_progress[:state],target_substep)
						temp2 = @app.set_current_substep(recipe,change[:state],target_substep)
						temp.deep_merge!(temp2)
						change[:state].deep_merge!(temp)
						
            change[:detail] = target_substep['id']
            return "success",change
        end


        def change(session_data,ex_input)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”change”,”target”:”substep01_01″}}
            session_data[:json_data]["operation_contents"] = ex_input[:action][:target]
            return @app.navi_menu(session_data, nil)
        end


        def check(session_data,ex_input)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”check”,”target”:”substep01_01″[,"value":"true"]}}
            session_data[:json_data]["operation_contents"] = ex_input[:action][:target]
            
            if ex_input[:action].include?(:value) then
                value = ex_input[:action][:value].to_b
            else
                value = nil
            end
            return @app.check(session_data,nil,value)
        end

        def channel(session_data,ex_input)
            # ex_input : {"navigator":"default","action":{"name":"channel","value":"DETAIL"}}
            session_data[:json_data]["operation_contents"] = ex_input[:action][:value]
            return @app.channel(session_data)
        end

# instead of uncheck, use 'check' with "value":false option.
#        def uncheck(session_data,ex_input)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”check”,”target”:”substep01_01″}}
#            session_data[:json_data]["operation_contents"] = ex_input[:action][:target]
#            return @app.check(session_data,nil,false)
#        end

##########################
# Trigger Operation by External Input
##########################
        def event(session_data,ex_input)
            # ex_input : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”event”,”target”:”event_01 event_02″, ["timing":"start"]}}
            recipe = session_data[:recipe]
            latest_progress = session_data[:progress]

            events = ex_input[:action][:target]
            timing = ex_input[:action].include?(:timing) ? ex_input[:action][:timing] : 'start'
            
            step_candidates = recipe.triggerable_nodes(['step','substep'])
            media_candidates = recipe.triggerable_nodes(['audio','video'])
            

            
            
            change = nil
            if step_candidates.empty? then
                change = Recipe::StateChange.new
            else
                change = event_inner(recipe,latest_progress,step_candidates, events, timing,:event_step)
            end
            
            latest_progress = latest_progress.deep_merge(change) unless change.empty?
            unless media_candidates.empty? then
                temp = event_inner(recipe,latest_progress,media_candidates, events, timing, :event_media)
                unless temp.empty? then
                    change[:play].deep_merge!(temp[:play])
                    latest_progress = latest_progress.deep_merge(change)
                end
            end

						c_ss = @app.current_substep(recipe,latest_progress[:state])
						noty_cands = c_ss.notifies + recipe.notifies
						change_notify = @app.register_notifies(noty_cands,latest_progress[:notify],"start",events)
						change[:notify].deep_merge!(change_notify);

            return "success", change
        end

        def event_inner(recipe,ref_progress, hash, events, timing,func)
            change = Recipe::StateChange.new
            for parent,cands in hash do
                delay_array = @app.check_fired_triggers(cands,timing,events)
                next if delay_array.empty?
                delay = delay_array.min
                temp_change = self.send(func,recipe,ref_progress,parent,delay)
                next if nil == temp_change
                change.deep_merge!(temp_change)
            end
            return change
        end


        def event_step(recipe, ref_progress, node, delay)
            log_error "Trigger for step/substep cannot direct delay currently." if delay > 0
            
            pseudo_ex_input = {:navigator=>"default", :action=>{:name=>"jump",:target=>node['id']}}.with_indifferent_access
            pseudo_session_data = { :recipe => recipe, :progress => ref_progress,:json_data => {}, :alg => self }
            return jump(pseudo_session_data,pseudo_ex_input)[1]
        end
            
        def event_media(recipe, ref_progress, node, delay)
            return nil unless @app.is_on_context?(recipe,ref_progress,node)
            return @app.play_control(recipe, ref_progress, :PLAY, node.id,delay)[1]
        end
        
        def event_notify(recipe, ref_progress, node, delay)
            #            return nil unless @app.is_on_context?(recipe,ref_progress,node)
            change = Recipe::StateChange.new
            change[:notify] = @app.notify_control(ref_progress[:notify],change[:notify], node, true, delay)
            return change
        end

    end
end