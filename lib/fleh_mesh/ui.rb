require 'colorize'
require 'tty-table'
require 'tty-spinner'

module FlehMesh
  module UI
    BANNER = <<~BANNER
      #{'      _____   ______ ______  _____      _____ _    _  _______ _    _  ____  _    _  _____ ______ '.colorize(:cyan)}
      #{'     |  __ \\ |  ____|  ____||  __ \\    |  __ \\ |  | ||__   __| |  | |/ __ \\| |  | |/ ____|  ____|'.colorize(:cyan)}
      #{'     | |__) || |__  | |__   | |__) |   | |__) | |__| |   | |  | |__| | |  | | |  | | (___ | |__   '.colorize(:cyan)}
      #{'     |  ___/ |  __| |  __|  |  _  /    |  _  /|  __  |   | |  |  __  | |  | | |  | |\\___ \\|  __|  '.colorize(:blue)}
      #{'     | |     | |____| |____ | | \\ \\    | | \\ \\| |  | |   | |  | |  | | |__| | |__| |____) | |____ '.colorize(:blue)}
      #{'     |_|     |______|______||_|  \\_\\   |_|  \\_\\_|  |_|   |_|  |_|  |_|\\____/ \\____/|_____/|______|'.colorize(:blue)}
      #{'                                                                                                  '.colorize(:blue)}
      #{'                 --- SOVEREIGN SSH MESH | OPERATION LIGHTHOUSE | v0.1.0 ---'.colorize(:light_black)}
    BANNER

    def self.header(title)
      puts "\n" + BANNER
      puts "\n#{'['.colorize(:light_black)} #{title.colorize(:white).bold} #{']'.colorize(:light_black)}".center(110)
      puts "-" * 110
    end

    def self.status(icon, message, color = :white)
      puts " #{icon.colorize(color)} #{message.colorize(color)}"
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
      puts table.render(:unicode, padding: [0, 1, 0, 1], alignments: [:left, :left])
    end

    def self.spinner(message)
      spinner = TTY::Spinner.new(" :spinner #{message.colorize(:white)}", format: :dots)
      spinner.auto_spin
      yield(spinner)
      spinner.success("Done!".colorize(:green))
    end

    def self.footer
      puts "-" * 110
      puts " #{'LaunchCloud Labs'.colorize(:cyan)} | #{'FirstLight | EventHorizon (FLEH)'.colorize(:light_red)}"
      puts "\n"
    end
  end
end
