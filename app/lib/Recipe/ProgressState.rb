module Recipe
    class ProgressState < Hash #ActiveSupport::HashWithIndifferentAccess

        def empty?
            for key,val in self do
                next if key == :iter_index
                return false unless val.empty?
            end
            return true
        end

        def initialize()#constructor = {})
            #super(constructor)
            # iteration index
            self[:iter_index] = -1
            
            # the substep whose detail is displayed
            self[:detail] = ""
            
            # the order of step/substeps to generate NaviDraw
            self[:recommended_order] = []
            
            # :OVERVIEW|:MATERIALS|:GUIDE
            self[:channel] = ""

            # state (:visual=>:OTHERS|:CURRENT|:ABLE, :is_finished=>bool)
						self[:state] = ActiveSupport::HashWithIndifferentAccess.new # {|hash,key| hash[key] = {:visual=>"OTHERS",:is_finished=>false}}
            
            # audio/video playing history(:views) and :delay to render Play (and Chancel)
						self[:play] = ActiveSupport::HashWithIndifferentAccess.new
=begin
						{
                |hash,key| hash[key] = {
                    :do_play=>false,
                    :delay=>[],
                    :PLAY=>0,
                    :PAUSE=>[],
                    :JUMP=>[],
                    :TO_THE_END=>0,
                    :FULL_SCREEN=>[],
                    :MUTE=>[],
                    :VOLUME=>[],
                }
            }
=end
																																				

            # to render Notify (and Chancel)
            self[:notify] = ActiveSupport::HashWithIndifferentAccess.new
=begin
						 {|hash,key| hash[key] = {
                :delay=>[],
                :do_play=>false,
                :PLAY=>0}
            }
=end
        end
				def init_state(key)
					return if self[:state][key]
					self[:state][key] = {:visual=>"OTHERS",:is_finished=>false}
				end
				def init_play(key)
					return if self[:play][key]
					self[:play][key] = {
						:do_play=>false,
						:delay=>[],
						:PLAY=>0,
						:PAUSE=>[],
						:JUMP=>[],
						:TO_THE_END=>0,
						:FULL_SCREEN=>[],
						:MUTE=>[],
						:VOLUME=>[],
					}
				end
				def init_notify(key)
					return if self[:notify][key]
					self[:notify][key] = {
						:delay=>[],
						:do_play=>false,
						:PLAY=>0
					}

				end

    end
    StateChange = ProgressState # alias for ProgressState
end
class Hash
    def to_progress
        buf = Recipe::ProgressState.new
        buf.deep_merge(self)
    end
end
