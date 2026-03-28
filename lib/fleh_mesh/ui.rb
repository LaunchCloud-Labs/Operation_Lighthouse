require 'colorize'
require 'tty-table'
require 'tty-spinner'

module FlehMesh
  module UI
    def self.header(title)
      puts "\n"
      puts "  #{"LIGHTHOUSE".colorize(:cyan).bold} #{"________________________________________________________________________________".colorize(:light_black)}"
      puts "  #{"SOVEREIGN SSH MESH".colorize(:light_black)} | #{"v0.1.1".colorize(:light_black)}"
      puts "\n  #{'['.colorize(:light_black)} #{title.colorize(:white).bold} #{']'.colorize(:light_black)}"
      puts "\n"
    end

    def self.status(icon, message, color = :white)
      puts "  #{icon.colorize(color)} #{message.colorize(color)}"
    end

    def self.success(message)
      status("âœ“", message, :green)
    end

    def self.error(message)
      status("âœ˜", message, :red)
    end

    def self.info(message)
      status("â„¹", message, :blue)
    end

    def self.step(message)
      status("â–ªï¸", message, :light_black)
    end

    def self.table(header, rows)
      table = TTY::Table.new(header, rows)
      puts table.render(:unicode, padding: [0, 1, 0, 1])
    end

    def self.spinner(message)
      spinner = TTY::Spinner.new("  :spinner #{message.colorize(:white)}", format: :dots)
      spinner.auto_spin
      yield(spinner)
      spinner.success("Done!".colorize(:green))
    end

    def self.footer
      puts "\n  #{"________________________________________________________________________________________________".colorize(:light_black)}"
      puts "  #{'LaunchCloud Labs'.colorize(:cyan)} | #{'FirstLight | EventHorizon (FLEH)'.colorize(:light_red)}"
      puts "\n"
    end
  end
end
