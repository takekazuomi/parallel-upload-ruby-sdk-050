Parallel Upload for Ruby SDK 0.5.0 Example
============================
Ruby sdk を使ったAzure Blobへのアップロード

ruby sdk 0.5.0は、現状では非常に素朴な実装でREST APIの薄いラッパーでし
かありません。このコードでは、ruby sdk のコードを元にblock blobの
parallel uploadを実装しています。

# 概要
Azure Blobでは並列アップロードを使うとスループットが上がることが知られ
ています。このプログラムでは、ファイルを4M blockで分割してblock blobへ
uploadして、逐次と並列で速度を比べています。
このコードでは、並列無しでput blob して最後にcommitと、
[Prallal](https://github.com/grosser/parallel) を使ってパラレルアップロー
ドして最後にcommitの両方を実装しています。
Rubyの特性上、linuxでは、forkベースの並列処理の方が効率が良いという話も
あり、確認のためprocess(fork)ベースとthreadベースの２つのパターンで走ら
せて比較しています。（確かに、forkの方が良さそう）
並列無しと有りで比較すると倍ほど速度が違い、processとthreadで比較する
と、速度はあまり変らず、CPUの負荷がforkベースの方が低い結果になった。

Linux環境は、Ubuntu 12.04 on Windows Azure のLarge Instanceを使っていま
す。

以降で、インストール、データファイルの準備、実行の順で説明する。

# インストールと実行

必要なgemをインストールします

```
$ bundle install --path vendor/bundler
Fetching gem metadata from https://rubygems.org/..........
Fetching gem metadata from https://rubygems.org/..
Resolving dependencies...
Installing json (1.7.7) with native extensions
Installing mime-types (1.23)
Installing nokogiri (1.5.9) with native extensions
Installing systemu (2.5.2)
Installing macaddr (1.6.1)
Installing uuid (2.3.7)
Installing azure (0.5.0)
Installing parallel (0.6.4)
Using bundler (1.2.5)
Your bundle is complete! It was installed into ./vendor/bundler
 
```

* MEMO
エラーに成らなければ、そのまま次へ。参考までに、遭遇したエラーを後ろの
方に書いて置きます。

# アップロード元のテストデータの作成
azure ubuntu vm環境では、テンポラリディスクにデータを作成します。
/dev/sdb1 が、 /mnt/resource type ext4 (rw)になっているので、ここにデー
タファイルを作ります。
XXXXのところは、ログインしているユーザー名で入れ替えてください。
```
sudo makedir -p /mnt/resource/tmp/data
sudo chdown -R XXXX:XXXX /mnt/resource/tmp
ln -s /mnt/resource/tmp/data data
ls -l
... snip ...
lrwxrwxrwx 1 XXXX XXXX   22 May 13 09:32 data -> /mnt/resource/tmp/data
... snip ...
```

ここまで出来たら、下記のRubyのスクリプトでデータファイルを作成します。
（Windows環境では、ddはDevKitのものを使います）createdata.rbの後の数字
は、生成するファイルサイズ（MByte)です。

ちょっと脱線しますが、テンポラリディスクの性能を見るために何パターンで
ddを走らせています。

Largeで試したところ、下記のようになりました。
1.9 GB/sが、/dev/zero -> /dev/nullへの書込み速度
339 M/Bが、/dev/zero -> data/file.datへの書込み速度
10.3 MBが、/dev/urandom -> /dev/nullへの書込み速度
9.2 M/Bが、/dev/urandom -> data/file.datへの書込み速度

/dev/zero -> data/file.datはSSD並の速度ですが、データファイルの作成速度
は、/dev/urandomが律速らしくあまり速くありません。


```
$ ruby .\createdata.rb 1024
1048576+0 records in
1048576+0 records out
1073741824 bytes (1.1 GB) copied, 0.569654 s, 1.9 GB/s
1048576+0 records in
1048576+0 records out
1073741824 bytes (1.1 GB) copied, 3.1632 s, 339 MB/s
1048576+0 records in
1048576+0 records out
1073741824 bytes (1.1 GB) copied, 104.509 s, 10.3 MB/s
1048576+0 records in
1048576+0 records out
1073741824 bytes (1.1 GB) copied, 116.121 s, 9.2 MB/s
```

ちなみに、読み込みは下記のようになりました。SATA3、SSDだとしてもちょっ
と速すぎな気がするのでキャッシュが効いているのかもしれません。

```
$ dd if=data/file.dat of=/dev/null
2097152+0 records in
2097152+0 records out
1073741824 bytes (1.1 GB) copied, 1.43132 s, 750 MB/s
```

# 実行
blobupload.rbの中のStorage Accountの部分を書き換えます。

```
Azure.configure do |config|
  config.storage_account_name = "<ACCONT NAME>"
  config.storage_access_key   = "<ACCESS KEY>"
end
```

下記のように実行します

```
$ bundle exec ruby blobup.rb
                                          user     system      total        real
parallel(process) put blob: 1         3.120000   1.050000  15.270000 ( 69.585965)
parallel(process) put blob: 2         3.160000   1.120000  14.190000 ( 39.677753)
parallel(process) put blob: 4         2.940000   1.250000  14.590000 ( 31.273716)
parallel(process) put blob: 8         3.030000   1.390000  16.460000 ( 29.900934)
parallel(process) put blob: 16        2.930000   1.590000  17.360000 ( 29.784424)
parallel(process) put blob: 32        3.060000   1.990000  19.060000 ( 38.103178)
parallel(process) put blob: 64        2.920000   2.900000  22.220000 ( 37.490831)

parallel(thread) put blob: 1         10.060000   5.750000  15.810000 ( 69.415202)
parallel(thread) put blob: 2          9.640000   4.470000  14.110000 ( 37.975378)
parallel(thread) put blob: 4         10.270000   6.520000  16.790000 ( 32.898025)
parallel(thread) put blob: 8          9.970000   8.440000  18.410000 ( 30.511209)
parallel(thread) put blob: 16        10.740000  12.400000  23.140000 ( 31.029340)
parallel(thread) put blob: 32        11.380000  16.340000  27.720000 ( 34.744499)
parallel(thread) put blob: 64        11.780000  19.210000  30.990000 ( 39.652134)

simple block blob upload:             6.900000   3.340000  10.240000 ( 65.904059)

```

# 考察
parallel(process)が、processベース、parallel(thread)がthreadベース。
simple blockと書いてあるのが逐次版です。

ざっくりとした結果しか出ていませんが、processと、threadを比較すると
user/system timeどちらもthreadが大きくCPU負荷が高いのがわかります。
realが掛かった時間で、CPU+I/O待ちの時間になります。並列度１以外は、おお
よそ、I/O待ちにかかっている時間は同じです。

全体の傾向を見ると、8並列ぐらいが一番速くなっているようです。L(Core 4)
で実行しているので、もう少し並列度を上げた時がピークでも良さそうな気も
しますが、妥当な結果だと思います。

この結果から総論すると、」速度は1GByteを30秒で270 Mbps程度。並列度は4で
十分2でも210Mbpsは出る。processをforkした方がCPU負荷が低い」と言えます。

また、プログラムの作りでは、並列無しものは4MB Block読むためバッファを一つ
用意して使いまわしていますが、並列版は4MBをバッファに読んで、process /
threadに渡すというのを繰り返しています。その結果、4MBをバッファは毎回作
成されてGCで回収されるという動きになり、並列版じゃない方（逐次版）の方
がGCへの負荷が少なく省メモリで動くようになっています。

CPUへの負荷の話は、Ruby依存の問題ですが、メモリの話はバッファーをPoolし
て使いまわすような仕組みを入れれば改善できると思います。


# エラー等
## Could not verify the SSL certificate for ...
手元のWindows 環境では、gemのレポジトリへのhttpsアクセスで証明書のエラー
になりました。ルート証明書見つからないからのようです。いろいろな回避方
法があるようですが、今回は、cygwin環境にインストールされていた証明書を
使うように環境変数を設定しました。

エラーの内容

```
$ bundle install --path vendor/bundler
Fetching source index from https://rubygems.org/
Resolving dependencies...
Could not verify the SSL certificate for https://rubygems.org/.
There is a chance you are experiencing a man-in-the-middle attack, but most
likely your system doesn't have the CA certificates needed for verification. For
information about OpenSSL certificates, see bit.ly/ruby-ssl. To connect without
using SSL, edit your Gemfile sources and change 'https' to 'http'.
```

この辺りの話は、エラーメッセージの中のリンクに詳細が書いてあります。

https://gist.github.com/fnichol/867550

今回はこれで回避

```
$Env:SSL_CERT_FILE="C:\cygwin\usr\ssl\certs\ca-bundle.crt"
```

## Ubuntu 12.04 
初期状態だとパッケージが足りないので追加インストールしてください

```
apt-get install make install libxslt1-dev libxml2-dev
```

この辺りが参考になります。[Installing Nokogiri](http://nokogiri.org/tutorials/installing_nokogiri.html)


## ruby sdk の注意
ruby sdkでは、今のところRuby 1.9.3か、2.0.0で、でWindowsの場合は32bit版
のみをサポートしています。Web Platform Installerで入れると、
RubyInstallerの2.0.0-p0 32bit版がインストールされるので、DevKitは相当の
物（Ruby 2.0.0: mingw64-32-4.7.2 ）を入れなけれないけません。

http://rubyinstaller.org/downloads/

## fiddlerを使う
また脱線しますが、Windowsだとfiddlerが使えると便利です。

環境変数、HTTP_PROXYにfiddlerのproxyを設定すると使えようになります。
fiddlerのtool/fiddler options/Connectionsを見ると、待ち受けポートの番号
がわかります。例えば、8889なら下記のように設定する。(powershell用)

```
$Env:HTTP_PROXY="http://localhost:8889"
```
ソース上だと下記のURLの当たりで処理しています。

https://github.com/WindowsAzure/azure-sdk-for-ruby/blob/release-0.5.0/lib/azure/core/http/http_request.rb#L132


# 最後に
Rubyを使うことの素晴らしい点は、WindowsでもLinuxからでも同じコードで
Azure Blobにアクセスすることができることです。
このコードを書いている途中でもコードのプラットフォーム依存性は低く、問
題になったのは Parallel の:in_processが、Windows環境ではサポートされて
いないことぐらいでした。実に素晴らしい。

パフォーマンスだけを比較すると、以前C#のSDKを使って同様な速度測定したも
のと比べて半分ぐらいの速度しか出ていないので注意が必要です。
この速度が何に起因するのかはわかりませんが、スケーラビリティを計算する
時の参考にしてください。

もう少し、コードをチューニングすれば効率が上がるかもしれないという気が
したので、同時に2つベンチマークを流してみました。これで、速度が上がると
すると、parallelに渡すところが律速になっている可能性がある。と思ったが
結果は芳しくなかった残念。

ちなみに、
[Windows Azureのフラット ネットワーク ストレージと2012年版スケーラビリティ ターゲット](http://satonaoki.wordpress.com/2012/11/03/windows-azure%E3%81%AE%E3%83%95%E3%83%A9%E3%83%83%E3%83%88-%E3%83%8D%E3%83%83%E3%83%88%E3%83%AF%E3%83%BC%E3%82%AF-%E3%82%B9%E3%83%88%E3%83%AC%E3%83%BC%E3%82%B8%E3%81%A82012%E5%B9%B4%E7%89%88%E3%82%B9/)
によると、単一Blobだと、480Mbps、ストレージアカウント全体で受信10Gbpsが
スケーラビリティターゲットということでもあり、C# SDK並の2倍のスループッ
トは出ても良いはず。

参考
[Windows Azure Storage 2.0 の Blob Upload](http://kyrt.in/blog/2012/12/08/blobasyncinside/)
