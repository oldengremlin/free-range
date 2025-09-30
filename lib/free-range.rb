require 'optparse'
require 'rmagick'
require 'fileutils'

class FreeRange
  # Змінні екземпляра для статичних параметрів
  attr_reader :config, :subscribers_result, :target, :use_color, :debug, :table_mode, :table_png_mode

  # Перевірка наявності ImageMagick
  begin
    require 'rmagick'
  rescue LoadError
    puts "Помилка: бібліотека rmagick не встановлена або ImageMagick недоступний."
    puts "Встановіть ImageMagick і виконайте: gem install rmagick"
    exit 1
  end

  # Клас для зберігання конфігураційних команд
  class Config
    attr_accessor :username, :password

    # Ініціалізує об’єкт конфігурації
    # @param login [Hash] Hash with target, username, and password
    # @yield [self] Yields self for block-based configuration
    def initialize(login)
      @login = login
      @username = nil
      @password = nil
      yield self if block_given?
    end

    # Повертає команду SSH
    # @return [String] SSH command string
    def ssh_command
      "sshpass -p \"#{@login[:password]}\" ssh -C -x -4 -o StrictHostKeyChecking=no #{@login[:username]}@#{@login[:target]}"
    end

    # Повертає команду для отримання даних про передплатників
    # @return [String] Subscribers command string
    def subscribers_command
      "ssh -C -x roffice /usr/local/share/noc/bin/radius-subscribers"
    end

    # Повертає команду для отримання списку інтерфейсів
    # @return [String] Command to fetch interfaces
    def command_interfaces
      'show configuration interfaces | no-more | display set | match dynamic-profile | match "ranges ([0-9]+(-[0-9]+)?)"'
    end

    # Повертає команду для отримання діапазонів VLAN
    # @param interface [String, nil] Interface name or nil for all interfaces
    # @return [String] Command to fetch VLAN ranges
    def command_ranges(interface = nil)
      interface ? "show configuration interfaces #{interface} | no-more | display set | match dynamic-profile | match \"ranges ([0-9]+(-[0-9]+)?)\"" : 'show configuration interfaces | no-more | display set | match dynamic-profile | match "ranges ([0-9]+(-[0-9]+)?)"'
    end

    # Повертає команду для отримання демультиплексорних VLAN
    # @param interface [String, nil] Interface name or nil for all interfaces
    # @return [String] Command to fetch demux VLANs
    def command_demux(interface = nil)
      interface ? "show configuration interfaces #{interface} | display set | match unnumbered-address" : 'show configuration interfaces | display set | match unnumbered-address'
    end

    # Повертає команду для отримання інших VLAN
    # @param interface [String, nil] Interface name or nil for all interfaces
    # @return [String] Command to fetch other VLANs
    def command_another(interface = nil)
      interface ? "show configuration interfaces #{interface} | display set | match vlan-id" : 'show configuration interfaces | display set | match vlan-id'
    end
  end

  # Абстрактний клас для роботи з VLAN
  class VlanContainer
    def initialize
      @vlans = []
    end

    # Додаємо VLAN до списку (віртуальний метод, може бути перевизначений)
    # @param vlan [Integer] VLAN ID to add
    # @return [void]
    def add_vlan(vlan)
      @vlans << vlan
    end

    # Повертаємо масив VLAN
    # @return [Array<Integer>] Sorted array of unique VLAN IDs
    def vlans
      @vlans.uniq.sort
    end

    # Створюємо хеш діапазонів із VLAN
    # @return [Hash{Integer => Integer}] Hash mapping range start to range end
    def ranges
      return {} if @vlans.empty?

      vlan_ranges_hash = {}
      sorted_vlans = vlans
      start = sorted_vlans.first
      prev = start

      sorted_vlans[1..-1].each do |vlan|
        unless vlan == prev + 1
          vlan_ranges_hash[start] = prev
          start = vlan
        end
        prev = vlan
      end
      vlan_ranges_hash[start] = prev

      vlan_ranges_hash
    end
  end

  # Клас для зберігання та обробки діапазонів
  class Ranges < VlanContainer
    def initialize
      super
      @another_in_ranges = []
    end

    # Додаємо діапазон до списку VLAN-ів
    # @param start [Integer] Start of VLAN range
    # @param finish [Integer] End of VLAN range
    # @return [void]
    def add_range(start, finish)
      (start..finish).each { |vlan| @vlans << vlan }
    end

    # Додаємо діапазон до списку "інших" VLAN-ів
    # @param start [Integer] Start of another VLAN range
    # @param finish [Integer] End of another VLAN range
    # @return [void]
    def add_another_range(start, finish)
      (start..finish).each { |vlan| @another_in_ranges << vlan }
    end

    # Повертаємо масив "інших" VLAN-ів
    # @return [Array<Integer>] Sorted array of unique "another" VLAN IDs
    def another_in_ranges
      @another_in_ranges.uniq.sort
    end
  end

  # Клас для зберігання та обробки VLAN-ів
  class Vlans < VlanContainer
    # Метод add_vlan уже успадковано від VlanContainer
    # Метод vlans уже успадковано
    # Метод ranges уже успадковано, але перейменуємо для зрозумілості
    alias vlan_ranges ranges
  end

  # Клас для виводу даних
  class Print
    # Виводить хеш діапазонів VLAN у порядку зростання
    # @param ranges [Ranges] Object containing VLAN ranges
    # @return [void]
    def self.ranged(ranges)
      puts "\nСформований хеш діапазонів (в порядку зростання):"
      if ranges.ranges.empty?
        puts "Не знайдено діапазонів."
      else
        ranges.ranges.sort_by { |k, _| k }.each do |start, end_val|
          puts "range[#{start}]=#{end_val}"
        end
      end
    end

    # Виводить зайняті VLAN-и в межах діапазонів у порядку зростання
    # @param vlans [Vlans] Object containing VLANs
    # @return [void]
    def self.vlans(vlans)
      puts "\nЗайняті VLAN-и в межах діапазонів (в порядку зростання):"
      if vlans.vlans.empty?
        puts "Не знайдено VLAN-ів у межах діапазонів."
      else
        puts vlans.vlans.uniq.sort.join(", ")
      end
    end

    # Виводить діапазони VLAN-ів у порядку зростання
    # @param vlans [Vlans] Object containing VLANs
    # @return [void]
    def self.vlan_ranges(vlans)
      puts "\nДіапазони VLAN-ів (в порядку зростання):"
      vlan_ranges = vlans.vlan_ranges
      if vlan_ranges.empty?
        puts "Не знайдено діапазонів VLAN-ів."
      else
        vlan_ranges.sort_by { |k, _| k }.each do |start, end_val|
          puts "range[#{start}]=#{end_val}"
        end
      end
    end

    # Виводить комбіновані діапазони VLAN зі статусами
    # @param ranges [Ranges] Object containing VLAN ranges
    # @param vlans [Vlans] Object containing VLANs
    # @param use_color [Boolean] Enable colored output
    # @param target [String] Target device hostname
    # @param interface [String, nil] Interface name or nil
    # @return [void]
    def self.combined_ranges(ranges, vlans, use_color, target, interface = nil)
      if ranges.ranges.empty?
        puts "Не знайдено діапазонів."
        return
      end

      all_vlans, _status_counts = build_vlan_statuses(ranges, vlans)
      result = []
      sorted_vlans = all_vlans.keys.sort
      start = sorted_vlans.first
      prev = start
      status = all_vlans[start]

      sorted_vlans[1..-1].each do |vlan|
        unless vlan == prev + 1 && all_vlans[vlan] == status
          result << format_range(start, prev, status, use_color)
          start = vlan
          status = all_vlans[vlan]
        end
        prev = vlan
      end
      result << format_range(start, prev, status, use_color)

      puts result.join(',')
    end

    # Виводить таблицю розподілу VLAN
    # @param ranges [Ranges] Object containing VLAN ranges
    # @param vlans [Vlans] Object containing VLANs
    # @param use_color [Boolean] Enable colored output
    # @param target [String] Target device hostname
    # @param interface [String, nil] Interface name or nil
    # @return [void]
    def self.table(ranges, vlans, use_color, target, interface = nil)
      puts "VLAN Distribution for #{target}#{interface ? " (#{interface})" : ''}"
      all_vlans, status_counts = build_vlan_statuses(ranges, vlans)

      puts "     0         1         2         3         4         5         6         7         8         9         "
      (0..40).each do |h|
        start_vlan = h * 100
        end_vlan = [start_vlan + 99, 4094].min
        row = (start_vlan..end_vlan).map { |vlan| format_table_char(all_vlans[vlan] || ' ', use_color) }.join
        puts "#{format("%4d", start_vlan)} #{row}"
      end

      legend_parts = [
        ["Legend: ", nil],
        ["f", 'f'], ["=free", nil], [", ", nil],
        ["b", 'b'], ["=busy", nil], [", ", nil],
        ["e", 'e'], ["=error", nil], [", ", nil],
        ["c", 'c'], ["=configured", nil], [", ", nil],
        ["a", 'a'], ["=another", nil], [", ", nil],
        ["u", 'u'], ["=unused", nil]
      ]
      legend_text = legend_parts.map do |text, status|
        if status && use_color
          format_table_char(status, use_color)
        else
          text
        end
      end.join
      puts "\n#{legend_text}"

      summary_parts = [
        ["Total: ", nil],
        ["f", 'f'], ["=#{status_counts['f']}", nil], [", ", nil],
        ["b", 'b'], ["=#{status_counts['b']}", nil], [", ", nil],
        ["e", 'e'], ["=#{status_counts['e']}", nil], [", ", nil],
        ["c", 'c'], ["=#{status_counts['c']}", nil], [", ", nil],
        ["a", 'a'], ["=#{status_counts['a']}", nil], [", ", nil],
        ["u", 'u'], ["=#{status_counts['u']}", nil]
      ]
      summary_text = summary_parts.map do |text, status|
        if status && use_color
          format_table_char(status, use_color)
        else
          text
        end
      end.join
      puts summary_text
    end

    # Зберігає таблицю розподілу VLAN як PNG-зображення
    # @param ranges [Ranges] Object containing VLAN ranges
    # @param vlans [Vlans] Object containing VLANs
    # @param path [String] Directory path to save the PNG
    # @param target [String] Target device hostname
    # @param interface [String, nil] Interface name or nil
    # @return [void]
    def self.table_png(ranges, vlans, path, target, interface = nil)
      all_vlans, status_counts = build_vlan_statuses(ranges, vlans)
      cell_width = 12
      cell_height = 20
      rows = 41
      cols = 100
      header_height = 60
      label_width = 50
      width = label_width + cols * cell_width + 10
      height = header_height + rows * cell_height + 20 + 50
      font_size = 14
      title_font_size = 18
      font = 'Courier'

      canvas = Magick::Image.new(width, height) { |options| options.background_color = 'white' }
      gc = Magick::Draw.new
      gc.font = font
      gc.pointsize = font_size
      gc.text_antialias = true

      gc.fill('black')
      gc.pointsize = title_font_size
      gc.text(10, 25, "VLAN Distribution for #{target}#{interface ? " (#{interface})" : ''}")
      gc.pointsize = font_size

      (0..9).each do |i|
        x = label_width + i * 10 * cell_width - 3
        gc.fill('black')
        gc.text(x + 5, header_height - 5, i.to_s)
      end

      (0..40).each do |h|
        start_vlan = h * 100
        end_vlan = [start_vlan + 99, 4094].min
        y = header_height + h * cell_height
        gc.fill('black')
        gc.text(5, y + font_size, format("%4d", start_vlan))

        (start_vlan..end_vlan).each_with_index do |vlan, i|
          status = all_vlans[vlan] || ' '
          x = label_width + i * cell_width
          color = case status
                  when 'f' then '#00FF00'  # Зелений
                  when 'b' then '#FFFF00'  # Жовтий
                  when 'e' then '#FF0000'  # Червоний
                  when 'c' then '#FF00FF'  # Фіолетовий
                  when 'a' then '#0000FF'  # Синій
                  when 'u' then '#555555'  # Темно-сірий
                  else 'white'  # Пробіл
                  end
          gc.fill(color)
          gc.rectangle(x, y, x + cell_width - 1, y + cell_height - 1)
          gc.fill('black')
          gc.text(x + 2, y + font_size, status) unless status == ' '
        end
      end

      legend_y = height - 50
      x = 10
      legend_parts = [
        ["Legend: ", nil],
        ["f", '#00FF00'], ["=free", nil], [", ", nil],
        ["b", '#FFFF00'], ["=busy", nil], [", ", nil],
        ["e", '#FF0000'], ["=error", nil], [", ", nil],
        ["c", '#FF00FF'], ["=configured", nil], [", ", nil],
        ["a", '#0000FF'], ["=another", nil], [", ", nil],
        ["u", '#555555'], ["=unused", nil]
      ]
      legend_parts.each do |text, color|
        if color
          gc.fill(color)
          gc.rectangle(x, legend_y - font_size + 2, x + 10, legend_y + 2)
          gc.fill('black')
          gc.text(x + 2, legend_y, text)
          x += 12
        else
          gc.fill('black')
          gc.text(x, legend_y, text)
          x += text.length * 8
        end
      end

      summary_y = height - 30
      x = 10
      summary_parts = [
        ["Total: ", nil],
        ["f", '#00FF00'], ["=#{status_counts['f']}", nil], [", ", nil],
        ["b", '#FFFF00'], ["=#{status_counts['b']}", nil], [", ", nil],
        ["e", '#FF0000'], ["=#{status_counts['e']}", nil], [", ", nil],
        ["c", '#FF00FF'], ["=#{status_counts['c']}", nil], [", ", nil],
        ["a", '#0000FF'], ["=#{status_counts['a']}", nil], [", ", nil],
        ["u", '#555555'], ["=#{status_counts['u']}", nil]
      ]
      summary_parts.each do |text, color|
        if color
          gc.fill(color)
          gc.rectangle(x, summary_y - font_size + 2, x + 10, summary_y + 2)
          gc.fill('black')
          gc.text(x + 2, summary_y, text)
          x += 12
        else
          gc.fill('black')
          gc.text(x, summary_y, text)
          x += text.length * 8
        end
      end

      gc.draw(canvas)
      FileUtils.mkdir_p(path) unless Dir.exist?(path)
      filename = File.join(path, "free-range-#{target}#{interface ? "-#{interface.tr('/', '-')}" : ''}.png")
      canvas.write(filename)
      puts "Зображення збережено: #{filename}"
    end

    private

    # Будує хеш статусів VLAN і підраховує кількість кожного статусу
    # @param ranges [Ranges] Object containing VLAN ranges
    # @param vlans [Vlans] Object containing VLANs
    # @return [Array<Hash, Hash>] Hash of VLAN statuses and status counts
    def self.build_vlan_statuses(ranges, vlans)
      all_vlans = {}
      ranges.ranges.each do |start, finish|
        (start..finish).each { |vlan| all_vlans[vlan] = 'f' }
      end
      vlans.vlans.uniq.each { |vlan| all_vlans[vlan] = all_vlans.key?(vlan) ? 'b' : 'e' }
      (1..4094).each { |vlan| all_vlans[vlan] = 'u' unless all_vlans.key?(vlan) }
      ranges.another_in_ranges.each { |vlan| all_vlans[vlan] = all_vlans.key?(vlan) && all_vlans[vlan] != 'u' ? 'c' : 'a' }
      status_counts = { 'f' => 0, 'b' => 0, 'e' => 0, 'c' => 0, 'a' => 0, 'u' => 0 }
      all_vlans.each_value { |status| status_counts[status] += 1 }

      [all_vlans, status_counts]
    end

    # Форматує діапазон VLAN зі статусом для виводу
    # @param start [Integer] Start of VLAN range
    # @param finish [Integer] End of VLAN range
    # @param status [String] VLAN status ('f', 'b', 'e', 'c', 'a', 'u')
    # @param use_color [Boolean] Enable colored output
    # @return [String] Formatted range string
    def self.format_range(start, finish, status, use_color)
      range_text = start == finish ? "#{start}" : "#{start}-#{finish}"
      range_text_with_status = "#{range_text}(#{status})"
      if use_color
        case status
        when 'f' then "\e[32m#{range_text}\e[0m"  # Зелений для free
        when 'b' then "\e[33m#{range_text}\e[0m"  # Жовтий для busy
        when 'e' then "\e[31m#{range_text}\e[0m"  # Червоний для error
        when 'c' then "\e[35m#{range_text}\e[0m"  # Фіолетовий для configured
        when 'a' then "\e[34m#{range_text}\e[0m"  # Синій для another
        when 'u' then "\e[90m#{range_text}\e[0m"  # Темно-сірий для unused
        else range_text  # Без кольору для інших статусів
        end
      else
        range_text_with_status  # Текстовий вивід зі статусами
      end
    end

    # Форматує символ для таблиці VLAN
    # @param status [String] VLAN status ('f', 'b', 'e', 'c', 'a', 'u', or ' ')
    # @param use_color [Boolean] Enable colored output
    # @return [String] Formatted character for table display
    def self.format_table_char(status, use_color)
      if use_color
        case status
        when 'f' then "\e[48;5;2m\e[30m#{status}\e[0m"  # Зелений фон, чорний текст
        when 'b' then "\e[48;5;3m\e[30m#{status}\e[0m"  # Жовтий фон, чорний текст
        when 'e' then "\e[48;5;1m\e[30m#{status}\e[0m"  # Червоний фон, чорний текст
        when 'c' then "\e[48;5;5m\e[30m#{status}\e[0m"  # Фіолетовий фон, чорний текст
        when 'a' then "\e[48;5;4m\e[30m#{status}\e[0m"  # Синій фон, чорний текст
        when 'u' then "\e[48;5;8m\e[30m#{status}\e[0m"  # Темно-сірий фон, чорний текст
        else status  # Без кольору для інших статусів
        end
      else
        status  # Текстовий вивід без кольорів
      end
    end
  end

  # Метод для заповнення Ranges для одного інтерфейсу
  # @param interface [String, nil] Interface name or nil for all interfaces
  # @param ranges [Ranges] Object to store VLAN ranges
  # @return [void]
  def process_interface(interface, ranges)
    full_cmd = "#{@config.ssh_command} '#{@config.command_ranges(interface)}'"
    puts "[DEBUG] Executing command: #{full_cmd}" if @debug
    result = `#{full_cmd}`.strip
    unless result.empty?
      result.each_line do |line|
        if line =~ /ranges (\d+)(?:-(\d+))?/
          start_range = $1.to_i
          end_range = $2 ? $2.to_i : $1.to_i
          ranges.add_range(start_range, end_range)
        end
      end
    end

    full_cmd = "#{@config.ssh_command} '#{@config.command_demux(interface)}'"
    puts "[DEBUG] Executing command: #{full_cmd}" if @debug
    result = `#{full_cmd}`.strip
    unless result.empty?
      result.each_line do |line|
        if line =~ /unit (\d+)/
          start_range = $1.to_i
          if start_range > 0
            end_range = start_range
            ranges.add_range(start_range, end_range)
          end
        end
      end
    end

    full_cmd = "#{@config.ssh_command} '#{@config.command_another(interface)}'"
    puts "[DEBUG] Executing command: #{full_cmd}" if @debug
    result = `#{full_cmd}`.strip
    unless result.empty?
      result.each_line do |line|
        if line =~ /vlan-id (\d+)/
          start_range = $1.to_i
          if start_range > 0
            end_range = start_range
            ranges.add_another_range(start_range, end_range)
          end
        end
      end
    end
  end

  # Обробляє VLAN для інтерфейсу та виводить результати
  # @param interface [String, nil] Interface name or nil for all interfaces
  # @return [void]
  def process_and_output(interface)
    ranges = Ranges.new
    vlans = Vlans.new
    @subscribers_result.each_line do |line|
      if line.split.first =~ /dhcp(?:_[0-9a-fA-F.]+)?_([^:]+):(\d+)@#{Regexp.escape(@target)}$/
        subscriber_interface, vlan = $1, $2.to_i
        if interface
          vlans.add_vlan(vlan) if subscriber_interface == interface && vlan > 0
        else
          vlans.add_vlan(vlan) if vlan > 0
        end
      end
    end

    process_interface(interface, ranges)
    if @debug
      puts "\nІнтерфейс: #{interface}" if interface
      Print.ranged(ranges)
      Print.vlans(vlans)
      Print.vlan_ranges(vlans)
      puts
    end
    if @table_png_mode
      Print.table_png(ranges, vlans, @table_png_mode, @target, interface)
    elsif @table_mode
      Print.table(ranges, vlans, @use_color, @target, interface)
    else
      Print.combined_ranges(ranges, vlans, @use_color, @target, interface)
    end
  end

  # Ініціалізує об’єкт FreeRange із параметрами
  def initialize
    @config = nil
    @subscribers_result = nil
    @target = nil
    @use_color = false
    @debug = false
    @table_mode = false
    @table_png_mode = nil

    options = {}
    OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Використання: free-range <IP-адреса або hostname> [опції]

        Аналізує розподіл VLAN на мережевих пристроях, генеруючи таблиці або PNG-зображення.
      BANNER
      opts.on("-h", "--help", "Показати цю довідку") { puts opts; exit 0 }
      opts.on("-u", "--username USERNAME", "Ім'я користувача для SSH") { |u| options[:username] = u }
      opts.on("-p", "--password PASSWORD", "Пароль для SSH") { |p| options[:password] = p }
      opts.on("-n", "--no-color", "Вимкнути кольоровий вивід") { options[:no_color] = true }
      opts.on("-d", "--debug", "Увімкнути дебаг-режим") { options[:debug] = true }
      opts.on("-t", "--table", "Вивести діаграму розподілу VLAN-ів") { options[:table] = true }
      opts.on("-g", "--table-png PATH", "Зберегти діаграму розподілу VLAN-ів як PNG") { |path| options[:table_png] = path }
      opts.on("-i", "--interface INTERFACE", "Назва інтерфейсу або 'all'") { |i| options[:interface] = i }
      opts.on("-c", "--config CONFIG_FILE", "Шлях до конфігураційного файлу") { |c| options[:config_file] = c }
    end.parse!

    if ARGV.empty?
      puts "Помилка: потрібно вказати IP-адресу або hostname роутера."
      puts "Використовуйте: free-range --help для довідки."
      exit 1
    end

    # Ініціалізуємо змінні екземпляра
    @use_color = !options[:no_color] && ENV['TERM'] && ENV['TERM'] != 'dumb'
    @debug = options[:debug]
    @table_mode = options[:table]
    @table_png_mode = options[:table_png]
    interface = options[:interface]
    config_file = options[:config_file]

    # Ініціалізуємо config з порожнім login
    @config = Config.new({ target: ARGV[0], username: nil, password: nil })

    # Завантажуємо конфігураційний файл, якщо він вказаний
    if config_file
      begin
        # Виконуємо конфігураційний файл у контексті існуючого об’єкта config
        @config.instance_eval(File.read(config_file), config_file)
      rescue LoadError, Errno::ENOENT
        puts "Помилка: неможливо завантажити конфігураційний файл '#{config_file}'."
        exit 1
      rescue ArgumentError => e
        puts "Помилка в аргументах конфігураційного файлу '#{config_file}': #{e.message}"
        exit 1
      rescue StandardError => e
        puts "Помилка в конфігураційному файлі '#{config_file}': #{e.message}"
        exit 1
      end
    end

    # Визначаємо username і password з пріоритетом: аргументи > config > ENV
    username = options[:username] || @config.username || ENV['WHOAMI']
    password = options[:password] || @config.password || ENV['WHATISMYPASSWD']

    if username.nil? || password.nil?
      puts "Помилка: необхідно вказати ім'я користувача та пароль."
      puts "Використовуйте опції -u/--username і -p/--password, конфігураційний файл або змінні оточення WHOAMI і WHATISMYPASSWD."
      exit 1
    end

    login = { target: ARGV[0], username: username, password: password }
    @target = ARGV[0].split('.')[0]
    puts "Connecting to device: #{login[:target]}"

    # Оновлюємо config з актуальними login даними
    @config = Config.new(login) { |c|
      c.username = @config.username if @config.username
      c.password = @config.password if @config.password
    }

    if @debug
      puts "[DEBUG] Values:"
      puts "[DEBUG] use_color: #{@use_color}"
      puts "[DEBUG] table_mode: #{@table_mode}"
      puts "[DEBUG] table_png_mode: #{@table_png_mode}"
      puts "[DEBUG] interface: #{interface}"
      puts "[DEBUG] ARGV[0]: #{ARGV[0]}"
      puts "[DEBUG] target: #{@target}"
      puts "[DEBUG] login: #{login}"
      puts "[DEBUG] config_file: #{config_file}"
      puts "[DEBUG] config.username: #{@config.username}"
      puts "[DEBUG] config.password: #{@config.password}"
      puts "[DEBUG] config.ssh_command: #{@config.ssh_command}"
      puts "[DEBUG] config.subscribers_command: #{@config.subscribers_command}"
      puts "[DEBUG] config.command_interfaces: #{@config.command_interfaces}"
    end

    @subscribers_result = `#{@config.subscribers_command}`.strip
    if @subscribers_result.empty?
      puts "Помилка: результат subscribers_command порожній. Перевір шлях або доступ."
      exit 1
    end

    if interface == "all"
      full_cmd = "#{@config.ssh_command} '#{@config.command_interfaces}'"
      puts "[DEBUG] Executing command: #{full_cmd}" if @debug
      result = `#{full_cmd}`.strip
      if result.empty?
        puts "Помилка: результат команди порожній. Перевір підключення або команду."
        exit 1
      end

      interfaces = result.each_line.map { |line| line.split[2] }.uniq
      if interfaces.empty?
        puts "Помилка: не знайдено інтерфейсів із діапазонами."
        exit 1
      end

      interfaces.each do |intf|
        process_and_output(intf)
      end
    else
      process_and_output(interface)
    end
  end

  # Основна логіка виконання
  # @return [void]
  def self.run
    new
  end
end
