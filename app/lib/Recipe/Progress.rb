require 'lib/Recipe/ProgressState.rb'
require 'lib/Recipe/Delta.rb'

module Recipe

Progress = ProgressState
class Progress
		@@default_keys = [:recommended_order,:channel,:detail,:play,:notify,:iter_index,:state]
    def update!(change,delta)
			#=begin
			change.delete_nil!
			change.delete_nil_key!
			
			prev_progress= self.deep_dup
			delta.after = change
			iter_index_prev = self[:iter_index]
			STDERR.puts change[:ObjectAccess]
			STDERR.puts self[:ObjectAccess]
			
			self.deep_merge_with_clear_flag!(change,true)

			self.delete_nil!
			self.delete_nil_key!
			#			STDERR.puts self
			
			
			
			delta.before, temp= prev_progress.deep_diff(self)
			
			if delta.before == delta.after then
				delta.clear
			else
				# update iteration index unless any index is specified in 'change.'
				change[:iter_index] = iter_index_prev + 1 if change[:iter_index] < 0
				delta.before[:iter_index] = iter_index_prev
				self[:iter_index] = change[:iter_index]
			end
			#=end			
=begin			
				change.delete_nil_key!
        delta.after = change
				prev_progress = self.deep_dup
        for key in [:recommended_order,:channel,:detail] do
            next if change[key].empty?
            delta.before[key] = self[key]
            self[key] = change[key]
        end

        for key in [:play,:notify] do
            for id,val in change[key] do
                next if self[key][id] == val
                delta.before[key][id] = self[key][id].deep_dup
                self[key][id] = val.deep_dup
            end
        end
        for key,val in change[:state] do
            next if key==nil # deep_dup caused an errorly elem. ignore it.
						next if key.empty?
            raise "Unknown ID '#{key}' is directed in state change." unless self[:state].include?(key)
            delta.before[:state][key] = self[:state][key].deep_dup
            #            STDERR.puts "#{key}: #{val}"
            self[:state][key].deep_merge!(val)
        end

        # fill previous order as a recommended_order at this iteration.
        change[:recommended_order] = self[:recommended_order] if change[:recommended_order].empty? and !change[:state].empty?
				
				# custom state for each algorithm
				for key in change.keys - @@default_keys do
						if self.include?(key) and self[key]!=nil then
							self[key] = self[key].clear_by(change[key])
							next if change[key].to_s == '__clear__'
							change[key].remove_clear_flag!
							STDERR.puts change[key]

							next if self[key]==nil
							self[key].deep_merge!(change[key])
						else
							self[key] = change[key].deep_dup
						end
				end
        
        if delta.before == delta.after then
            delta.clear
        else
            # update iteration index unless any index is specified in 'change.'
            change[:iter_index] = self[:iter_index] + 1 if change[:iter_index] < 0
            delta.before[:iter_index] = self[:iter_index]
            self[:iter_index] = change[:iter_index]
        end
				# set flag for the values firstly appeared at this iteration.
				delta.before.set_clear_flag!(prev_progress)
=end
		end
end

end