require 'net/ssh'
require 'net/scp'
require 'securerandom'

module FlehMeshLogic
  def self.init_lighthouse(ip, user)
    puts "âœ¨ Initializing Lighthouse at #{ip}..."
    
    Net::SSH.start(ip, user) do |ssh|
      # 1. Enable GatewayPorts for reverse proxying
      puts "â–ªï¸ Enabling GatewayPorts in sshd_config..."
      ssh.exec!("sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config")
      ssh.exec!("sudo sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config")
      ssh.exec!("sudo systemctl restart ssh")

      # 2. Create a dedicated 'lighthouse' user for the tunnel
      puts "â–ªï¸ Creating 'lighthouse' service user..."
      ssh.exec!("sudo useradd -m -s /bin/bash lighthouse")
      ssh.exec!("sudo mkdir -p /home/lighthouse/.ssh")
      ssh.exec!("sudo chmod 700 /home/lighthouse/.ssh")
      ssh.exec!("sudo touch /home/lighthouse/.ssh/authorized_keys")
      ssh.exec!("sudo chmod 600 /home/lighthouse/.ssh/authorized_keys")
      ssh.exec!("sudo chown -R lighthouse:lighthouse /home/lighthouse/.ssh")
      
      # 3. Setup UFW if present
      puts "â–ªï¸ Configuring Firewall (UFW)..."
      ssh.exec!("sudo ufw allow 22/tcp")
      ssh.exec!("sudo ufw allow 2222/tcp")
      ssh.exec!("sudo ufw --force enable")
    end
    
    puts "âœ… Lighthouse initialized successfully!"
  end

  def self.connect_home(lighthouse_ip, lighthouse_user, remote_port)
    puts "âœ¨ Setting up HomeBase connection to #{lighthouse_ip}..."
    
    # 1. Generate a dedicated SSH key for the tunnel if it doesn't exist
    key_path = File.expand_path("~/.ssh/id_fleh_tunnel")
    unless File.exist?(key_path)
      puts "â–ªï¸ Generating tunnel SSH key..."
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")
    end
    
    public_key = File.read("#{key_path}.pub").strip
    
    # 2. Add the public key to the lighthouse user
    puts "â–ªï¸ Authorizing HomeBase on Lighthouse..."
    Net::SSH.start(lighthouse_ip, 'root') do |ssh|
      ssh.exec!("echo '#{public_key}' | sudo tee -a /home/lighthouse/.ssh/authorized_keys")
    end

    # 3. Create a systemd service for the tunnel
    puts "â–ªï¸ Installing systemd tunnel service..."
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
    
    puts "â–ªï¸ Enabling service (requires sudo)..."
    system("sudo cp #{service_path} /etc/systemd/system/fleh-tunnel.service")
    system("sudo systemctl daemon-reload")
    system("sudo systemctl enable fleh-tunnel.service")
    system("sudo systemctl start fleh-tunnel.service")

    puts "âœ… HomeBase is now connected to the Lighthouse!"
  end

  def self.add_user(name)
    puts "âœ¨ Provisioning Employee: #{name}..."
    
    # 1. Generate SSH keypair for the employee
    key_dir = File.expand_path("./keys/#{name}")
    FileUtils.mkdir_p(key_dir)
    key_path = File.join(key_dir, "id_fleh_#{name}")
    
    puts "â–ªï¸ Generating keys in #{key_dir}..."
    system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")
    
    public_key = File.read("#{key_path}.pub").strip
    
    # 2. Authorize the employee on the HomeBase (this machine)
    puts "â–ªï¸ Authorizing employee on HomeBase..."
    authorized_keys_path = File.expand_path("~/.ssh/authorized_keys")
    File.open(authorized_keys_path, "a") { |f| f.puts("\n# Fleh Mesh: #{name}\n#{public_key}") }
    
    puts "\nâœ… Employee #{name} Added!"
    puts "--------------------------------------------------"
    puts "INSTRUCTIONS FOR SHELLY SSH:"
    puts "1. Connection Type: SSH"
    puts "2. Host: [YOUR_LIGHTHOUSE_IP]"
    puts "3. Port: 2222"
    puts "4. User: #{ENV['USER']}"
    puts "5. Private Key: Copy content of #{key_path}"
    puts "--------------------------------------------------"
  end
end
