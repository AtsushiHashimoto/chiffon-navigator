require 'lib/Recipe/Delta.rb'
module Navi
module Base
    # those functions are commonly called from the route "/navi/:algorith"
    extend Sinatra::Extension

    def self.registered(app)
        app.helpers Base
    end

#################################################
## CALL AT THE STATE OF NAVIGATION.
#################################################
    def start(session_data)
        session_logger = session_data[:logger]
  
        # parse the recipe
        recipe_text = session_data[:json_data]["operation_contents"]

        #       session_data[:logger].debug recipe_text
        session_data[:recipe] = Nokogiri::XML(recipe_text)
        session_data[:recipe].add_parent2child_link

        recipe = session_data[:recipe]

        #save the recipe
        File.open("#{session_data[:session_dir]}/#{settings.recipe_file}","w").write(recipe.to_xml)


        # initialize progress
        change = Recipe::StateChange.new
        progress = session_data[:progress]
				
        for step in recipe.xpath('//step') do
            progress[:state][step.id][:is_opened] = false
						progress[:state][step.id][:visual] = 'ABLE' if is_able?(recipe,progress[:state],step)
        end
        for substep in recipe.xpath('//substep') do
            progress[:state][substep.id]
						progress[:state][substep.id][:visual] = 'ABLE' if is_able?(recipe,progress[:state],substep)
        end
        
        for media_id in recipe.xpath('//audio').map{|v| v.id} + recipe.xpath('//video').map{|v| v.id}
            progress[:play][media_id]
        end
        for noty_id in recipe.xpath('//notification').map{|v| v.id}
            progress[:notify][noty_id]
        end
				#STDERR.puts progress[:state]
				change[:state] = progress[:state].deep_dup

        # make first change for rendering prescription.
        change[:channel] = settings.start_channel
        
        # call a recommend function from the Module directed by "ession_data[:alg]"
        change[:recommended_order], temp_hash = update_recommended_order(recipe,progress,session_data[:alg])
        
        log_error "#{__FILE__}: at #{__LINE__}, nil is set to progress[:state]" if progress[:state].include?(nil)

        #        session_data[:logger].debug change[:recommended_order]
        #        session_data[:logger].debug "Before Merge1:" + temp_hash.to_s
        #        session_data[:logger].debug "Before Merge2:" + change[:state].to_s
        change[:state].deep_merge!(temp_hash)
        #        session_data[:logger].debug "After Merge  :" + change[:state].to_s

        c_ss = current_substep(recipe,change[:state])
        change[:detail] = c_ss.id


        # START時に再生すべきnotificationが無いか調べる
        ref_notify = progress[:notify]
        change[:notify] = register_notifies(c_ss.notifies,ref_notify,"start")

        session_logger.debug "\n\nSTART: change1: #{change[:notify]}"
        change[:notify].deep_merge!(register_notifies(recipe.root.notifies,ref_notify,"start"))
        session_logger.debug "\n\nSTART: change2: #{change[:notify]}"

        session_logger.info change
        log_error "#{__FILE__}: at #{__LINE__}, nil is set to progress[:state]" if progress[:state].include?(nil)

        return "success", change
    end

#################################################
## ROUTING EXTERNAL INPUT
#################################################
    def external_input(session_data,navi_algorithms)
        ex_input = JSON.parse(session_data[:json_data]["operation_contents"]).with_indifferent_access
        # ex_input sample : {“navigator”:”default”,”mode”:”order”,”action”:{“name”:”next”}}

        navi_alg = ex_input.include?(:navigator) ? ex_input[:navigator] : 'default'
        log_error "Unknown algorithm '#{navi_alg}' is directed in external input." unless navi_algorithms.include?(navi_alg)
        return navi_algorithms[navi_alg].route(session_data,ex_input)
    end

        
#################################################
## CLICK THE CHANNEL BUTTONS.
#################################################


    def channel(session_data, change=nil)
        change = Recipe::StateChange.new if nil==change
        change[:channel] = session_data[:json_data]["operation_contents"].to_sym
        return "success", change
    end

#################################################
## CLICK THE NAVI MENU TEXT.
#################################################


    def navi_menu(session_data, change=nil)
        change = Recipe::StateChange.new if nil==change
								
        id = session_data[:json_data]["operation_contents"].to_sym
        recipe = session_data[:recipe]
        node = recipe.getByID(id)

        ref_progress = session_data[:progress]

        if 'substep' == node.name then
            parent_id = node.parent.id
            ref_state = ref_progress[:state]
            parent_is_open = ref_state[parent_id][:is_opened]
            unless parent_is_open then
                temp = navimenu_step(recipe,ref_progress,parent_id,change)
								change.deep_merge(temp)
            end

            change[:detail] = id.to_s
        else
            temp = navimenu_step(recipe,ref_progress,id,change)
						change.deep_merge!(temp)
        end
        return "success", change
    end
    
    def navimenu_step(recipe, ref_progress, step_id,change)
        ref_state = ref_progress[:state]
        change[:state] = ref_state.deep_dup
        change[:state][step_id][:is_opened] = !ref_state[step_id][:is_opened]
        change[:recommended_order] = rendering(recipe,ref_progress[:recommended_order],change[:state])
        return change
    end
    
    def rendering(recipe, old_order, state)
        order = []
        for id in old_order.map{|v|v.to_sym}.find_all{|v| nil!=recipe.getByID(v,"step")} do
            order << id
            next unless state[id.to_sym][:is_opened]
            for substep in recipe.getByID(id).to_sub do
                order << substep.id
            end
        end
        return order
    end


#################################################
## MEDIA PLAYER CONTROL/LOG.
#################################################

        
    def _play_control(session_data,change=nil)
        operation_contents = session_data[:json_data]["operation_contents"]
        operation = operation_contents["operation"].to_sym
        id = operation_contents["id"].to_sym
        value = operation_contents.include?("value") ? operation_contents["value"] : nil

        ref_progress = session_data[:progress]
        recipe = session_data[:recipe]

        return play_control(recipe, ref_progress, operation,id,0,change,value)
    end
    
    PLAY_LOG_ONLY_OPERATIONS = [:JUMP,:FULL_SCREEN,:MUTE,:VOLUME]
    def play_control(recipe, ref_progress, operation,id,delay=nil,change=nil,value=nil)
        if nil == change then
            change = Recipe::StateChange.new
            change_play = change[:play][id]
            change_play = ref_progress[:play][id].deep_dup
        else
            change_play = change[:play][id]
            change_play.deep_merge!(ref_progress[:play][id])
        end

        case operation
            when :PAUSE,:JUMP,:FULL_SCREEN,:MUTE,:VOLUME then
                change_play[operation] << value
            else
                change_play[operation] = change_play[operation]+1
        end

        is_log_only_operation = PLAY_LOG_ONLY_OPERATIONS.include?(operation)
        unless is_log_only_operation then
            # operation == :PLAY
						#STDERR.puts change_play[:do_play]
						#STDERR.puts operation
						
            case operation
                when :PLAY then
                    change_play[:do_play] = true
                else # :PAUSE or :END_TO_PLAY
                    change_play[:do_play] = false
            end
						#STDERR.puts change_play[:do_play]
            media = recipe.getByID(id)
            delay = media.attributes.include?("delay") ? media["delay"] : "0" if nil == delay
            change_play[:delay] << delay
        end
        change[:play][id].deep_merge!(change_play)
        
        return "success", change
    end
		
		def stop_all_medias(recipe,ref_progress, substep, change)
			#			substep = recipe.getByID(substep.to_sym) if substep.kind_of?(Symbol) or substep.kind_of?(String)
			#STDERR.puts __LINE__
			for media in substep.children.to_a do
					next unless ['video','audio'].include?(media.name)
					id = media.id
					#STDERR.puts id
					state, temp = play_control(recipe, ref_progress, :PAUSE, id, 0)
					#STDERR.puts temp[:play][id]
					change[:play][id] = temp[:play][id]
			end
			state = "success" if !state
			return state, change						
		end
        
#################################################
## CHECK THE CHECKBOXES BESIDES THE NAVI MENU.
#################################################


    def check(session_data, change=nil,flag=nil)
        #        session_data[:logger].debug "progress: " + session_data[:progress].to_s
        ref_progress = session_data[:progress]
        ref_state = ref_progress[:state]


        change = Recipe::StateChange.new if change==nil

        id = session_data[:json_data]["operation_contents"]
        recipe = session_data[:recipe]
        elem = recipe.getByID(id)

        p_ss = current_substep(recipe,ref_state)


        #        session_data[:logger].debug "before check: " + change.to_s

        if "substep" == elem.name then
            #            session_data[:logger].info session_data[:progress]
            change[:state].deep_merge!(set_current_substep(recipe,ref_state,elem))
            change[:state].deep_merge!(check_substep(elem,flag,recipe,ref_state))
        elsif "step" == elem.name then
            change[:state].deep_merge!(set_current_step(recipe,ref_state,elem))
            change[:state].deep_merge!(check_step(elem,true,flag,recipe,ref_state))
            #            session_data[:logger].debug "check_step: " + change.to_s
        else
            log_error "check a element which is not a step or substep."
        end
        

#        session_data[:logger].debug "change:   " + change.to_s
#        session_data[:logger].debug "progress: " + ref_state.to_s
#        session_data[:logger].debug "merged: " + ref_state.deep_merge(change).to_s
        change[:recommended_order], temp_hash = update_recommended_order(recipe,ref_progress.deep_merge(change),session_data[:alg])
        change[:state].deep_merge!(temp_hash)


        #        session_data[:logger].debug "all merged." + change[:state].to_s
        ref_state = ref_state.deep_merge(change[:state])
        c_ss = current_substep(recipe,ref_state)
        

        if nil == c_ss then
            change[:notify].deep_merge!(register_notifies(p_ss.notifies, ref_progress[:notify], 'end')) unless nil == p_ss
            return "success", change
        end

        change[:detail] = c_ss['id']
        
        if p_ss != c_ss then
            change[:notify].deep_merge!(register_notifies(p_ss.notifies, ref_progress[:notify], 'end')) unless nil == p_ss
            change[:notify].deep_merge!(register_notifies(c_ss.notifies, ref_progress[:notify], 'start'))
        end
    
        return "success", change
    end
    
    def is_finished(ref_state,elem)
        ref_state[elem.id][:is_finished]
    end

    def update_is_finished(id, flag)
        return {id.to_sym=>{:is_finished=>flag}}
    end
    
    def check_substep(substep,flag,recipe,ref_state)
        flag = !is_finished(ref_state,substep) if nil==flag
        temp_hash = update_is_finished(substep.id, flag)

        step = substep.parent
        brothers = step.to_sub
        
        # maintain other substeps belonging to the same step
        default_order = recipe.max_order
        tar_order = substep.order(default_order)
        for ss in brothers do
            ss_order = ss.order(default_order)
            if ss_order==tar_order then
                is_finished = (ss==substep ? flag : ref_state[ss.id][:is_finished])
                temp_hash[ss.id] = {:is_finished=>is_finished,:visual=>'ABLE'}
            elsif ss_order<tar_order then
                temp_hash[ss.id] = {:is_finished=>true,:visual=>'ABLE'} if flag
            else
                temp_hash[ss.id] = {:is_finished=>false,:visual=>'OTHERS'} if !flag
            end
        end

        completed_ss = brothers.size
        for id in brothers.map{|v|v.id}
            if temp_hash.keys.include?(id) then
                next if temp_hash[id][:is_finished]
            else
                next if ref_state[id][:is_finished]
            end
            completed_ss = completed_ss-1
            break
        end
        is_completed = (completed_ss == brothers.size)
        is_touched = (completed_ss>0)

        if is_completed then
            temp_hash.deep_merge!(check_step(step, false, true, recipe, ref_state))
        else
            temp_hash.deep_merge!(check_step(step, false, false, recipe, ref_state))
        end


        # change all parent step to 'finished' if flag == true
        if flag == true and step.attributes.include?("parent") and is_touched then
            parents = step["parent"].split(" ").map{|v| recipe.getByID(v.to_sym,"step")}
            for parent_step in parents do
                temp_hash.deep_merge!(check_step(parent_step, true, flag, recipe, ref_state))
            end
        end

        if flag == false and step.attributes.include?("child") and !is_touched then
            children = step['child'].split(" ").map{|v| recipe.getByID(v.to_sym,'step')}
            for child in children do
                temp_hash.deep_merge!(check_step(child,true,flag,recipe,ref_state))
            end
        end
        
        return temp_hash.with_indifferent_access
    end

    def check_step(step, do_check_substeps, flag, recipe, ref_state)
        old_flag = is_finished(ref_state,step)
        flag = !old_flag if nil == flag
        id = step.id
        temp_hash = update_is_finished(id, flag)
        flag = temp_hash[id][:is_finished]
        if do_check_substeps then
            for child_id in step.to_sub.map{|v|v.id} do
               temp_hash.deep_merge!(update_is_finished(child_id,flag))
            end
        end
        
        attr = flag ? "parent" : "child"
        if old_flag != flag and step.attributes.include?(attr) then
            # check all ancestors/descendants
            for id in step[attr].split(" ").map{|v|v.to_sym} do
                temp_hash.deep_merge!(check_step(recipe.getByID(id),true,flag,recipe,ref_state))
            end
        end
        return temp_hash
    end
    
    
    
    def current_elem(recipe,states)
        candidate_IDs = states.find_all{|k,v| v[:visual]=="CURRENT"}.map{|k,v| k}
        hash = {}
        for cand in candidate_IDs do
            node = recipe.getByID(cand)
            log_error "There are two or more current #{node.name} '#{hash[node.name].id}' and '#{node.id}'." if hash.include?(node.name)
            hash[node.name] = node
        end
        return hash
    end
    
    def current_substep(recipe,states)
        return current_elem(recipe,states)["substep"]
    end

    def current_step(recipe,states)
        return current_elem(recipe,states)["step"]
    end


#################################################
## RENDERING RESPONCE TO VIEWER (PRESCRIPTION)
#################################################
    
    def create_prescription(delta,progress)
        subscription = []
        
        # CHANNEL
        subscription << render_channel(delta.after[:channel]) unless delta.after[:channel].empty?

        # DETAIL_DRAW
        subscription << render_detaildraw(delta.after[:detail]) unless delta.after[:detail].empty?

        # NAVI_DRAW
        subscription << render_navidraw(progress[:recommended_order],progress[:state]) unless delta.after[:state].empty? and delta.after[:recommended_order].empty?
        
        # PLAY
        subscription += render_media("Play",delta.after[:play]) unless delta.after[:play].empty?

        # NOTIFY
        subscription += render_media("Notify",delta.after[:notify]) unless delta.after[:notify].empty?
        
        return subscription
    end

    def render_detaildraw(detail)
        return {"DetailDraw"=>{"id"=>detail}}
    end

    def render_navidraw(order,states)
        array = []
        for id in order do
            array << {"id"=>id,"visual"=>states[id.to_sym][:visual].to_s,"is_finished"=>states[id.to_sym][:is_finished].to_i}
        end
        return {"NaviDraw"=>{"steps"=>array}}
    end
    
    def render_channel(channel)
        return {"ChannelSwitch"=>{"channel"=>channel.to_s}}
    end
    
    def render_media(media_type,change_play)
        subscription = []
        for id,hash in change_play do
            if hash[:do_play] then
                subscription << {media_type=>{"id"=>id,"delay"=> hash[:delay].last}}
            else
                subscription << {"Cancel"=>{"id"=>id}}
            end
        end
        raise "no media has been rendered." if subscription.empty?
        return subscription
    end

#################################################
## COMMON TOOLS FOR NAVIGATION CONTROLLER
#################################################

######### update by recommend function for navimenu reconstruction

    def update_recommended_order(recipe,_latest_progress,algorithm, prior_step=nil)
        latest_progress = _latest_progress.deep_dup
        latest_progress[:state].delete(nil)
        _latest_progress[:state].delete(nil)
        ref_states = latest_progress[:state]
        # It's very funny but deep_dup makes a nil element to both ref_states and latest_progress[:state]
        prior_step = nil if prior_step != nil and 'substep' == prior_step.name
        


        # sort steps
        node_array = algorithm.recommend(recipe,latest_progress,prior_step)
        change_state = set_visual_step(recipe,ref_states, node_array)
        

        ref_states = latest_progress[:state].deep_merge(change_state)
        default_order = recipe.max_order

        unless nil == prior_step then
            ref_states[prior_step.id][:is_opened] = true
        end


        id_array = []
        for step in node_array do
            step_id = step.id
            id_array << step_id
            next unless ref_states[step_id][:is_opened]

            substeps = step.to_sub.sort_by!{|v| v.order(default_order)}
            id_array += substeps.map{|v| v.id}
            
            is_current = ("CURRENT" == ref_states[step_id][:visual])
            
            # update visual for substeps
            sub_change_state = set_visual_substep(recipe,ref_states, substeps, is_current)
            change_state.deep_merge!(sub_change_state)
        end
        
        return id_array,change_state
    end
        
    def set_visual_step(recipe,ref_states,node_array, is_current=true)
        change = Recipe::StateChange.new
        change_states = ref_states.deep_dup
        is_first_unfinished_able = is_current
        

        for node in node_array do
            log_error "substep is input to set_visual_step" if 'substep' == node.name
            id = node.id
            change_states[id][:visual] = is_able?(recipe,ref_states,node) ? "ABLE" : "OTHERS"


            if ref_states[id][:is_finished] then
                change_states[id][:is_opened] = false
                next
            end
            next unless is_first_unfinished_able
            change_states.deep_merge!(set_current_step(recipe,ref_states,node))
            is_first_unfinished_able = false
        end
        return change_states
    end
            
    def set_visual_substep(recipe,ref_states,node_array, is_current=true)
    
        # maintain other substeps belonging to the same step
        default_order = recipe.max_order
        
        change = Recipe::StateChange.new
        change_states = change[:state]
        is_first_unfinished_able = is_current
        tar_order = default_order+1

        for ss in node_array.sort_by{|v|v.order(default_order)} do
            change_states[ss.id] = ref_states[ss.id]
            
            if change_states[ss.id][:is_finished] then
                change_states[ss.id][:visual] = 'ABLE'
                next
            elsif !is_first_unfinished_able then
                change_states[ss.id][:visual] = ss.order(default_order)==tar_order ? 'ABLE' : 'OTHERS'
                next
            end
            
            change_states.deep_merge!(set_current_substep(recipe,ref_states,ss))
            tar_order = ss.order(default_order)
            is_first_unfinished_able = false
        end
        return change_states
    end
    
    def set_current_step(recipe,ref_states,new_current)
        n_ss = first_unfinished_substep(new_current,recipe,ref_states)
        
        default_order = recipe.max_order
        n_ss = new_current.to_sub.sort_by{|v|v.order(default_order)}.last if nil == n_ss
        return set_current_substep(recipe,ref_states,n_ss)

        return hash
    end
    
    def set_current_substep(recipe,ref_states,new_current)
        hash = {}.with_indifferent_access

        c_s = current_step(recipe,ref_states)
        unless nil == c_s then
            hash[c_s.id] = {
                    :is_finished => ref_states[c_s.id][:is_finished],
                    :visual => is_able_step?(recipe,ref_states,c_s)? 'ABLE' : 'OTHERS',
                    :is_opened => false
            }
        end
        hash[new_current.parent.id] = {
            :is_finished =>false,
            :visual => 'CURRENT',
            :is_opened => true
        }

        c_ss = current_substep(recipe,ref_states)
        unless nil==c_ss then
            hash[c_ss.id] = {
                :is_finished => ref_states[c_ss.id][:is_finished],
                :visual => is_able_substep?(recipe, ref_states,c_ss) ? 'ABLE' : 'OTHERS'
            }
        end
        hash[new_current.id] = {
            :is_finished => false,
            :visual => 'CURRENT'
        }
        return hash
    end



######### register notification / media
    def check_fired_triggers(trigger_array,timing,events=nil)
        delay = []
        if nil == events
            events = []
        elsif events.kind_of?(String)
            events = events.split(/\s+/).sort
        end
        events.sort!
        
        for trigger in trigger_array do
            if trigger.include?('ref') then
                ref_events = trigger['ref'].to_s.split(/\s+/).sort
                # check the events
                next unless ref_events == events
            elsif nil != events
                next
            end

            # check the timing
            next unless trigger[:timing] == timing

            delay << (trigger.include?(:delay) ? trigger[:delay].to_f : 0)
        end
        return delay
    end

    # event == nil when checking recipe, substep or step's start/end.
    def register_notifies(notifies, latest_notify, timing, event=nil, force = false)
        change_notify = Hash.new
				
        for notify in notifies do
            delay = check_fired_triggers(notify.trigger,timing,event)
            
            next if delay.empty? # no trigger has fired.
            view_times = latest_notify[notify.id][:PLAY]
            next if 0 < view_times and !force
            temp = notify_control(latest_notify,change_notify,notify,true,delay.min)
						change_notify.deep_merge!(temp)
        end
        return change_notify
    end
    
    def notify_control(ref_notify, change_notify, notification_node, do_play, delay)
        target = ref_notify[notification_node.id].deep_dup
        target[:do_play] = do_play
        target[:PLAY] = target[:PLAY]+1
        target[:delay] << delay
				
				return {notification_node.id=>target}
    end

######### is_able? (for step/substep)
    def is_able?(recipe,ref_states,node)
        if "step" == node.name then
            return is_able_step?(recipe,ref_states,node)
        elsif "substep" == node.name then
            return is_able_substep?(recipe,ref_states,node)
        end
        log_error "invalid node for function 'is_able'."
    end
    
    def is_able_step?(recipe,ref_states,node)
        # the node without any parents is always 'able'
        return true unless node.attributes.include?('parent')

        parents = node['parent']
        for pid in parents.split(/\s+/).map{|v|v.to_sym} do
            return false unless ref_states[pid][:is_finished]
        end
        return true
    end
    
    def is_able_substep?(recipe,ref_states,node)
        default_order = recipe.max_order
        my_order = node.order(default_order)
        prior_siblings = node.parent.to_sub.find_all{|v|v.order(default_order) < my_order}
        
        return is_able_step?(recipe,ref_states,node.parent) if prior_siblings.empty?

        for prior_substep in prior_siblings do
            return false if !ref_states[prior_substep.id][:is_finished]
        end
        return true
    end

    def first_unfinished_substep(target_step,recipe,ref_state)
        default_order = recipe.max_order
        substeps = target_step.to_sub.sort_by{|v|v.order(default_order)}
        for ss in substeps do
            return ss unless ref_state[ss.id][:is_finished]
        end
        return nil
    end
        
    def is_on_context?(recipe,ref_progress,media_node)
        parent = media_node.parent
        return true if recipe.root == parent # for global notification
        
        # parent must be a substep
        log_error "unexpected parent of media node #{media_node.id}. Has the hwml definition changed??" unless 'substep' == parent.name

        return ((parent == current_substep(recipe,ref_progress[:state])) or (parent['id'] == ref_progress[:detail]))
    end


end
end