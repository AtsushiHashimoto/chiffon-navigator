require 'rubygems'
require 'nokogiri'

require 'lib/Recipe/Progress'

module Recipe

Recipe = Nokogiri::XML::Document
class Nokogiri::XML::Document
    def getByID(id, name=nil)
        name = "*" if nil == name
        elements = self.xpath("//#{name}[@id='#{id.to_s}']")
        raise "several elements has the same ID '#{id.to_s}.'" if elements.size > 1
        if elements.empty? then
            if nil == name then
                raise "no element with ID '#{id.to_s}' was found." if elements.empty?
            end
            return nil
        end
        return elements[0]
    end
    
    def max_order
				return root['max_order'].to_i if root.attributes.include?('max_order')
				array = self.xpath('//substep').to_a
				temp = array.map{|v|
					v.attributes.include?('order') ? v['order'].to_i : 0
				}
        root['max_order'] = temp.max
        return temp.max
    end
        
    def add_parent2child_link
        steps = self.xpath('//step')
        for step in steps do
            raise "step in recipe must have '@id' attribute." unless step.attributes.include?('id')
            next unless step.attributes.include?('parent')
            parents = step['parent'].split(/\s+/)
            for pid in parents do
                parent = self.getByID(pid,"step")
                if parent.attributes.include?('child') then
                    parent['child'] = "#{parent['child']} #{step['id']}"
                else
                    parent['child'] = step['id']
                end
            end
        end
    end
        
    def triggerable_nodes(node_types)
        hash = Hash.new{|hash,key| hash[key]=[]}
        xpath_query = node_types.map{|v| "//#{v}/trigger"}.join(" | ")
        for cand in self.xpath(xpath_query) do
            cand.give_def_trigger_attr
            temp = cand.to_attr_hash
            hash[cand.parent] << temp
        end
        return hash
    end
end

class Nokogiri::XML::Node
    def to_sub
        self.children.to_a.find_all{|v|"substep"==v.name}
    end
    
    def notifies
        self.children.to_a.find_all{|v|"notification"==v.name}
    end
    
    def media
        self.children.to_a.find_all{|v|"audio"==v.name or "video"==v.name}
    end
    
    def to_attr_hash
        Hash[*(self.attributes.map{|key,node| [key,node.value]}.flatten(1))].with_indifferent_access
    end
    
    def give_def_trigger_attr
        self['timing'] = 'start' unless self.attributes.include?(:timing)
    end
    
    def trigger
        return self.children.to_a.find_all{
            |v| "trigger"==v.name
        }.map{|t|
            t.give_def_trigger_attr
            t.to_attr_hash
        }
    end

    def order(default_order=-1)
        self.attributes.include?('order') ? self['order'].to_i : default_order
    end
    
    def id
        raise "A node without '@id': #{self}" unless self.attributes.include?("id")
        self["id"].to_sym
    end
		
		def is_next?(id)
				if self['name'] == 'step' then
						return self.children.to_a.map{|v|v.id}.include?(id)
				elsif self['name'] == 'substep' then
						bros = self.parent.to_sub
						default_order = recipe.max_order
						my_order = bros.order(default_order)
						array = []
						for ss in bros do
								next if my_order > ss.order(default_order)
								next if ss.id == self.id
								break if !array.empty? and my_order + 1 < ss.order(default_order)
								array << ss.id
						end
						return array.include?(id)
				end
				return false
		end
end

end