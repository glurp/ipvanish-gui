#!/usr/bin/ruby
# encoding: utf-8
#
# License: LGPL V2.1
#
#######################################################################
#   ipvanish.rb : GUI for manage VPN connection to IPVanish networkon Linux
#  Usage:
#    > sudo apt-get install openvpn
#     <<< install ruby 1.9.3 minimum >>>
#    > sudo gem install pty expect rubyzip
#    > sudo gem install Ruiby
#    > mkdir ipvanish; ce ipvanish
#    > wget wget http://www.ipvanish.com/software/configs
#    > cd ...
#    >
#    > sudo ruby ipvanish.rb &
#######################################################################

##################### Check machine envirronent #############" 
if `which openvpn`.size==0
   puts "Please, install 'openvpn' : > sudo apt-get install openvpn"
   exit
end
if !Dir.exists?("/etc") && !Dir.exists?("/user")
   puts "Please, run me on i Unix/Bsd/Linux machine...."
   exit
end
(puts "Must be root/sudo ! ";exit(1)) unless Process.uid==0 

################## Load ruby gem dependancy #################
def trequire(pack) 
   require pack
rescue Exception  => e
   puts "Please, install '#{pack}' : > sudo gem install #{pack}"
   exit
end

trequire 'open-uri'
trequire 'open3'
trequire 'Ruiby'
trequire 'pty'
trequire 'pp'
trequire 'expect'
trequire 'zip'
require_relative 'ip_speed_test.rb'

################################ Global state ##################

$provider={}
$current=""
$connected=false
$openvpn_pid=0
$thtail=nil
$style_ok= <<EOF
* { background-image:  -gtk-gradient(linear, left top, left bottom,  from(#066), to(#ACC));
    color: #FFFFFF;
}
GtkEntry,GtkTreeView { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFE), to(#EED));
    color: #000;
}
GtkButton, GtkButton > GtkLabel { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFE), to(#FFA));
    color: #000;
}
EOF
$style_nok= <<EOF
* { background-image:  -gtk-gradient(linear, left top, left bottom,  from(#966), to(#FCC));
    color: #FFFFFF;
}
GtkEntry,GtkTreeView { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFA), to(#EE6));
    color: #000;
}
GtkButton, GtkButton > GtkLabel { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFC), to(#EEB));
    color: #000;
}
EOF



$auth=""
if $auth.size>0 
  puts "*************** Auth in code !!!! Do not commit !!! ************************"
end
if File.exists?("ipvanish.cred")  
  $auth=File.read("ipvanish.cred")
end 

############################# Tools ##############################

def proc_presence?(name)   `pgrep -lf #{name}`.split("\n").size>0 end
def presence_openvpn?()   proc_presence?("openvpn") end

def check_system(with_connection)
  return unless with_connection
  data=open("http://geoip.hidemyass.com").read.chomp
  if (data=~ /<table>(.*?)<\/table>/m)
    props=$1.gsub(/\s+/,"").
            split(/<\/*tr>/).select {|s| s && s.size>0}.
            each_with_object({}) { |r,h| 
              k,v=r.split("</td><td>").map {|c| ;c.gsub(/<.*?>/,"")}
              h[k]=v if k && v
            }
     contents=props.map {|kv| '%-10s : %10s' % kv }.join("\n")
    alert("Your connection is :\n #{contents}" )
  else
  end
end

def get_list_server()
  gui_invoke { @lprovider.clear ; @lprovider.add_item("get server list...") }
  begin
    gui_invoke { @lprovider.add_item("download ovpn & crt files...") }
    Dir.mkdir("ipvanish") unless Dir.exists?("ipvanish")
    zipfn="ipvanish/a.zip"
    File.open(zipfn,"wb") { |f| 
      data=open("http://www.ipvanish.com/software/configs/configs.zip").read
      p data.size,data.encoding
      f.write(data)
    }
    lfn= []
    flog="/tmp/openvpn_ipvanish.log"
    Zip::File.open(zipfn) do |zip_file|
      zip_file.each do |entry|
        puts "  Extracting #{entry.name}..."
        fn="ipvanish/#{entry.name}"
        File.delete(fn) if File.exists?(fn)
        entry.extract(fn)
        File.write(fn,File.read(fn)+ "\nlog-append #{flog}\n") 
        lfn << entry.name if entry.name =~ /.ovpn$/
        if entry.name =~ /^ca.*.crt$/
          File.delete(entry.name) if File.exists?(entry.name)
          entry.extract(entry.name) 
        end
      end
    end
    puts "loading list server (#{lfn.size})..."
    gui_invoke { @lprovider.add_item("loading list server (#{lfn.size})...") }
    provider={}
    lfn.sort.each { |name|
      _,country,town,abrev,srv=*name.split(/[\-\.]/)[0..-2]
      p  [country,town,srv,name]
      key="%s %-15s"%[country,town]
      provider[key]||={}
      provider[key][srv]=name
    }
    $provider=provider.each_with_object({}) {|(k,v),h| h["%10s (%d)" % [k,v.size]] = v if v.size>1}

    gui_invoke {
      @lprovider.clear
      $provider.keys.each_with_index { |item,i| @lprovider.add_item(item) ; update if i%10==1}
    }
  rescue Exception => e
      gui_invoke { error(e)}
  end
end

def choose_provider(item)
  sel=nil
  if $provider[item].size>1
    ok=dialog("Server selection") {
          labeli("Selection of server on #{item}")
          l=list("Server",100,200) {|isels,csels|  sel=csels.first}
          l.set_data($provider[item].keys)
    }
    return unless ok
  else
    return unless ask("Ok for connection on #{item} ?")
    sel=$provider[item].keys.first
  end
  $current="ipvanish/#{$provider[item][sel]}"

  sel="udp"
  ok=dialog("Protocol selection") {
      labeli("Selection of internet protocol")
      l=list("Protocol",100,200) {|isels,csels|  sel=csels.first}
      l.set_data(%w{udp tcp})
  }
  File.write($current,File.read($current).sub(/proto\s+\w+/,"proto #{sel}")) if ok

  if $auth==""
      user,pass="",""
      loop {
        prompt("Vpn User Name ?") {|p| user=p }.run  
        return if user.size==0
        prompt("Vpn Passwd ?") {|p| pass=p }.run
        break if user.size>2 && pass.size>2
        error("Error, redone...")
      }
      $auth=user+"////"+pass; user="";pass=""
      File.write("ipvanish.cred",$auth) 
  end

  if  $connected
    if ask("Kill current active vpn ?")
      disconnect
    else
      return
    end
  end
  Thread.new { connect }
end

def connect
  log "connect: to #{$current}"
  return unless $current.size>0
  ovpn=$current
  log "run openvpn..."
  flog="/tmp/openvpn_ipvanish.log"
  openvpn($current,ovpn,flog)
 end

 def openvpn(name,cfg,flog)
  openvpn = "openvpn --script-security 3 --verb 4 --config #{cfg} 2>&1"
  rusername = %r[Enter Auth Username:]i
  rpassword = %r[Enter Auth Password:]i
  rcompleted= %r[Initialization\s*Sequence\s*Completed]i
  rfail     = %r[AUTH_FAILED]i
  log "spawn > #{openvpn} ..." 
  th=tailmf(flog,rcompleted,rfail)
  PTY.spawn(openvpn) do |read,write,pid|
    begin
      $openvpn_pid=pid
      th0=nil
      read.expect(rusername) { log "set user..."    ; write.puts $auth.split("////")[0] }
      read.expect(rpassword) { log "set passwd..."  ; write.puts $auth.split("////")[1] }
      read.expect(rcompleted) {
        log "OK !!!!"
        gui_invoke {
         status_connection(true)
         @ltitle.text=name
        } 
      }
      read.each { |o| log "log:    "+o.chomp }
    rescue Exception => e
      gui_invoke { status_connection(false) }
      Process.kill("KILL",pid)
      log "openvpn Exception #{e} #{"  "+e.backtrace.join("\n  ")}"
    ensure
      th.kill rescue nil
    end
  end 
  $openvpn_pid=0
  gui_invoke { status_connection(false) }
end

def disconnect
  system("killall","openvpn")  
  gui_invoke { status_connection(false) }
  $openvpn_pid=0
end

def reconnect()
 if $current.size>0 && $provider[$current] && $auth.size>0 && $auth.split("////").size==2
   Thread.new() {  
     disconnect()
     log "sleep 4 seconds..."
     sleep 4
     log "reconnect..."
     connect()
   }
 else
   alert("Not connected !!!")
 end
end

def speed_test()
  alabel=[]
  dialog_async("Speed test",{:response=> proc {|dia| $sth.kill if $sth; true }}) {
     stack(bg:"#FFF") {
       3.times { |i| alabel << entry("",bg:"#FFF",fg:"#000") }
     }
  }
  alabel[0].text="Connecting..."
  $sth=ip_speed_test(4) { |qt,delta,speed| 
    alabel[0].text="download ..."
    if delta>0
      alabel[1].text="downlolad test..."
      alabel[2].text="Speed : #{speed.round(2)} KB/s"
    else
      alabel[0].text="End test"
      alabel[1].text="Data received: #{qt} MB"
      alabel[2].text="Global Speed : #{speed.round(2)} KB/s"
    end
  }
end

at_exit { disconnect if $openvpn_pid>0 }

###########################################################################
#               M A I N    W I N D O W
###########################################################################

Ruiby.app width: 500,height: 400,title: "IPVanish VPN Connection" do
  rposition(1,1)
  def status_connection(state)
    $connected=state
    def_style state ? $style_ok : $style_nok 
    @ltitle.text= state ? $current : "VPN Connection Manager"
    clear_append_to(@status) { label(state ? "#YES" : "#DIALOG_ERROR") } 
  end
  ############### HMI ###############
  flow do
     stacki do
       buttoni("Check vpn") { check_system(true) }
       buttoni("Refresh list") { Thread.new { get_list_server() } }
       buttoni("Disconnect...") { Thread.new { disconnect() } }
       buttoni("Change IP...") { reconnect() }
       buttoni("Speed Test...") { speed_test() }
       buttoni("Forget name&pass") { $auth=""; File.delete("ipvanish.cred") }
       bourrage
       buttoni("Exit") { ruiby_exit()  }
     end
     separator
     stack do
       flowi do
          @ltitle=label("VPN Connection Manager",{
            font: "Arial bold 16",bg: "#004455", fg: "#AAAAAA"
          })
           @status=stacki { labeli("#DIALOG_ERROR") }
           $connected=false
       end
       separator
       stack do
         @lprovider=list("Providers:",200,200) { |item| 
            @pvc.text=@lprovider.get_data[item.first] rescue nil
         }
         @lprovider.add_item("Loading...")
         flowi { 
           @pvc=entry("...",width:200)
           button("Connect...") { choose_provider(@pvc.text) if @pvc.text.size>3 }
         }
       end
     end
  end
  ############### initial traitments
  after(50) do
    Thread.new {
       begin
         puts "get public ip..."
         $original_ip=open("http://geoip.hidemyass.com/ip").read.chomp
         puts "public is ip=#{$original_ip}"
       rescue 
         $original_ip=""
         gui_invoke {error("Internet seem unreachable !") }
       end
      check_system(false) rescue nil
      get_list_server
    }
  end  
  set_icon "ipvanish.png" 
  ############### icon animation
  anim(1000) {
    set_icon($openvpn_pid==0 ? ( (Time.now.to_i%2==0)? "ipvanish_down.png" : "ipvanish_down.png" ) : "ipvanish.png" )
  }
end
