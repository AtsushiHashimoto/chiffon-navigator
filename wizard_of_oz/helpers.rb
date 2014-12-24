module Sinatra
    module MyHelpers
        def js_path(basename)
            "/woz/" + settings.js_dir + "/" + basename + ".js"
        end
        def render_js(js_file)
            raise "java script file '#{js_path(js_file)}' is not found." unless File.exist?("#{settings.root}/public/#{js_path(js_file)}")
            @js_file = js_file
            haml '%script(src="#{js_path(@js_file)}" type="text/javascript")'
        end
        
        def css_path(basename)
            "/woz/" + settings.css_dir + "/" + basename + ".css"
        end
        
        def render_css(css_file)
            raise "css file '#{css_path(css_file)}' is not found." unless File.exist?("#{settings.root}/public/#{css_path(css_file)}")
            @css_file = css_file
            haml '%link(href="#{css_path(@css_file)}" rel="stylesheet" type="text/css")'
        end
        
        def generate_event_btn(node)
            
        end
        
        def render_external_input(action_name,options={},navigator="default")
            hash = {"navigator"=>navigator, "action"=>{}}
            hash["action"]["name"] = action_name
            for key,val in options do
                hash["action"][key] = val
            end
            return hash.to_json
        end
        
        def render_navi_steps(steps)
            html = ""
            steps = steps.to_a
            @i = 1
            for step in steps do
                @step_id = step['id']
                @step_navi_text = step['navi_text']
                @substeps = step.to_sub
                html += haml :navi_step
                @i = @i+1
            end
            return html
        end
        def render_navi_substeps(substeps)
            html = ""
            for substep in substeps
                @substep_id = substep['id']
                @substep_navi_text = substep['navi_text']
                html += haml :navi_substep
            end
            return html
        end
        def render_select_jump(recipe)
            html = ""
            for @step in recipe.xpath("//step").to_a.sort_by{|v| v.id} do
                @substeps = @step.to_sub
                html += haml '%li.step=haml \'%a.select_controller(role="menuitem" tabindex="-1" href="#" data-target="#{@step["id"]}" data-navigator="default" data-action="jump")= @step["navi_text"]\''
                for @substep in @step.to_sub do
                    html += haml '%li.substep= haml \'%a.select_controller(role="menuitem" tabindex="-1" href="#" data-target="#{@substep["id"]}"  data-navigator="default" data-action="jump")= "- " + @substep["navi_text"]\''
                end
                html += haml '%li.divider'
            end
            return html
        end

        def render_select_event(recipe)
            html = ""
            for @trigger in recipe.xpath('//trigger').to_a.find_all{|v|v.attributes.include?('ref')}.sort_by{|v| v.include?('ref')} do
                html += haml '%li.event=haml \'%a.select_controller(role="menuitem" data-navigator="default" data-action="event" data-target="#{@trigger["ref"]}" tabindex="-1" href="#")=@trigger["ref"]\''
            end
            return html
        end
    end
end