class FalseClass; def to_i; 0 end end
class TrueClass; def to_i; 1 end end

class Array
    def subset_of?(other)
        return (self - other).empty?
    end
end

class Object
    def to_b
        compare_value = self.class == String ? self.downcase : self
        case compare_value
            when "yes", "true", "ok", true, "1", 1, :true, :ok, :yes
                true
            else
                false
        end
    end
end