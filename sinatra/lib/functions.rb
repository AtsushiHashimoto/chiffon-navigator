#!/usr/bin/ruby

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'
require 'lib/startaction.rb'
require 'lib/ordersmaker.rb'
require 'lib/finishaction.rb'

def navi_menu(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])
		# mode�ν���
		result = maker.modeUpdate_navimenu(jason_input["time"]["sec"], jason_input["operation_contents"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		orders = []
		# DetailDraw�����Ϥ��줿step��CURRENT�Ȥ�����
		orders.concat(maker.detailDraw())
		# Play�����ס�����å����줿step��Ĵ����ư��Ϥ��С�EXTERNAL_INPUT�Ǻ��������
		# Notify�����ס�����å����줿step��Ĵ����ư��Ϥ��С�EXTERNAL_INPUT�Ǻ��������
		# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
		orders.concat(maker.cancel())
		# ChannelSwitch������
		# NaviDraw��Ŭ�ڤ�visual��񤭴�������Τ���
		orders.concat(maker.naviDraw())

		# ����ե������񤭹���
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def external_input(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])
		# mode�ν���
		result = maker.modeUpdate_externalinput(jason_input["time"]["sec"], jason_input["operation_contents"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		orders = []
		# DetailDraw��Ĵ���Ԥ��Ȥä���Τ˹�碌��substep��id����
		orders.concat(maker.detailDraw)
		# Play��substep��˥���ƥ�Ĥ�¸�ߤ���к���̿�������
		orders.concat(maker.play(jason_input["time"]["sec"]))
		# Notify��substep��˥���ƥ�Ĥ�¸�ߤ���к���̿�������
		orders.concat(maker.notify(jason_input["time"]["sec"]))
		# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
		orders.concat(maker.cancel())
		# ChannelSwitch������
		# NaviDraw��Ŭ�ڤ�visual��񤭴�������Τ���
		orders.concat(maker.naviDraw())

		# ����ե������񤭹���
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def channel(jason_input)
	begin
		maker = OrdersMaker.new(jason_input["session_id"])

		orders = []
		case jason_input["operation_contents"]
		when "GUIDE"
			# mode�ν���
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "GUIDE")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw��modeUpdate���ʤ��Τǡ��Ƕ����ä�����������Ʊ��DetailDraw�����뤳�Ȥˤʤ롥
			orders.concat(maker.detailDraw())
			# Play��START����overview��Ф�guide�˰ܤ��硤��ǥ����κ�����ɬ�פ��⤷��ʤ���
			orders.concat(maker.play(jason_input["time"]["sec"]))
			# Notify��START����overview��Ф�guide�˰ܤ��硤��ǥ����κ�����ɬ�פ��⤷��ʤ���
			orders.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel�����ס������Ԥ�����ƥ�Ĥ�¸�ߤ��ʤ���
			# ChannelSwitch��GUIDE�����
			orders.push({"ChannelSwitch"=>{"channel"=>"GUIDE"}})
			# NaviDraw��ľ��ΥʥӲ��̤�Ʊ����Τ��֤����Ȥˤʤ롥
			orders.concat(maker.naviDraw())

			# ����ե�����񤭹���
			logger()
		when "MATERIALS"
			# mode�ν���
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "MATERIALS")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw�����ס�Detail�����褵��ʤ�
			# Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
			# Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
			# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
			orders.concat(maker.cancel())
			# ChannelSwitch��MATERIALS�����
			orders.push({"ChannelSwitch"=>{"channel"=>"MATERIALS"}})
			# NaviDraw�����ס�Navi�����褵��ʤ�

			# ����ե������񤭹���
			logger()
		when "OVERVIEW"
			# mode�ι���
			result = maker.modeUpdate_channel(jason_input["time"]["sec"], "OVERVIEW")
			if result == "internal_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw�����ס�Detail�����褵��ʤ�
			# Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
			# Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
			# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
			orders.concat(maker.cancel())
			# ChannelSwitch��OVERVIEW�����
			orders.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
			# NaviDraw�����ס�Navi�����褵��ʤ�

			# ����ե������񤭹���
			logger()
		else
			# ����ե�����˽񤭹���
			logger()
			errorLOG()
			return {"status"=>"invalid params"}
		end
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def check(jason_input)
	begin
		orders = []
		maker = OrdersMaker.new(jason_input["session_id"])
		# element_name�γ�ǧ
		element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"])

		if element_name == "step" || element_name == "substep"
			# mode�ν���
			result = maker.modeUpdate_check(jason_input["time"]["sec"], jason_input["operation_contents"])
			if result == "interlan_error"
				return {"status"=>"internal error"}
			elsif result == "invalid_params"
				return {"status"=>"invalid params"}
			end

			# DetailDraw��
			orders.concat(maker.detailDraw())
			# Play�����ס������å��������������礭�ʲ������ܤǤϤʤ�
			orders.concat(maker.play(jason_input["time"]["sec"]))
			# Notify�����ס������å��������������礭�ʲ������ܤǤϤʤ����ס�
			orders.concat(maker.notify(jason_input["time"]["sec"]))
			# Cancel��CURRENT��substep������å����줿��硤��ǥ�����λ����ɬ�פ����롥
			orders.concat(maker.cancel())
			# ChannelSwitch�����ס�
			# NaviDraw�������å����줿��Τ�is_fisnished�˽��ؤ���visual��Ŭ�ڤ˽񤭴�������Τ���
			orders.concat(maker.naviDraw())

			# ����ե������񤭹���
			logger()
		else
			# ����ե������񤭹���
			logger()
			errorLOG()
			return {"status"=>"invalid params"}
		end
	rescue => e
		 p e
		 return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def start(jason_input)
	# Navigation��ɬ�פʥե�����ʾܺ٤ϥ��饹�ե�������ˤ����
	# modeUpdate�⤳�δؿ��Ǥ�äƤ��ޤ�
	result = start_action(jason_input["session_id"], jason_input["operation_contents"])
	if result == "internal_error"
		return {"status"=>"internal error"}
	elsif result == "invalid_params"
		return {"status"=>"invalid params"}
	end

	orders = []
	### DetailDraw�����ס�Detail�����褵��ʤ�
	### Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Cancel�����ס������Ԥ�����ƥ�Ĥ�¸�ߤ��ʤ�
	### ChannelSwitch��OVERVIEW�����
	orders.push({"ChannelSwitch"=>{"channel"=>"OVERVIEW"}})
	### NaviDraw�����ס�Navi�����褵��ʤ�

	# ����ե�����˽񤭹���
	logger()
	return {"status"=>"success","body"=>orders}
end

def finish(jason_input)
	begin
		# media��STOP�ˤ��롥
		hash_mode, result = finish_action(jason_input["session_id"])
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end

		doc = REXML::Document.new(open("records/#{jason_input["session_id"]}/#{jason_input["session_id"]}_recipe.xml"))

		### DetailDraw�����ס�Detail�����褵��ʤ�
		### Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		### Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		### Cancel�������Ԥ�����ƥ�Ĥ�¸�ߤ���Х���󥻥�
		orders, result = cancel(jason_input["session_id"], doc, hash_mode)
		if result == "internal_error"
			return {"status"=>"internal error"}
		elsif result == "invalid_params"
			return {"status"=>"invalid params"}
		end
		### ChannelSwitch������
		### NaviDraw�����ס�Navi�����褵��ʤ�

		# ����ե�����˽񤭹���
		logger()
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end

def play_control(jason_input)
	begin
		element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"]["id"])
		if element_name == "audio" || element_name == "video"
			case jason_input["operation_contents"]["operation"]
			when "PLAY"
			when "PAUSE"
			when "JUMP"
			when "TO_THE_END"
			when "FULL_SCREEN"
			when "MUTE"
			when "VOLUME"
			else
				return {"status"=>"invalid params"}
			end
		else
			return {"status"=>"invalid params"}
		end

		orders = []
		### DetailDraw�����ס�Detail�����褵��ʤ�
		### Play��
		### Notify��
		### Cancel��
		### ChannelSwitch������
		### NaviDraw�����ס�Navi�����褵��ʤ�
	rescue => e
		p e
		return {"status"=>"internal error"}
	end

	return {"status"=>"success","body"=>orders}
end
