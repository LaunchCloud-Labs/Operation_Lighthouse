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

    def self.save_state(data)
      state = load_state.merge(data)
      File.write(CONFIG_FILE, state.to_json)
    end

    def self.load_state
      return {} unless File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
    rescue
      {}
    end

    def self.setup_id(domain, token)
      FlehMesh::UI.header("CONFIGURING SOVEREIGN IDENTITY")
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
      FlehMesh::UI.header("GHOSTPORT: ROUTER PUNCH-THROUGH")
      save_state({ ghost_port: port })
      
      FlehMesh::UI.step("Discovering router via UPnP...")
      if system("which upnpc > /dev/null 2>&1")
        internal_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
        res = `upnpc -a #{internal_ip} 22 #{port} TCP`
        if res =~ /mapping successful/i || res =~ /Redirecting/i
          FlehMesh::UI.success("Router punched successfully!")
        else
          FlehMesh::UI.error("Router failed to punch.")
        end
      else
        FlehMesh::UI.error("Missing 'upnpc' tool. Please 'brew install miniupnpc'.")
      end
      FlehMesh::UI.footer
    end

    def self.add_user(name, pin)
      FlehMesh::UI.header("PROVISIONING NEW EMPLOYEE")
      state = load_state
      domain = state[:domain] || "launchcloud"
      port = state[:ghost_port] || 54321

      key_dir = File.expand_path("./keys/#{name}")
      FileUtils.mkdir_p(key_dir)
      key_path = File.join(key_dir, "id_fleh_#{name}")
      
      FlehMesh::UI.step("Generating PIN-Protected SSH credentials...")
      # Use PIN as passphrase (-N)
      system("ssh-keygen -t ed25519 -f #{key_path} -N '#{pin}' -q")
      
      public_key = File.read("#{key_path}.pub").strip
      
      FlehMesh::UI.step("Authorizing access on local HomeBase...")
      authorized_keys_path = File.expand_path("~/.ssh/authorized_keys")
      File.open(authorized_keys_path, "a") { |f| f.puts("\n# Fleh Mesh: #{name}\n#{public_key}") }
      
      # Save user to state
      users = state[:users] || []
      users << { name: name, created_at: Time.now }
      save_state({ users: users })

      FlehMesh::UI.success("Employee #{name.bold} is authorized.")
      
      puts "\n" + "-" * 60
      puts " #{'SHELLY SSH CONFIGURATION (GIVE THIS TO EMPLOYEE)'.colorize(:white).bold}"
      puts "-" * 60
      puts " 1. Connection: #{'SSH'.colorize(:cyan)}"
      puts " 2. Host: #{domain}.duckdns.org".colorize(:yellow)
      puts " 3. Port: #{port}".colorize(:green)
      puts " 4. User: #{ENV['USER']}".colorize(:green)
      puts " 5. Private Key: (The file generated in keys/#{name})"
      puts " 6. PIN/Passphrase: #{pin.colorize(:light_red)} (The employee MUST know this)"
      puts "-" * 60
      FlehMesh::UI.footer
    end

    def self.revoke_user(name)
      FlehMesh::UI.header("REVOKING ACCESS")
      state = load_state
      users = state[:users] || []
      
      # Remove from authorized_keys
      key_path = File.expand_path("./keys/#{name}/id_fleh_#{name}.pub")
      if File.exist?(key_path)
        pub_key = File.read(key_path).strip
        auth_file = File.expand_path("~/.ssh/authorized_keys")
        content = File.read(auth_file).gsub(/.*#{Regexp.escape(pub_key)}.*/, "")
        File.write(auth_file, content)
        FlehMesh::UI.success("Access revoked for #{name}.")
      end

      users.reject! { |u| u[:name] == name }
      save_state({ users: users })
      FlehMesh::UI.footer
    end

    def self.check_live_status
      state = load_state
      domain = state[:domain]
      port = state[:ghost_port] || 54321
      
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
