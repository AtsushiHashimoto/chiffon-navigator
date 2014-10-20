require 'rubygems'
require 'json'
require 'lib/Recipe/ProgressState.rb'
module Recipe
    
class Delta
    attr_accessor :before,:after
    def initialize
        clear
    end
    def +(other)
        @before.deep_merge!(other.before)
        @after.deep_merge!(other.after)
    end

    def clear
        @after = ProgressState.new
        @before = ProgressState.new
    end
    
    def empty?
        @after.empty? and @before.empty?
    end
    
    def to_s
        return self.to_array.to_s
    end

    def to_array
        return [before,after]
    end
    
    def parse(str)
        @before, @after = JSON.parse(str,{:symbolize_names => true})
    end
        
    def load(source)
        load_io(source) if source.instance_of?(IO)
        load_io(File.open(source,"r"))
    end
    def load_io(io)
        parse(io.read)
    end

end

end

class Array
    def to_delta
        buf = Recipe::Delta.new
        return buf if self.length == 0
        buf.before.deep_merge!(self[0])
        return buf if self.length < 1
        buf.after.deep_merge!(self[1])
        return buf
    end
end
