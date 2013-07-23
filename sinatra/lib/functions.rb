#!/usr/bin/ruby

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'
require 'lib/startaction.rb'
require 'lib/ordersmaker.rb'

def navi_menu(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])
	# mode�ν���
	maker.modeUpdate("NAVI_MENU", jason_input["time"]["sec"], jason_input["operation_contents"])

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

	return orders
end

def external_input(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])
	# mode�ν���
	maker.modeUpdate("EXTERNAL_INPUT", jason_input["time"]["sec"], jason_input["operation_contents"])

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

	return orders
end

def channel(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])

	orders = []
	case jason_input["operation_contents"]
	when "GUIDE"
		# mode�ν���
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 0)

		# DetailDraw��modeUpdate���ʤ��Τǡ��Ƕ����ä�����������Ʊ��DetailDraw�����뤳�Ȥˤʤ롥
		orders.concat(maker.detailDraw())
		# Play��START����overview��Ф�guide�˰ܤ��硤��ǥ����κ�����ɬ�פ��⤷��ʤ���
		orders.concat(maker.play(jason_input["time"]["sec"]))
		# Notify��START����overview��Ф�guide�˰ܤ��硤��ǥ����κ�����ɬ�פ��⤷��ʤ���
		orders.concat(maker.notify(jason_input["time"]["sec"]))
		# Cancel�����ס������Ԥ�����ƥ�Ĥ�¸�ߤ��ʤ���
		# ChannelSwitch��GUIDE�����
		orders.concat(maker.channelSwitch("GUIDE"))
		# NaviDraw��ľ��ΥʥӲ��̤�Ʊ����Τ��֤����Ȥˤʤ롥
		orders.concat(maker.naviDraw())

		# ����ե�����񤭹���
		logger()
	when "MATERIALS"
		# mode�ν���
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 1)

		# DetailDraw�����ס�Detail�����褵��ʤ�
		# Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		# Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
		orders.concat(maker.cancel())
		# ChannelSwitch��MATERIALS�����
		orders.concat(maker.channelSwitch("MATERIALS"))
		# NaviDraw�����ס�Navi�����褵��ʤ�

		# ����ե������񤭹���
		logger()
	when "OVERVIEW"
		# mode�ι���
		maker.modeUpdate("CHANNEL", jason_input["time"]["sec"], 1)

		# DetailDraw�����ס�Detail�����褵��ʤ�
		# Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		# Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
		# Cancel�������Ԥ�����ƥ�Ĥ�����Х���󥻥�
		orders.concat(maker.cancel())
		# ChannelSwitch��OVERVIEW�����
		orders.concat(maker.channelSwitch("OVERVIEW"))
		# NaviDraw�����ס�Navi�����褵��ʤ�

		# ����ե������񤭹���
		logger()
	else
		# ���Ƥ�Order�����ס�����Order���֤���
		orders = [{}]
		# ����ե�����˽񤭹���
		logger()
		errorLOG()
	end
	return orders
end

def check(jason_input)
	orders = []
	maker = OrdersMaker.new(jason_input["session_id"])
	# element_name�γ�ǧ
	element_name = searchElementName(jason_input["session_id"], jason_input["operation_contents"])

	if element_name == "audio" or element_name == "video" then
		# mode�ν���
		# id��cancel��ľ�ܤ֤�����Ǥ⤤������notification������äƤ��뤫�γ�ǧ��modeUpdate����Ǥ��Τǻ����ʤ�
		maker.modeUpdate("CHECK", jason_input["time"]["sec"], jason_input["operation_contents"])

		# DetailDraw������
		# Play������
		# Notify������
		# Cancel�����ꤵ�줿id�򥭥�󥻥�
		orders.concat(maker.cancel())
		# ChannelSwitch�����ס�
		# NaviDraw������

		# ����ե������񤭹���
		logger()
	elsif element_name == "step" or element_name == "substep" then
		# mode�ν���
		maker.modeUpdate("CHECK", jason_input["time"]["sec"], jason_input["operation_contents"])

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
		# ���Ƥ�Order�����ס�����Order���֤���
		orders = [{}]

		# ����ե������񤭹���
		logger()
		errorLOG()
	end
	return orders
end

def start(jason_input)
	# Navigation��ɬ�פʥե�����ʾܺ٤ϥ��饹�ե�������ˤ����
	start_action(jason_input["session_id"], jason_input["operation_contents"])
	maker = OrdersMaker.new(jason_input["session_id"])
	# mode�ե������START�ʾ��֤�����
	maker.modeUpdate("START", jason_input["time"]["sec"])

	orders = []
	### DetailDraw�����ס�Detail�����褵��ʤ�
	### Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Cancel�����ס������Ԥ�����ƥ�Ĥ�¸�ߤ��ʤ�
	### ChannelSwitch��OVERVIEW�����
	orders.concat(maker.channelSwitch("OVERVIEW"))
	### NaviDraw�����ס�Navi�����褵��ʤ�

	# ����ե�����˽񤭹���
	logger()
	return orders
end

def finish(jason_input)
	maker = OrdersMaker.new(jason_input["session_id"])

	# media��STOP�ˤ���
	maker.modeUpdate("END", jason_input["time"]["sec"])

	orders = []
	### DetailDraw�����ס�Detail�����褵��ʤ�
	### Play�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Notify�����ס���������ƥ�Ĥ�¸�ߤ��ʤ�
	### Cancel�������Ԥ�����ƥ�Ĥ�¸�ߤ���Х���󥻥�
	orders.concat(maker.cancel())
	### ChannelSwitch������
	### NaviDraw�����ס�Navi�����褵��ʤ�

	# ����ե�����˽񤭹���
	logger()
	return orders
end
