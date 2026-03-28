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
    
    # --- LaunchCloud Sovereign Defaults ---
    DEFAULT_DOMAIN = "launchcloud"
    DEFAULT_TOKEN  = "7b27785e-6725-4c47-8fb3-54264301de13"
    # --------------------------------------

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
        rescue
          return base_state
        end
      end
      
      base_state
    end

    def self.check
      FlehMesh::UI.header("PRE-FLIGHT CHECK")
      results = []
      
      if system("ssh -V > /dev/null 2>&1")
        results << ["SSH Client", "âœ“".colorize(:green)]
      else
        results << ["SSH Client", "âœ˜".colorize(:red)]
      end

      if system("ssh-keygen -V > /dev/null 2>&1")
        results << ["SSH Keygen", "âœ“".colorize(:green)]
      else
        results << ["SSH Keygen", "âœ˜".colorize(:red)]
      end

      if system("which upnpc > /dev/null 2>&1")
        results << ["UPnP (Router Punch)", "âœ“ Ready".colorize(:green)]
      else
        results << ["UPnP (Router Punch)", "âœ˜ Not Installed".colorize(:yellow)]
      end

      FlehMesh::UI.table(["Component", "Status"], results)
      FlehMesh::UI.footer
    end

    def self.setup_id(domain, token)
      FlehMesh::UI.header("IDENTITY CONFIGURATION")
      FlehMesh::UI.info("Domain: #{domain}.duckdns.org")
      
      save_state({ domain: domain, token: token })
      
      FlehMesh::UI.step("Updating DuckDNS record...")
      url = "https://www.duckdns.org/update?domains=#{domain}&token=#{token}&ip="
      begin
        response = Net::HTTP.get(URI(url))
        if response == "OK"
          FlehMesh::UI.success("Identity is live at #{domain}.duckdns.org!")
        else
          FlehMesh::UI.error("Failed to update: #{response}")
        end
      rescue => e
        FlehMesh::UI.error("Network error: #{e.message}")
      end
      FlehMesh::UI.footer
    end

    def self.punch(port = 54321)
      FlehMesh::UI.header("GHOSTPORT PUNCH")
      FlehMesh::UI.info("Forwarding External #{port} -> Internal 22")
      
      save_state({ ghost_port: port })
      
      if system("which upnpc > /dev/null 2>&1")
        FlehMesh::UI.step("Locating router and creating mapping...")
        internal_ip = `hostname -I 2>/dev/null | awk '{print $1}'`.strip
        internal_ip = `ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1`.strip if internal_ip.empty?
        
        res = `upnpc -a #{internal_ip} 22 #{port} TCP`
        if res =~ /mapping successful/i || res =~ /Redirecting/i
          FlehMesh::UI.success("GhostPort is open and punching!")
        else
          FlehMesh::UI.error("Router rejected mapping. Try manual forwarding.")
        end
      else
        FlehMesh::UI.error("UPnP Tool Missing. (brew install miniupnpc)")
      end
      FlehMesh::UI.footer
    end

    def self.add_user(name, pin)
      FlehMesh::UI.header("NEW EMPLOYEE PROVISION")
      state = load_state
      domain = state[:domain]
      port = state[:ghost_port]

      key_dir = File.join(File.expand_path("../..", __FILE__), "keys", name)
      FileUtils.mkdir_p(key_dir)
      key_path = File.join(key_dir, "id_fleh_#{name}")
      
      FlehMesh::UI.step("Generating PIN-Protected SSH credentials...")
      system("ssh-keygen -t ed25519 -f #{key_path} -N '#{pin}' -q")
      
      public_key = File.read("#{key_path}.pub").strip
      
      FlehMesh::UI.step("Authorizing access on local system...")
      ssh_dir = File.expand_path("~/.ssh")
      FileUtils.mkdir_p(ssh_dir)
      FileUtils.chmod(0700, ssh_dir)
      
      auth_file = File.join(ssh_dir, "authorized_keys")
      File.open(auth_file, "a") { |f| f.puts("\n# Fleh Mesh: #{name}\n#{public_key}") }
      FileUtils.chmod(0600, auth_file)
      
      users = state[:users] || []
      users << { name: name, created_at: Time.now }
      save_state({ users: users })

      FlehMesh::UI.success("Employee authorized successfully.")
      
      puts "\n" + "-" * 70
      puts " #{'SHELLY SSH CREDENTIALS (Sovereign Passphrase Mode)'.colorize(:white).bold}"
      puts "-" * 70
      puts "  1. Host: #{domain}.duckdns.org".colorize(:yellow)
      puts "  2. Port: #{port}".colorize(:green)
      puts "  3. User: #{ENV['USER']}".colorize(:green)
      puts "  4. Secret PIN: #{pin.colorize(:light_red)}"
      puts "  5. Key File: #{key_path}"
      puts "-" * 70
      FlehMesh::UI.footer
    end

    def self.revoke_user(name)
      FlehMesh::UI.header("ACCESS REVOCATION")
      state = load_state
      
      key_path = File.join(File.expand_path("../..", __FILE__), "keys", name, "id_fleh_#{name}.pub")
      if File.exist?(key_path)
        pub_key = File.read(key_path).strip.split[1]
        auth_file = File.expand_path("~/.ssh/authorized_keys")
        if File.exist?(auth_file)
          lines = File.readlines(auth_file).reject { |line| line.include?(pub_key) }
          File.write(auth_file, lines.join)
          FlehMesh::UI.success("Access terminated for #{name}.")
        end
      end

      users = (state[:users] || []).reject { |u| u[:name] == name }
      save_state({ users: users })
      FlehMesh::UI.footer
    end

    def self.check_live_status
      state = load_state
      domain = state[:domain]
      port = state[:ghost_port]
      
      status = { identity: :offline, ghostport: :offline }
      if domain
        begin
          Socket.getaddrinfo("#{domain}.duckdns.org", nil)
          status[:identity] = :online
        rescue; end
        
        begin
          Socket.tcp("#{domain}.duckdns.org", port, connect_timeout: 2)
          status[:ghostport] = :online
        rescue; end
      end
      status
    end
  end
end
