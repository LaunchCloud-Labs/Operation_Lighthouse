require 'net/ssh'
require 'net/scp'
require 'securerandom'
require 'socket'
require 'net/http'
require 'json'
require 'fileutils'
require_relative 'fleh_mesh/ui'

module FlehMesh
  module Logic
    CONFIG_FILE = File.expand_path("~/.fleh_mesh.json")
    
    DEFAULT_DOMAIN = "launchcloud"
    DEFAULT_TOKEN  = "7b27785e-6725-4c47-8fb3-54264301de13"

    def self.save_state(data)
      state = load_state.merge(data)
      File.write(CONFIG_FILE, state.to_json)
    end

    def self.load_state
      base_state = { domain: DEFAULT_DOMAIN, token: DEFAULT_TOKEN, ghost_port: 54321, users: [] }
      if File.exist?(CONFIG_FILE)
        begin
          saved_state = JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
          return base_state.merge(saved_state)
        rescue; end
      end
      base_state
    end

    def self.get_internal_ip
      # Smart IP Discovery: Reject ALL 127.x (Loopback) and 100.x (Tailscale)
      ips = Socket.ip_address_list.select { |ai| ai.ipv4? }
      
      # Filter out all loopback ranges and Tailscale
      ips.reject! { |ai| ai.ip_address.start_with?("127.") }
      ips.reject! { |ai| ai.ip_address.start_with?("100.") }
      
      # Prioritize the physical LAN IP
      lan_ip = ips.find { |ai| ai.ip_address.start_with?("192.168.") || ai.ip_address.start_with?("10.") || ai.ip_address.start_with?("172.") }
      
      lan_ip ? lan_ip.ip_address : ips.first&.ip_address
    end

    def self.check
      FlehMesh::UI.header("PRE-FLIGHT CHECK")
      results = []
      
      results << ["SSH Client", (system("which ssh > /dev/null") ? "âœ“".colorize(:green) : "âœ˜".colorize(:red))]
      results << ["SSH Keygen", (system("which ssh-keygen > /dev/null") ? "âœ“".colorize(:green) : "âœ˜".colorize(:red))]
      results << ["UPnP Tool", (system("which upnpc > /dev/null") ? "âœ“".colorize(:green) : "âœ˜".colorize(:yellow))]
      results << ["Physical LAN IP", get_internal_ip.colorize(:cyan)]
      
      FlehMesh::UI.table(["Component", "Status"], results)
      FlehMesh::UI.footer
    end

    def self.setup_id(domain, token)
      FlehMesh::UI.header("IDENTITY CONFIGURATION")
      save_state({ domain: domain, token: token })
      
      url = "https://www.duckdns.org/update?domains=#{domain}&token=#{token}&ip="
      begin
        response = Net::HTTP.get(URI(url))
        if response == "OK"
          FlehMesh::UI.success("Identity live at #{domain}.duckdns.org")
        else
          FlehMesh::UI.error("DuckDNS Update Failed: #{response}")
        end
      rescue => e
        FlehMesh::UI.error("Network error: #{e.message}")
      end
      FlehMesh::UI.footer
    end

    def self.punch(port = 54321)
      FlehMesh::UI.header("GHOSTPORT PUNCH")
      save_state({ ghost_port: port })
      
      # Check if already open first
      status = check_live_status
      if status[:ghostport] == :online
        FlehMesh::UI.success("GhostPort is already OPEN and working. Skipping punch.")
        FlehMesh::UI.footer
        return
      end

      if system("which upnpc > /dev/null 2>&1")
        ip = get_internal_ip
        FlehMesh::UI.step("Punching router for #{ip}...")
        res = `upnpc -a #{ip} 22 #{port} TCP`
        
        if res =~ /mapping successful/i || res =~ /Redirecting/i
          FlehMesh::UI.success("GhostPort is OPEN.")
        else
          FlehMesh::UI.error("AUTOMATIC PUNCH FAILED")
          puts "\n  #{"YOUR ROUTER IS LOCKED".colorize(:white).bold.on_red}"
          puts "  To enable Shelly access, you must do this ONE TIME manually:"
          puts "  1. Log into your router (usually 192.168.1.1)"
          puts "  2. Go to 'Port Forwarding' or 'Virtual Server'"
          puts "  3. Create a rule: #{'External Port:'.colorize(:cyan)} #{port.to_s.bold}"
          puts "  4. Set #{'Internal IP:'.colorize(:cyan)} #{ip.bold}"
          puts "  5. Set #{'Internal Port:'.colorize(:cyan)} 22"
        end
      else
        FlehMesh::UI.error("Missing 'upnpc'. (brew install miniupnpc)")
      end
      FlehMesh::UI.footer
    end

    def self.add_user(name, pin)
      FlehMesh::UI.header("EMPLOYEE PROVISION")
      state = load_state
      
      key_dir = File.join(File.expand_path("../..", __FILE__), "keys", name)
      FileUtils.mkdir_p(key_dir)
      key_path = File.join(key_dir, "id_fleh_#{name}")
      
      FlehMesh::UI.step("Generating PIN-Protected SSH credentials...")
      system("ssh-keygen -t ed25519 -f #{key_path} -N '#{pin}' -q")
      
      public_key = File.read("#{key_path}.pub").strip
      
      FlehMesh::UI.step("Authorizing access...")
      ssh_dir = File.expand_path("~/.ssh")
      FileUtils.mkdir_p(ssh_dir)
      FileUtils.chmod(0700, ssh_dir)
      
      auth_file = File.join(ssh_dir, "authorized_keys")
      File.open(auth_file, "a") { |f| f.puts("\n# Fleh Mesh: #{name}\n#{public_key}") }
      FileUtils.chmod(0600, auth_file)
      
      users = state[:users] || []
      users << { name: name, created_at: Time.now }
      save_state({ users: users })

      FlehMesh::UI.success("Employee authorized.")
      
      puts "\n" + "-" * 70
      puts " #{'SHELLY SSH CONFIGURATION'.colorize(:white).bold}"
      puts "-" * 70
      puts "  Host: #{state[:domain]}.duckdns.org".colorize(:yellow)
      puts "  Port: #{state[:ghost_port]}".colorize(:green)
      puts "  User: #{ENV['USER']}".colorize(:green)
      puts "  PIN:  #{pin.colorize(:light_red)}"
      puts "  Key:  #{key_path}"
      puts "-" * 70
      FlehMesh::UI.footer
    end

    def self.revoke_user(name)
      FlehMesh::UI.header("REVOCATION")
      state = load_state
      key_path = File.join(File.expand_path("../..", __FILE__), "keys", name, "id_fleh_#{name}.pub")
      if File.exist?(key_path)
        pub_key = File.read(key_path).strip.split[1]
        auth_file = File.expand_path("~/.ssh/authorized_keys")
        if File.exist?(auth_file)
          lines = File.readlines(auth_file).reject { |line| line.include?(pub_key) }
          File.write(auth_file, lines.join)
          FlehMesh::UI.success("Revoked #{name}.")
        end
      end
      users = (state[:users] || []).reject { |u| u[:name] == name }
      save_state({ users: users })
      FlehMesh::UI.footer
    end

    def self.check_live_status
      state = load_state
      status = { identity: :offline, ghostport: :offline }
      if state[:domain]
        begin
          Socket.getaddrinfo("#{state[:domain]}.duckdns.org", nil)
          status[:identity] = :online
        rescue; end
        begin
          # Check the domain on the ghost port
          Socket.tcp("#{state[:domain]}.duckdns.org", state[:ghost_port], connect_timeout: 2)
          status[:ghostport] = :online
        rescue; end
      end
      status
    end
  end
end
