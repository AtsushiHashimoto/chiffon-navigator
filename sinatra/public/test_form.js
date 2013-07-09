
function form2json(form_id){
	var param = {};
	var form = $("form#"+form_id);
	$(form.serializeArray()).each(function(i,v){
		if(v.name!="time"){
			param[v.name] = v.value;
		}else{
			
			var sec = Date.parse(v.value);
			var usec = 0;
			var time_t = {};
			time_t["sec"]=sec;
			time_t["usec"]=usec;
			param["time"] =time_t
		}

			});
	var json_str = $.toJSON(param);
	return json_str;
}

function showText2DOMElem(dom_elem,str){
	$(dom_elem).html(str);
}

function submit2chiffon_navigator(jason_string,navigator_url){
	var geturl = $.ajax({
		type: "post",
		url: navigator_url,
		data: json_string,
		error: function(){alert("failed to communicate with the navigator.");},
		success: function(response){showText2DOMElem("div#prescription",geturl.getAllResponseHeaders()+"\n"+response);}
			});

}


function form_click(form_id,chiffon_navigator_url){
	json_string = form2json(form_id);
	showText2DOMElem("div#navigation_request",json_string);
	submit2chiffon_navigator(json_string,chiffon_navigator_url);
}


function updateTime(){
	$('#hidden_time').toDate({format:'Y/m/d h:i:s'});
	var time = $('#hidden_time').text();
	$('input#_time').val(time);
}
