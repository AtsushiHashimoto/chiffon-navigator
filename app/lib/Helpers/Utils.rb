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
		def deep_diff(b)
			a = self
			#STDERR.puts (a.keys | b.keys).join("/")
			(a.keys | b.keys).inject([{},{}]) do |diff, k|
				if k==nil
				elsif a[k] != b[k]
					if a[k].respond_to?(:deep_diff) and b[k].respond_to?(:deep_diff)
						ak, bk = a[k].deep_diff(b[k])
						diff[0][k] = (nil==ak or ak.empty?) ? :__clear__ : ak
						diff[1][k] = (nil==bk or bk.empty?) ? :__clear__ : bk
					else
						#STDERR.puts "clear a[#{k}]? : #{a[k]}" if a[k]==nil
						#STDERR.puts "clear b[#{k}]? : #{b[k]}" if b[k]==nil
						diff[0][k] = a[k]==nil ? :__clear__ : a[k]
						diff[1][k] = b[k]==nil ? :__clear__ : b[k]
					end
				end
				diff
			end
		end
		
		def delete_nil_key!
			for key,val in self do
				self.delete(key) if key == nil
				next unless val.respond_to?(:delete_nil_key!)
				val.delete_nil_key!
			end
			self
		end
				
		def delete_nil!
			for key,val in self do
				self.delete(key) if val == nil
				next unless val.respond_to?(:delete_nil!)
				val.delete_nil!
			end
		self
		end
			
		def deep_merge_with_clear_flag!(other, do_remove_flag=true)
			self.clear_by!(other)
			if do_remove_flag then
				other.remove_empty_elem!
				_other = other.remove_clear_flag!
			else
				_other =  other.remove_empty_elem
				_other = _other.remove_clear_flag
			end

			self.deep_merge!(_other)
			merged = self.deep_merge!(_other)
		end
		

		def clear_by(other)
			buf = self.deep_dup
			return buf.clear_by(other)
		end
		def clear_by!(other)
			if other==:__clear__ or other=='__clear__'
				self.clear
				return
			end					
			
			for key,val in self do				
				if key.respond_to?(:to_sym) then
					oth_val = other[key.to_sym]
				else						
					oth_val = other[key]
				end

				next if nil==oth_val
				if :__clear__==oth_val or '__clear__'==oth_val then
					self.reject!{|k,v| k==key}
					next
				end
				next unless val.respond_to?(:clear_by!)
				next unless oth_val.kind_of?(Hash)
				self[key] = val.clear_by!(oth_val)
			end
			self
		end
				
		def remove_empty_elem
			buf = self.deep_dup
			buf.remove_empty_elem!
		end
		def remove_empty_elem!
			for key, elem in self do
				next unless elem.respond_to?(:empty?)
				next unless elem.empty?
				self.delete(key)				
			end
		end
				
		def remove_clear_flag
			buf = self.deep_dup
			buf.remove_clear_flag!
		end
		def remove_clear_flag!
			for key,val in self do
				self.reject!{|k,val| k==key} if val == :__clear__ or val == '__clear__'
				next unless val.respond_to?(:remove_clear_flag!)
				val.remove_clear_flag!
			end
			self
		end
			
		def set_clear_flag(other)
			buf = self.deep_dup
			buf.remove_clear_flag(other)
		end
		def set_clear_flag!(other)
				for key,val in other do
					my_val = self[key.to_s]
					my_val = self[key.to_sym] unless my_val
					if nil == my_val
						self[key] = :__clear__
						next
					end
					next unless val.kind_of?(Hash)
					next unless my_val.kind_of?(Hash)
					my_val.set_clear_flag!(val)
				end
				self
		end
end