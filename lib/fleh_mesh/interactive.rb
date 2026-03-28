require 'tty-prompt'
require_relative '../fleh_mesh'

module FlehMesh
  class Interactive
    def self.start
      prompt = TTY::Prompt.new(help_color: :cyan)
      
      loop do
        state = FlehMesh::Logic.load_state
        domain = state[:domain]
        token = state[:token]
        port = state[:ghost_port] || 54321
        live_status = FlehMesh::Logic.check_live_status
        
        FlehMesh::UI.header("MISSION CONTROL")
        
        status_line = "  Status: "
        status_line += live_status[:identity] == :online ? "[IDENTITY OK]".colorize(:green) : "[IDENTITY ERROR]".colorize(:red)
        status_line += " | "
        status_line += live_status[:ghostport] == :online ? "[GHOSTPORT OPEN]".colorize(:green) : "[GHOSTPORT CLOSED]".colorize(:red)
        puts status_line + "\n"

        choices = [
          { name: "ðŸš€  RE-SYNC MESH (Automated Identity + Punch)", value: :quick_start },
          { name: "â„¹  Verify System Readiness", value: :check },
          { name: "ðŸ’¤  Provision New Employee", value: :add_user },
          { name: "ðŸ”¥  Revoke Employee Access", value: :revoke },
          { name: "âš™ï¸  Change Identity/Token (Manual)", value: :advanced },
          { name: "âŒ  Exit", value: :exit }
        ]
        
        action = prompt.select("Action:", choices, cycle: true)
        
        case action
        when :quick_start
          if domain && token
            FlehMesh::UI.info("Auto-syncing using saved credentials for #{domain}...")
            FlehMesh::Logic.setup_id(domain, token)
            FlehMesh::Logic.punch(port)
          else
            FlehMesh::UI.error("No credentials found. Please use 'Advanced Settings' to set Domain and Token once.")
            if prompt.yes?("Set them now?")
              domain = prompt.ask("Domain Name (e.g. launchcloud):")
              token = prompt.mask("DuckDNS Token:")
              FlehMesh::Logic.setup_id(domain, token)
              FlehMesh::Logic.punch(port)
            end
          end
        when :check
          FlehMesh::Logic.check
        when :add_user
          name = prompt.ask("Employee Name:")
          pin = prompt.ask("Assign Secret PIN (Employee Passphrase):", required: true)
          FlehMesh::Logic.add_user(name, pin)
        when :revoke
          users = state[:users] || []
          if users.empty?
            FlehMesh::UI.error("No active employees found.")
          else
            name = prompt.select("Select employee to KILL access:", users.map { |u| u[:name] })
            FlehMesh::Logic.revoke_user(name) if prompt.yes?("Are you sure?")
          end
        when :advanced
          domain = prompt.ask("New Domain Name:", default: state[:domain])
          token = prompt.mask("New DuckDNS Token:", default: state[:token])
          FlehMesh::Logic.setup_id(domain, token)
          FlehMesh::UI.success("Credentials updated and saved.")
        when :exit
          FlehMesh::UI.status("âœ‹", "Sovereignty maintained.", :cyan)
          break
        end
      end
    end
  end
end
