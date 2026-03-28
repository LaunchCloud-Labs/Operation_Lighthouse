require 'tty-prompt'
require_relative '../fleh_mesh'

module FlehMesh
  class Interactive
    def self.start
      prompt = TTY::Prompt.new(help_color: :cyan)
      
      loop do
        # 1. Load current state and check status
        state = FlehMesh::Logic.load_state
        domain = state[:domain] || "NOT SET"
        port = state[:ghost_port] || 54321
        live_status = FlehMesh::Logic.check_live_status
        
        # 2. Render Header with Live Status
        FlehMesh::UI.header("MISSION CONTROL")
        
        status_line = "  Identity: #{domain.colorize(:yellow)} "
        status_line += live_status[:identity] == :online ? "[ONLINE]".colorize(:green) : "[OFFLINE]".colorize(:red)
        status_line += " | GhostPort: #{port.to_s.colorize(:yellow)} "
        status_line += live_status[:ghostport] == :online ? "[OPEN]".colorize(:green) : "[CLOSED]".colorize(:red)
        puts status_line + "\n\n"

        # 3. Build Menu
        choices = [
          { name: "â„¹  Pre-Flight Check (Verify System)", value: :check },
          { name: "ðŸ”  Setup/Update Identity (DuckDNS)", value: :identity },
          { name: "ðŸ¥Š  Punch GhostPort (Open Router Door)", value: :punch },
          { name: "ðŸ’¤  Add New Employee (Provision Access)", value: :add_user },
          { name: "ðŸ”¥  Revoke Employee Access", value: :revoke },
          { name: "âŒ  Exit", value: :exit }
        ]
        
        action = prompt.select("Choose an action:", choices, cycle: true)
        
        case action
        when :check
          FlehMesh::Logic.check
        when :identity
          domain = prompt.ask("Domain Name (e.g. launchcloud):", default: state[:domain])
          token = prompt.mask("DuckDNS Token:", default: state[:token])
          FlehMesh::Logic.setup_id(domain, token)
        when :punch
          port = prompt.ask("External GhostPort (Default 54321):", default: 54321, convert: :int)
          FlehMesh::Logic.punch(port)
        when :add_user
          name = prompt.ask("Employee Name:")
          pin = prompt.ask("Set a PIN (This is the employee's secret):", required: true)
          FlehMesh::Logic.add_user(name, pin)
        when :revoke
          users = state[:users] || []
          if users.empty?
            FlehMesh::UI.error("No employees found to revoke.")
          else
            name = prompt.select("Select employee to REVOKE:", users.map { |u| u[:name] })
            if prompt.yes?("Are you sure you want to KILL access for #{name}?")
              FlehMesh::Logic.revoke_user(name)
            end
          end
        when :exit
          FlehMesh::UI.status("âœ‹", "Exiting Mission Control. Sovereignty maintained.", :cyan)
          break
        end
      end
    end
  end
end
