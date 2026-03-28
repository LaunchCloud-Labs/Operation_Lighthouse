require 'tty-prompt'
require_relative '../fleh_mesh'

module FlehMesh
  class Interactive
    def self.start
      prompt = TTY::Prompt.new(help_color: :cyan)
      
      FlehMesh::UI.header("MISSION CONTROL")
      
      loop do
        choices = [
          { name: "â„¹  Pre-Flight Check", value: :check },
          { name: "ðŸ”  Sovereign Identity (DuckDNS)", value: :identity },
          { name: "ðŸ¥Š  Punch GhostPort (Router)", value: :punch },
          { name: "ðŸ’¤  Add Employee (Shelly Access)", value: :add_user },
          { name: "ðŸ“Š  Dashboard & Health", value: :status },
          { name: "ðŸ›¡ï¸  Security Audit", value: :audit },
          { name: "âŒ  Exit", value: :exit }
        ]
        
        action = prompt.select("Main Menu:", choices, cycle: true)
        
        case action
        when :check
          FlehMesh::Logic.check
        when :identity
          domain = prompt.ask("Domain Name (e.g. launchcloud):")
          token = prompt.mask("DuckDNS Token:")
          FlehMesh::Logic.setup_id(domain, token)
        when :punch
          port = prompt.ask("External GhostPort:", default: 54321, convert: :int)
          FlehMesh::Logic.punch(port)
        when :add_user
          name = prompt.ask("Employee Name:")
          FlehMesh::Logic.add_user(name)
        when :status
          ip = prompt.ask("Lighthouse/Identity IP or Domain:", default: "launchcloud.duckdns.org")
          FlehMesh::Logic.status(ip)
        when :audit
          ip = prompt.ask("Target IP:")
          FlehMesh::Logic.audit(ip)
        when :exit
          FlehMesh::UI.status("âœ‹", "Exiting Mission Control. Sovereignty maintained.", :cyan)
          break
        end
      end
    end
  end
end
