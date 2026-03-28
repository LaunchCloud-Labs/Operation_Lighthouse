require 'tty-prompt'
require_relative '../fleh_mesh'

module FlehMesh
  class Interactive
    def self.start
      prompt = TTY::Prompt.new(help_color: :cyan)
      
      loop do
        state = FlehMesh::Logic.load_state
        domain = state[:domain] || "NOT SET"
        port = state[:ghost_port] || 54321
        live_status = FlehMesh::Logic.check_live_status
        
        FlehMesh::UI.header("MISSION CONTROL")
        
        status_line = "  Status: "
        status_line += live_status[:identity] == :online ? "[IDENTITY OK]".colorize(:green) : "[IDENTITY ERROR]".colorize(:red)
        status_line += " | "
        status_line += live_status[:ghostport] == :online ? "[GHOSTPORT OPEN]".colorize(:green) : "[GHOSTPORT CLOSED]".colorize(:red)
        puts status_line + "\n"

        choices = [
          { name: "ðŸš€  One-Click Deployment (Identity + Punch)", value: :quick_start },
          { name: "â„¹  Verify System Readiness", value: :check },
          { name: "ðŸ’¤  Provision New Employee", value: :add_user },
          { name: "ðŸ”¥  Revoke Employee Access", value: :revoke },
          { name: "âš™ï¸  Advanced Settings (Manual Config)", value: :advanced },
          { name: "âŒ  Exit", value: :exit }
        ]
        
        action = prompt.select("Action:", choices, cycle: true)
        
        case action
        when :quick_start
          domain = prompt.ask("Domain Name (e.g. launchcloud):", default: state[:domain])
          token = prompt.mask("DuckDNS Token:", default: state[:token])
          FlehMesh::Logic.setup_id(domain, token)
          FlehMesh::Logic.punch(port)
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
          adv_choices = [
            { name: "Update Identity Only", value: :identity },
            { name: "Update GhostPort Only", value: :punch },
            { name: "Back", value: :back }
          ]
          adv_action = prompt.select("Advanced:", adv_choices)
          case adv_action
          when :identity
            domain = prompt.ask("Domain Name:", default: state[:domain])
            token = prompt.mask("Token:", default: state[:token])
            FlehMesh::Logic.setup_id(domain, token)
          when :punch
            port = prompt.ask("Port:", default: 54321, convert: :int)
            FlehMesh::Logic.punch(port)
          end
        when :exit
          FlehMesh::UI.status("âœ‹", "Sovereignty maintained.", :cyan)
          break
        end
      end
    end
  end
end
