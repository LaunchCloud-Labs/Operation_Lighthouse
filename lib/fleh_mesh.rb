require 'net/ssh'
require 'net/scp'
require 'securerandom'
require 'socket'
require_relative 'fleh_mesh/ui'

module FlehMesh
  module Logic
    def self.install
      FlehMesh::UI.header("GLOBAL INSTALLATION")
      
      bin_path = File.expand_path(File.join(File.dirname(__FILE__), "../../bin/fleh-mesh"))
      targets = ["/usr/local/bin/lcl-tunnel", "/usr/local/bin/lcl-lighthouse"]
      
      targets.each do |target|
        FlehMesh::UI.step("Creating symlink: #{target}...")
        system("sudo ln -sf #{bin_path} #{target}")
      end
      
      FlehMesh::UI.success("Operation Lighthouse is now available globally!")
      FlehMesh::UI.info("Try running: lcl-tunnel check")
      FlehMesh::UI.footer
    end

    def self.check
      FlehMesh::UI.header("PRE-FLIGHT CHECK")
      
      results = []
      
      # SSH Client
      if system("ssh -V > /dev/null 2>&1")
        results << ["SSH Client", "âœ“ Installed".colorize(:green)]
      else
        results << ["SSH Client", "âœ˜ Missing".colorize(:red)]
      end

      # SSH Keygen
      if system("ssh-keygen -V > /dev/null 2>&1")
        results << ["SSH Keygen", "âœ“ Installed".colorize(:green)]
      else
        results << ["SSH Keygen", "âœ˜ Missing".colorize(:red)]
      end

      # Systemd
      if system("systemctl --version > /dev/null 2>&1")
        results << ["Systemd", "âœ“ Available".colorize(:green)]
      else
        results << ["Systemd", "âœ˜ N/A (macOS/Non-Linux)".colorize(:yellow)]
      end

      FlehMesh::UI.table(["Component", "Status"], results)
      FlehMesh::UI.footer
    end

    def self.status(ip, port = 2222)
      FlehMesh::UI.header("MESH HEALTH DASHBOARD")
      
      FlehMesh::UI.spinner("Probing Lighthouse Relay (#{ip})...") do |s|
        # Check if port is open
        begin
          Socket.tcp(ip, port, connect_timeout: 5)
          s.update(title: "Lighthouse Port #{port}: #{'OPEN'.colorize(:green)}")
        rescue
          s.update(title: "Lighthouse Port #{port}: #{'CLOSED/FILTERED'.colorize(:red)}")
        end
      end

      FlehMesh::UI.info("Local Service: " + (`systemctl is-active fleh-tunnel.service 2>/dev/null`.strip.colorize(:cyan) rescue "Unknown"))
      FlehMesh::UI.footer
    end

    def self.audit(ip, user = 'root')
      FlehMesh::UI.header("SECURITY AUDIT")
      FlehMesh::UI.info("Auditing Lighthouse: #{ip}")

      Net::SSH.start(ip, user) do |ssh|
        issues = []
        
        # Check for PasswordAuth
        if ssh.exec!("grep '^PasswordAuthentication' /etc/ssh/sshd_config") =~ /yes/
          issues << ["Password Auth", "ENABLED".colorize(:red), "Disable for security"]
        else
          issues << ["Password Auth", "DISABLED".colorize(:green), "Good"]
        end

        # Check for RootLogin
        if ssh.exec!("grep '^PermitRootLogin' /etc/ssh/sshd_config") =~ /yes/
          issues << ["Root Login", "ENABLED".colorize(:yellow), "Consider disabling"]
        else
          issues << ["Root Login", "LOCKED".colorize(:green), "Good"]
        end

        FlehMesh::UI.table(["Audit Item", "State", "Recommendation"], issues)
      end
      
      FlehMesh::UI.footer
    end

    def self.init_lighthouse(ip, user)
      FlehMesh::UI.header("PROVISIONING LIGHTHOUSE RELAY")
      FlehMesh::UI.info("Target: #{ip} as #{user}")
      
      begin
        Net::SSH.start(ip, user) do |ssh|
          FlehMesh::UI.step("Enabling GatewayPorts in sshd_config...")
          ssh.exec!("sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config")
          ssh.exec!("sudo sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config")
          ssh.exec!("sudo systemctl restart ssh")

          FlehMesh::UI.step("Creating 'lighthouse' service user...")
          ssh.exec!("sudo useradd -m -s /bin/bash lighthouse")
          ssh.exec!("sudo mkdir -p /home/lighthouse/.ssh")
          ssh.exec!("sudo chmod 700 /home/lighthouse/.ssh")
          ssh.exec!("sudo touch /home/lighthouse/.ssh/authorized_keys")
          ssh.exec!("sudo chmod 600 /home/lighthouse/.ssh/authorized_keys")
          ssh.exec!("sudo chown -R lighthouse:lighthouse /home/lighthouse/.ssh")
          
          FlehMesh::UI.step("Hardening Firewall (Allowing 22, 2222)...")
          ssh.exec!("sudo ufw allow 22/tcp")
          ssh.exec!("sudo ufw allow 2222/tcp")
          ssh.exec!("sudo ufw --force enable")
        end
        FlehMesh::UI.success("Lighthouse initialized and hardened at #{ip}!")
      rescue => e
        FlehMesh::UI.error("Connection failed: #{e.message}")
      end
      
      FlehMesh::UI.footer
    end

    def self.connect_home(lighthouse_ip, lighthouse_user, remote_port)
      FlehMesh::UI.header("LINKING HOMEBASE TO RELAY")
      FlehMesh::UI.info("Lighthouse: #{lighthouse_ip}")
      
      key_path = File.expand_path("~/.ssh/id_fleh_tunnel")
      unless File.exist?(key_path)
        FlehMesh::UI.step("Generating master tunnel SSH key...")
        system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")
      end
      
      public_key = File.read("#{key_path}.pub").strip
      
      begin
        FlehMesh::UI.step("Authorizing HomeBase on Lighthouse...")
        Net::SSH.start(lighthouse_ip, 'root') do |ssh|
          ssh.exec!("echo '#{public_key}' | sudo tee -a /home/lighthouse/.ssh/authorized_keys")
        end

        FlehMesh::UI.step("Installing systemd tunnel service...")
        service_content = <<~SERVICE
          [Unit]
          Description=Fleh Mesh Reverse Tunnel (Operation Lighthouse)
          After=network.target

          [Service]
          User=#{ENV['USER']}
          ExecStart=/usr/bin/ssh -N -R #{remote_port}:localhost:22 -o "ExitOnForwardFailure=yes" -o "ServerAliveInterval=60" -i #{key_path} #{lighthouse_user}@#{lighthouse_ip}
          Restart=always
          RestartSec=10

          [Install]
          WantedBy=multi-user.target
        SERVICE

        service_path = "/tmp/fleh-tunnel.service"
        File.write(service_path, service_content)
        
        FlehMesh::UI.step("Activating service (requires sudo)...")
        system("sudo cp #{service_path} /etc/systemd/system/fleh-tunnel.service")
        system("sudo systemctl daemon-reload")
        system("sudo systemctl enable fleh-tunnel.service")
        system("sudo systemctl start fleh-tunnel.service")

        FlehMesh::UI.success("HomeBase is live on Lighthouse port #{remote_port}!")
      rescue => e
        FlehMesh::UI.error("Failed to link HomeBase: #{e.message}")
      end

      FlehMesh::UI.footer
    end

    def self.add_user(name)
      FlehMesh::UI.header("PROVISIONING NEW EMPLOYEE")
      FlehMesh::UI.info("Employee: #{name}")
      
      key_dir = File.expand_path("./keys/#{name}")
      FileUtils.mkdir_p(key_dir)
      key_path = File.join(key_dir, "id_fleh_#{name}")
      
      FlehMesh::UI.step("Generating secure SSH credentials...")
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")
      
      public_key = File.read("#{key_path}.pub").strip
      
      FlehMesh::UI.step("Authorizing access on local HomeBase...")
      authorized_keys_path = File.expand_path("~/.ssh/authorized_keys")
      File.open(authorized_keys_path, "a") { |f| f.puts("\n# Fleh Mesh: #{name}\n#{public_key}") }
      
      FlehMesh::UI.success("Employee #{name.bold} is authorized.")
      
      puts "\n" + "-" * 60
      puts " #{'SHELLY SSH CONFIGURATION'.colorize(:white).bold}"
      puts "-" * 60
      puts " 1. Connection: #{'SSH'.colorize(:cyan)}"
      puts " 2. Host: #{'[YOUR_LIGHTHOUSE_IP]'.colorize(:yellow)}"
      puts " 3. Port: #{'2222'.colorize(:green)}"
      puts " 4. User: #{ENV['USER'].colorize(:green)}"
      puts " 5. Private Key: #{key_path.colorize(:light_black)}"
      puts "-" * 60
      
      FlehMesh::UI.footer
    end
  end
end
