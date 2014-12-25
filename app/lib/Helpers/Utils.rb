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

class Time
		def self.parse_my_timestamp(timestamp_str)
			#			2014.11.13_12.43.45.471616
			buf = /(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\.(\d+)/.match(timestamp_str)
			return nil if nil == buf[0]
			Time.utc($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,"#{$6}.#{$7}".to_r)
		end
end

class Hash
		def clear_by(other)
				for key,val in self do
					next unless other.include?(key)
					if :clear==other[key] then
						self.delete(key)
						other.delete(key)
						next
					end
					next unless val.kind_of?(Hash)
					next unless other[key].kind_of?(Hash)
					self[key] = val.clear_by(other[key])
				end
		end
end