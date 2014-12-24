jQuery(function ($) {

    // global variables
    var DEBUG = 1;
    var notification_live_sec;

    var receiver_url;
    var logger_url;
    var jobs = {};
    var seconds = 1000;
    var session_id;
    
       
    // show_notify
    var show_notify = function (obj, on_debug) {
       if (on_debug) {
           if(DEBUG) noty(obj);
       }
       else {
           noty(obj);
       }
    };

       
    // loading
    $(document)
        .ajaxStart(function () {
            $('#loading')
                .css("top", $(window)
                    .scrollTop() + "px")
                .css("left", $(window)
                    .scrollLeft() + "px")
                .show(0);
        })
        .ajaxComplete(function () {
            $('#loading')
                .hide(0);
        })
        .ajaxError(function () {
            show_notify({
                type: 'error',
                text: 'AJAX ERROR'
            });
        });

    // チャンネルの定義テーブル
    var channels = {
        'OVERVIEW': 'overview',
        'MATERIALS': 'materials',
        'GUIDE': 'guide'
    };

    // メニューの表示切り替えテーブル
    var navigations = {
        'finished': 'navi-finished',
        'is_open': 'pane-open',
        'is_close': 'pane-close',
        'CURRENT': 'navi-current',
        'ABLE': 'navi-able',
        'OTHERS': 'navi-others'
    };

    // メニュー初期化用クラス名
    var navigation_classes = $.map(navigations, function (value, key) {
        return value
    })
        .join(' ');


    // 警告を表示し，サーバーへログを送信する
    var warning_handler = function (str) {
        if (DEBUG) console.log({
            '-- warning_handler': str
        });
        if (DEBUG) show_notify({
            type: 'warning',
            text: 'WARNING : ' + str
        });
/*        $.getJSON(logger_url, {
            type: 'warn',
            msg: str
        });*/
    };


    // エラーを表示し，サーバーへログを送信する
    var error_handler = function (str) {
        if (DEBUG) console.log({
            '-- error_handler': str
        });
        if (DEBUG) show_notify({
            type: 'error',
            text: 'ERROR : ' + str
        });
/*        $.getJSON(logger_url, {
            type: 'error',
            msg: str
        });*/
    };

    // Navigator呼び出し後のコールバック関数
    var receiver_callback = function (data, status) {
        if (data.status == 'success') {
        } else {
            if (DEBUG) console.log({
                '-- data': data
            });
            error_handler(data.status);
        }
    };
       
       
    var receiver_callback_function = function(json){
       console.log(json);
    };
       
    var update_callback = function(data,status){
        $.each(data,function(i,obj) {
						//console.log(obj);
            if (obj.ChannelSwitch){
               console.log("update callback: ChannelSwitch");
            }
            else if (obj.DetailDraw){
               console.log("update callback: DetailDraw");
            }
            else if (obj.NaviDraw){
               console.log("update callback: NaviDraw");
               $('.navi-step')
               .removeClass(navigation_classes)
               .hide(0);
               
               var all_finished = true;
               $.each(obj.NaviDraw.steps, function (i, step) {
                      if (all_finished) {
                        all_finished = step.is_finished ? true : false
                      }
                      if ($('#navi-' + step.id)
                          .length) {
                          var navi = $('#navi-' + step.id);
                          $('#check-' + step.id)
                            .attr('checked', step.is_finished ? true : false);
                          if ( step.is_finished ) {
                            navi.addClass('navi-finished');
                          }
                          else {
                            navi.addClass(navigations[step.visual]);
                          }
                          if (!navi.hasClass('navi-substep')) {
                            navi.attr('data-order',i);
                            if ( step.is_open ) {
                                navi.addClass('pane-open');
                            }
                            else {
                                navi.addClass('pane-close');
                            }
                          }
                          navi.show(0);
                      } else {
                        warning_handler('missing recipe for NaviDraw : ' + step.id);
                      }
                      });
               
               var list = $('li.navi-step').not('li.navi-substep').sort(function(a,b){
                    var num_a = Number($(a).data('order'));
                    var num_b = Number($(b).data('order'));
                    if(num_a>num_b) return 1;
                    if(num_b>num_a) return -1;
                    return 0;
                    })
               
               $('.navi_area').hide(0);
               $('.navi_area').children('ul').empty();
               $.each(list,function(i,step){
                      $('.navi_area').children('ul').append(step);
                      });
/*    $('.navi_area').append($('<ul/>').append(list));*/
               $('.navi_area').show(0);
               
               
               var area_top = $('.navi_area').last().offset().top;
               if (DEBUG) console.log(area_top);
               var current = $('.navi-current');
               if (current.length) {
               var current_top = current.last().offset().top;
               if (DEBUG) console.log(current_top);
               $('.navi_area').scrollTop(current_top - area_top - 300);
               }
               
               set_navi_func_updated();
               
               if (all_finished) {
               $('#finished')
               .show(0);
               }

            }
            else if (obj.Play){
               console.log("update callback: Play");
            }
            else if (obj.Notify){
               console.log("update callback: Notify");
            }
            else if (obj.Cancel){
               console.log("update callback: Cancel");
            }
       
            });
        };

    var update_by_latest_prescription = function(){
        $.getJSON(prescription_url)
            .done(update_callback);
               };
       
    function async_sleep(time, callback){
       setTimeout(callback, time);
    }

    var send_sorcery = function(einput){
       einput_str = JSON.stringify(einput).replace(/[\n\r]/g,"");
       var url = receiver_url + "?sessionid=" + session_id + "&string=" + einput_str;
       console.log(url)
//      $.get(url).done(receiver_callback);
       $('#loading');
       $.ajax({
              url: url,
              dataType: "jsonp",
              success: function(res) {
                console.log(res);
                },
              callback: receiver_callback
              });
       new_elem ="<li><a class=\"controller\" data-einput='"+ einput_str + "'>" +url+"</a><\li>";
       $("#history ul").prepend(new_elem);
       enchant($("#history ul:first-child a"));
       
       async_sleep(300, update_by_latest_prescription);
       
    };
    var enchant = function(elem){
       $(elem).on('click', function (e) {
          e.preventDefault();
                  console.log($(this).data('einput'));
          send_sorcery($(this).data('einput'));
        });
    };
    var set_navi_func_updated = function(){
       $('.navi_area .controller')
            .on('click', function (e) {
           e.preventDefault();
           send_sorcery($(this).data('einput'));
       });
    };
       
    // 次に行くボタン
    $('.controller')
        .on('click', function (e) {
            e.preventDefault();
            console.log(JSON.stringify($(this).data('einput')));
            send_sorcery($(this).data('einput'));
    })
       
    $('a.select_controller').on('click',function(e){
         e.preventDefault();
          console.log($(this).val());
          var einput = {
            "navigator": $(this).data("navigator"),
                "action" : {
                    "name" : $(this).data("action"),
                    "target" : $(this).data("target")
                }
          };
          send_sorcery(einput);
      });
       

    $("a#jump").click(function(ev) {
        $("ul.jump-menu").dropdown("toggle");
        return false;
    });
    $("a#event").click(function(ev) {
         $("ul.event-menu").dropdown("toggle");
         return false;
     });
			 
		// Algorithmの変更
    $('#select_algorithm').change(function(){
						$('.main_controller').each(function(){
						    console.log("select_algorithm");
								$(this).hide();
						});
						var controller = $(this).attr('value');
						$("#"+controller).show();
		});
			 
			 
	  ////////////////////////////
		//// object_access_controller
		var two0num = function(num){
			 return ('0' + num).slice(-2);
		};
	  var get_timestamp = function(datetime){
			 var date = [datetime.getFullYear(), 
									 two0num(datetime.getMonth()+1),
									 two0num(datetime.getDate())].join('.');
			 var time = [two0num(datetime.getHours()),
									 two0num(datetime.getMinutes()),
									 two0num(datetime.getSeconds()),
									 ('0'+(datetime.getMilliseconds()*1000)).slice(-6)
													 ].join('.');
			 return [date,time].join('_')
		};
		$('.oa_controller').on('click',function(e){
			 e.preventDefault();
			 var tar = $(this).data('target');
			 var act = 'touch';
			 if($(this).hasClass('in_hand')){
					act = 'release';
				  $(this).removeClass('in_hand');
			 }
			 else{
					$(this).addClass('in_hand');
			 }
			 var tstamp = get_timestamp(new Date());
													 
			 console.log(tar);
			 var einput = {navigator:'object_access', action:{target:tar,name:act,timestamp:tstamp}};
			 console.log(einput);
			 send_sorcery(einput);			 
													 });
			 
  	////////////////////////////
		//// check_with_noise_controller
		$('.cwn_controller').on('click', function(e){
														
														var tar = $(this).data('target');
														var act = $(this).data('action_name');
														var einput = {navigator:'check_with_noise', action:{name:act,target:tar}};
														console.log(tar);
														console.log(act);
														console.log(einput);
														if(act!='check'){
															e.preventDefault();
															if($(this).hasClass('noise_on')){
																console.log("noise off!")
																$(this).removeClass('noise_on');
															}
															else{
																console.log("noise on!")
																$(this).addClass('noise_on');
//																einput['action']['noise'] = JSON.parse($(this).data('noise'));
															}
														}
														console.log(einput);
														send_sorcery(einput);
														});

    // 初期設定および動作
    $('.woz-run')
       .each(function () {
        var url = $(this).attr('href');
        notification_live_sec = $(this)
             .data('notification_live_sec');
        external_input_url = $(this)
             .data('external_input_url');
        check_url = $(this)
             .data('check_url');
        play_control_url = $(this)
             .data('play_control_url');
        logger_url = $(this)
             .data('logger_url');
        receiver_url = $(this)
             .data('receiver_url');
        prescription_url = $(this)
             .data('prescription_url');
        session_id = $(this)
             .data('session_id');
             
             
        $.noty.defaults = {
            layout: 'bottom',
            theme: 'defaultTheme',
            type: 'alert',
            text: '',
            dismissQueue: true,
            template: '<div class="noty_message"><span class="noty_text"></span><div class="noty_close"></div></div>',
            animation: {
                open: {
                    height: 'toggle'
                },
                close: {
                    height: 'toggle'
                },
                easing: 'swing',
                    speed: 400
                },
                timeout: notification_live_sec * seconds,
                force: false,
                modal: false,
                maxVisible: 5,
                closeWith: ['click'],
                callback: {
                    onShow: function () {},
                    afterShow: function () {},
                    onClose: function () {},
                    afterClose: function () {}
                },
                buttons: false // an array of buttons
            };
    
    });
       
       $().ready(function(){
            update_by_latest_prescription();
       });
});

/* libraries

http://twitter.github.com/bootstrap/

http://needim.github.io/noty/

*/
