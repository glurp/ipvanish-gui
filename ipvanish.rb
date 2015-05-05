#!/usr/bin/ruby
# encoding: utf-8
#
# License: LGPL V2.1
#
#######################################################################
#   ipvanish.rb : GUI for manage VPN connection to IPVanish networkon Linux
#  Usage:
#    > sudo apt-get install openvpn
#     <<< install ruby 2.0 minimum >>>
#    > sudo gem install pty expect rubyzip
#    > sudo gem install Ruiby
#    > git clone https://github.com/glurp/ipvanish-gui
#    > cd ipvanish-gui
#    >
#    > sudo ruby ipvanish.rb &
#######################################################################

##################### Check machine environement #############" 
if `which openvpn`.size==0
   puts "Please, install 'openvpn' : > sudo apt-get install openvpn"
   exit
end
if !Dir.exists?("/etc") && !Dir.exists?("/user")
   puts "Please, run me on i Unix/Bsd/Linux machine...."
   exit
end
(puts "Must be root/sudo ! ";exit(1)) unless Process.uid==0 

################## Load ruby gem dependency #################
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

GtkEntry,GtkTreeView,GtkTreeView GtkLabel { 
   background-image:  -gtk-gradient(linear, left top, left bottom, from(#FFB), to(#EED));
    color: #000;
}
GtkTreeView row:selected  {
  background-image: none;
  background-color: #AA7;
  color: #000;
}

GtkButton, GtkButton > GtkLabel { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFE), to(#FFA));
    color: #000;
}
GtkButton:active { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FF0), to(#FF3));
}

EOF
$style_nok= <<EOF
* { background-image:  -gtk-gradient(linear, left top, left bottom,  from(#966), to(#FCC));
    color: #FFFFFF;
}
GtkEntry,GtkTreeView,GtkTreeView GtkLabel  { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFA), to(#EE6));
    color: #000;
}
GtkTreeView row:selected  {
  background-image: none;
  background-color: #500;
  color: #FF0;
}

GtkButton, GtkButton > GtkLabel { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#FFC), to(#EEB));
    color: #000;
}
GtkButton:active { background-image:  -gtk-gradient(linear, left top, left bottom,  
      from(#EEB), to(#EE0));
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
  begin
    gui_invoke { @treeview.set_data([%w{. download... . .}])}
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
        #puts "  Extracting #{entry.name}..."
        fn="ipvanish/#{entry.name}"
        File.delete(fn) if File.exists?(fn)
        entry.extract(fn)
        File.write(fn,File.read(fn)+ "\nlog-append #{flog}\n") 
        lfn << entry.name if entry.name =~ /.ovpn$/
        if entry.name =~ /^ca.*.crt$/
          File.delete(entry.name) if File.exists?(entry.name)
          entry.extract(entry.name) # create in local directory
        end
      end
    end
    puts "loading list server (#{lfn.size})..."
    gui_invoke { @treeview.set_data([%w{. loading . .}]) }
    provider={}
    lfn.sort.each { |name|
      _,country,town,abrev,srv=*name.split(/[\-\.]/)[0..-2]
      key="%s %-15s"%[country,town]
      provider[key]||=[country,town,{}]
      provider[key].last[srv]=name
    }
    provider=provider.each_with_object({}) {|(k,v),h| h[k]=v  if v.last.size>0} # only contry with almost 1 server
    provider=provider.each_with_object({}) {|(k,v),h| h[k]=v  if v.last.size>1} # only contry with several server

    gui_invoke {
      $provider={}
      ldata=provider.values.each_with_object([]) do |(country,town,h),lout| 
         id=(lout.size+1).to_s
         lout << [id,country,town,h.size.to_s]
         $provider[id]=h
      end
      @treeview.set_data(ldata)
    }
  rescue Exception => e
      gui_invoke { error(e)}
  end
end

def choose_provider(items)
  item=items.split(/\s+/).first
  sel=nil
  if $provider[item].size>1
    ok=dialog("Server selection") {
          labeli("Selection of server on #{items}")
          l=list("Server",100,200) {|isels,csels|  sel=csels.first ; true}
          l.set_data($provider[item].keys)
    }
    return unless ok
  else
    return unless ask("Ok for connection on #{items} ?")
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
  return unless $current.size>0
  openvpn($current,$current,"/tmp/openvpn_ipvanish.log")
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
         @treeview=grid(%w{ID Country Town #Servers},200,200) { |lvalues| 
            @pvc.text=lvalues[0..2].join(" ") rescue nil
            true
         }
         flowi { 
           @pvc=entry("...",width:200)
           button("Connect...") { choose_provider(@pvc.text) if @pvc.text.size>3 }
         }
       end
     end
  end
  ############### initial traitments
  after(50) do
    status_connection(true)
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
