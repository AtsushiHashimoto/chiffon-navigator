module Navi
    class ObjectAccessFuzzy
				@@sym = :ObjectAccessFuzzy
				@@is_valid_error_message = 	"Error: invalid ex_input has been casted."
				@@thresh_release = 0.5
				@@thresh_touch = 0.5

        def initialize(app)
            @app = app
				end
		
##########################
# ObjectAccess External Input
##########################
				def route(session_data,ex_input)					
					session_data[:progress][@@sym],change = self.init(session_data,ex_input)					
					return self.main_process(session_data,ex_input,change)
				end

# example) ex_input for ObjectAccessFuzzy
# at least, class_likelihood is necessary for this module.
=start

{
	"data_id":0,
	"timestamp":"{
	"created_time":"2014.08.11_18.36.33.395000",
	"received_time":""
	}",
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
							oaf_data = session_data[:progress][@@sym]
						else
							log_error "ERROR: the first message must contain class_list." unless ex_input[:action].include?(:class_list)
							change[@@sym][:object_states] = ActiveSupport::HashWithIndifferentAccess.new
							session_data[:progress][@@sym] = change[@@sym].deep_dup
						end
						
						oaf_data,is_changed = update_class_list(oaf_data,ex_input[:action][:class_list])
						if is_changed
							change[@@sym][:class_list] = oaf_data[:class_list].deep_dup
							change[@@sym][:object_states] = oaf_data[:object_states].deep_dup
							session_data[:progress][@@sym] = change[@@sym].deep_dup
						end
						
						
						return oaf_data,change
				end
				
				def is_valid?(session_data,ex_input)
					log_error "#{@@is_valid_error_message}: no timestamp" unless ex_input[:action].include?(:timestamp)
					log_error "#{@@is_valid_error_message}: no created_time in timestamp" unless ex_input[:action][:timestamp].include?(:created_time)

					for instance in ex_input[:action][:instances] do
						log_error "#{@@is_valid_error_message}: no class_likelihood for an instance" unless instance.include?(:class_likelihood)
						log_error "#{@@is_valid_error_message}: empty class_likelihood for an instance" if instance[:class_likelihood].empty?
					end
				end
					
				def update_class_list(oaf_data,class_list)
					class_list.sort!
					new_objects = class_list - oaf_data[:class_list]
					return oaf_data false if new_objects.empty?
					
					oaf_data[:class_list] += new_objects
					oaf_data[:class_list].sort!
					for id in new_objects do
						oaf_data[:object_states][id] = 0.0
					end
					
				end
						
############################
# Touch/Release process
############################
				def main_process(session_data,ex_input,change)				
					STDERR.puts "main_process!"
					timestamp = ex_input[:action][:timestamp][:created_time]
					oaf_data_ref = session_data[:progress][@@sym]
					obj_states = session_data[:progress][@@sym][:object_states].deep_dup
										
					for instance in ex_input[:action][:instances] do
							likelihood = instance[:class_likelihood]
							log_error "ERROR: different length of class_likelihood and class_list" if likelihood.size == oaf_data[:class_list].size
							
							prob_diff = instance[:action][:grabbed].to_r - instance[:action][:grabbed].to_r
														
							for i in 0...likelihood.size do
									class_id = oaf_data_ref[:class_list][i]
									likelihood = likelihood[i]
									prob_in_hand = obj_states[class_id]
									obj_states[class_id] = prob_in_hand + prob_diff									
							end
					end
					
					# prob_in_hand must be in [0,1]
					for id, prob in obj_states do
							obj_states[id] = [[1,prob].min,0].max
					end					
					change[@@sym][:object_states] = obj_states
					
					released_objects, put_objects = state_diff(obj_states,oaf_data_ref[:object_states])
					
					ex_input_oa = Hash.new
					
					
					state,temp = @app.algorithm['object_access'].route(session_data,ex_input_oa)
					change.deep_merge!(temp)
					return state,change
					end					
				end
				
				def state_diff(new_states,old_states) do
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
					return released_objects, put_objects
				end
		end
end

