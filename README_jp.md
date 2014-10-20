#Markdown Live Editor#
#CHIFFON Navigator 内部仕様書#

## 外部ライブラリ ##
CHIFFON Navigatorが利用している外部ライブラリは以下の二つ

 - Sinatra : http://www.sinatrarb.com/intro-ja.html
 - Nokogiri : http://www.engineyard.co.jp/blog/2012/getting-started-with-nokogiri/

##ディレクトリ構成##
(*)がついているディレクトリはユーザが自分で作成する必要がある．

ファイル

 - app.rb => ruby app.rbによりRackサーバで起動できる．a
 - config.yml => プログラムの設定値が書かれたファイル

ディレクトリ

 - lib => プログラムの本体が入っている
 - lib/Navi.rb => メインアプリケーション
 - lib/Navi => ナビゲーションのベースとなるヘルパー(Base.rb)と，ガイド戦略のアルゴリズムモジュール(Default.rb他，追加されたモジュール)がある．
 - lib/Helpers => 各種ヘルパーが定義されている
 - lib/Recipe => 調理進行状況を記述・管理するためのクラスの定義
 - records(*) => セッション毎の情報(通常のログを含む)を保存する
 - log(*) => エラーログ
 - public => デバッグ用ツールが入っていたが，wget を使ってデバグした方が良いので不要

## インストール ##
chiffon-navigatorのルートディレクトリにおいて下記コマンドを実行

1. sudo gem install bundler
- bundler install

## 使い方(ruby app.rbで起動した場合) ##
###セッションIDを取得したい場合 ###
% wget -O - -q "http://localhost:4567/session_id/:username

 - :username にはログインに使用したユーザの名前を入れる
 - wgetのオプションの意味はGoogle等で調べること．
 - 上記URLをWeb ブラウザのアドレスバーへ入力しても良い．

### CHIFFON Viewer との通信をシミュレートする場合
% wget -O - "http://localhost:4567/navi/:algorithm" --post-data="${string}"

 - :algorithm の部分には"default"または独自拡張アルゴリズムの名前を入れる(独自拡張アルゴリズムの作り方は後述)
 - ${string}の部分にはJSON形式のデータが入る．ここにViewerからポストされるデータを模したものを入れることでシミュレートができる．
 - 例: ${string} = "{\"session_id\"=\"test_session\",\"situation\"=\"start\",\"operation_contents\"=\"`cat test_recipe2.xml`\"}"
 - situation, operation_contentsに入りうる値の詳細はviewerの最終仕様書を参照のこと

### 独自拡張アルゴリズムの作り方 ###
 - 基本的な処理の流れはlib/Navi.rb及びlib/Navi/Base.rbに従うこと．
 - 独自拡張はrecommend, calc_likelihood, proc_external_input という三つの関数を持つ別モジュールを作ることにより実現する．
 - 上記のそれぞれの関数の引数はNavi::Default モジュールと同じにすること．
 - Navi.rb の ## ... ## という形式で書かれたコメントの指示に従い，作成したモジュールを /navi/:algorithm という形式で呼び出せるようにする．

## Author ##
 - Jin Inoue
 - Atsushi HASHIMOTO (Responsible)
  - ahasimoto@mm.media.kyoto-u.ac.jp