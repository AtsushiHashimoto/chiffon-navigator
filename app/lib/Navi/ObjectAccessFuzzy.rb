module Navi
    class ObjectAccessFuzzy
				@@sym = :ObjectAccessFuzzy
				@@is_valid_error_message = 	"invalid ex_input has been casted."
				@@thresh_release = 0.5
				@@thresh_touch = 0.5
				@@ex_input_oa_template = JSON::parse('{"navigator":"object_access","action":{}}').with_indifferent_access

        def initialize(app)
            @app = app
				end
				def log_error(str)
					raise str
				end

		
##########################
# ObjectAccess External Input
##########################
				def route(session_data,ex_input)
					#STDERR.puts "object_access_fuzzy"
					session_data = session_data.with_indifferent_access
					ex_input = ex_input.with_indifferent_access

					session_data[:progress][@@sym],change = self.init(session_data,ex_input)
					return main_process(session_data,ex_input,change)
				end

# example) ex_input for ObjectAccessFuzzy
# at least, class_likelihood is necessary for this module.
=begin

{
	"data_id":0,
	"timestamp":{
	"created_time":"2014.08.11_18.36.33.395000",
	"received_time":""
	},
	"class_list":["物体id 1", "物体id 2", "物体id 3",...],
	"instances":[
		{
			"instance_id":0,
			"feature": [1.23,4.35,4.23,2.23],
			"location": [40,80],
			"action":{
				"grabbed":0.68,
				"released":0.2,
				"in_hand":1.33
			},
			"class_likelihood": [1.32,4.65,4.65,2.43]
		},
		{
			"instance_id":0,
			"feature": [1.23,4.35,4.23,2.23],
			"location": [40,80],
			"action":{
				"grabbed":0.68,
				"released":0.2,
				"in_hand":1.33
			},
			"class_likelihood": [1.32,4.65,4.65,2.43]
		}
	]
}

=end
				

############################
# ObjectAccess Initialize State
############################

				def init(session_data,ex_input)
						recipe = session_data[:recipe]
						change = Recipe::StateChange.new
						
						is_valid?(session_data,ex_input)

						change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new		

						if session_data[:progress].include?(@@sym) then
							oaf_data = session_data[:progress][@@sym].deep_dup
							STDERR.puts __LINE__
						else
							@app.log_error "the first message must contain class_list." unless ex_input[:action].include?(:class_list)
							change[@@sym][:object_states] = ActiveSupport::HashWithIndifferentAccess.new
							change[@@sym][:class_list] = []
							oaf_data = change[@@sym].deep_dup
#							STDERR.puts "newly initialized"
						end
						
						oaf_data,is_changed = update_class_list(oaf_data,ex_input[:action][:class_list])
						if is_changed then
							change[@@sym][:class_list] = oaf_data[:class_list].deep_dup
							change[@@sym][:object_states] = oaf_data[:object_states].deep_dup
						end
						
						
						return oaf_data.deep_dup,change
				end
				
				def is_valid?(session_data,ex_input)
					log_error "#{@@is_valid_error_message}: no timestamp" unless ex_input[:action].include?('timestamp')
					log_error "#{@@is_valid_error_message}: no created_time in timestamp" unless ex_input[:action][:timestamp].include?(:created_time)

					for instance in ex_input[:action][:instances] do
						log_error "#{@@is_valid_error_message}: no class_likelihood for an instance" unless instance.include?(:class_likelihood)
						log_error "#{@@is_valid_error_message}: empty class_likelihood for an instance" if instance[:class_likelihood].empty?
					end
				end
					
				def update_class_list(oaf_data,class_list)
					class_list = class_list.map{|v|v.to_sym}
					return oaf_data, false if oaf_data.include?(:class_list) and class_list == oaf_data[:class_list]
					#STDERR.puts class_list
					#STDERR.puts oaf_data[:class_list]
					if oaf_data.include?(:class_list) then
						new_objects = class_list - oaf_data[:class_list]
					else
						new_objects = class_list
					end
					
					for obj in new_objects do
						STDERR.puts "init: #{obj}"
						oaf_data[:object_states][obj] = 0.0
					end
					oaf_data[:class_list] = class_list
					return oaf_data, true
				end
						
############################
# Main process and sub_routins
############################
				def pooling(oaf_data_ref, instances)
						obj_states = oaf_data_ref[:object_states].deep_dup
						#STDERR.puts __LINE__
						#STDERR.puts oaf_data_ref[:class_list]
						for instance in instances do
							likelihood = instance[:class_likelihood]							
							log_error "different length of class_likelihood and class_list" unless likelihood.size == oaf_data_ref[:class_list].size
							prob_diff = instance[:action][:grabbed].to_f - instance[:action][:released].to_f
							
							for i in 0...likelihood.size do
								class_id = oaf_data_ref[:class_list][i]
								l = likelihood[i]
								prob_in_hand = obj_states[class_id]
								STDERR.puts __LINE__
								STDERR.puts class_id
								STDERR.puts l
								STDERR.puts prob_diff
								STDERR.puts prob_in_hand
								# P(prob_in_hand^t_c)=P(c|blob)P(prob_in_hand^{t-1}_blob)
								# YOU NEED TO DESIGN AN APPROPRIATE POOLING FUNCTION!!!
								obj_states[class_id] = prob_in_hand + (l*prob_diff)									
								STDERR.puts obj_states
							end
						end
						
						# prob_in_hand must be in [0,1]
						for id, prob in obj_states do
							obj_states[id] = [[1,prob].min,0].max
						end					

						return obj_states
				end
	
				def main_process(session_data,ex_input,change)				
					#STDERR.puts "main_process!"
					timestamp = ex_input[:action][:timestamp][:created_time]
					oaf_data_ref = session_data[:progress][@@sym]

					# instance->class pooling
					obj_states = pooling(oaf_data_ref,ex_input[:action][:instances])
					
					
					change[@@sym][:object_states] = obj_states.deep_dup
					
					released_objects, touched_objects = state_diff(obj_states,oaf_data_ref[:object_states])		
					
					return "success", change if released_objects.empty? and touched_objects.empty?
					
					ex_input_oa = @@ex_input_oa_template.deep_dup
					ex_input_oa[:action][:name] = 'auto_detection'
					STDERR.puts "released: #{released_objects.join(" ")}"
					STDERR.puts "touched: #{touched_objects.join(" ")}"
					ex_input_oa[:action][:released] = released_objects
					ex_input_oa[:action][:touched] = touched_objects
					ex_input_oa[:action][:timestamp] = timestamp
					
					state,temp = @app.navi_algorithms['object_access'].route(session_data,ex_input_oa)
					change.deep_merge!(temp)
					STDERR.puts change[@@sym]
					return state,change
				end
				
				def state_diff(new_states,old_states)
					released_objects = []
					touched_objects = []
					for id, new_prob in new_states do
							old_prob = old_states[id]
							if old_prob > @@thresh_release and new_prob <= @@thresh_release then
								released_objects << id
							elsif old_prob <= @@thresh_touch and new_prob > @@thresh_touch then
								touched_objects << id
							end
					end
					return released_objects, touched_objects
				end
		end
end

