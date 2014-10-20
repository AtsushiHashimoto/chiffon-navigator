;(function($) {

	$.noty.layouts.bottom = {
		name: 'bottom',
		options: {},
		container: {
			object: '<ul id="noty_bottom_layout_container" />',
			selector: 'ul#noty_bottom_layout_container',
			style: function() {
				$(this).css({
					top: '400px',
					left: '5%',
					position: 'absolute',
					width: '90%',
					height: 'auto',
					margin: 0,
					listStyleType: 'none',
					zIndex: 9999999,
					borderRadius: '0px 0px 0px 0px'
				});
			}
		},
		parent: {
			object: '<li />',
			selector: 'li',
			css: {}
		},
		css: {
			display: 'none',
			background: "url('/images/noty_bk.png') repeat-x scroll left top",
			border: 'none',
			padding: '30px',
			fontSize:'20px',
			borderRadius: '0px 0px 0px 0px'
		},
		addClass: ''
	};

})(jQuery);