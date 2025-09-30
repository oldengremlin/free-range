# FreeRange

A Ruby gem to analyze VLAN distribution on network devices, generating tables or PNG images.

## Installation

### Debian/Ubuntu
1. Install dependencies:
   ```bash
   sudo apt install ruby ruby-dev imagemagick libmagickcore-dev libmagickwand-dev sshpass
   sudo gem install rmagick
   ```
2. Install the gem:
   ```bash
   sudo gem install free-range
   ```
   or
   ```bash
   gem install free-range -v 0.2.0
   ```

### Windows
1. Install Ruby using RubyInstaller: https://rubyinstaller.org/ (choose Ruby+Devkit 3.1.x).
2. Install ImageMagick: https://imagemagick.org/script/download.php#windows (enable "Install legacy components").
3. Install `sshpass` via:
   - **Cygwin**: Download from https://www.cygwin.com/, select the `sshpass` package, and add Cygwin’s `bin` to PATH.
   - **WSL**: Run `wsl --install`, then in Ubuntu: `sudo apt install sshpass`.
4. Install the gem:
   ```cmd
   gem install free-range -v 0.2.0
   ```

## Usage
```bash
free-range <IP-or-hostname> [-u username] [-p password] [-n] [-d] [-t] [-g path] [-i interface] [-c config_file]
```

### Options
- `-h, --help`: Display this help message.
- `-u, --username USERNAME`: SSH username (overrides config file and `WHOAMI` environment variable).
- `-p, --password PASSWORD`: SSH password (overrides config file and `WHATISMYPASSWD` environment variable).
- `-n, --no-color`: Disable colored output.
- `-d, --debug`: Enable debug mode.
- `-t, --table`: Display VLAN distribution table.
- `-g, --table-png PATH`: Save VLAN distribution as a PNG image to the specified path.
- `-i, --interface INTERFACE`: Interface name (e.g., `xe-0/0/2`, `ps0`, `ae1`, `irb`) or `all`.
- `-c, --config CONFIG_FILE`: Path to a Ruby configuration file.

### Configuration File
You can specify custom commands and credentials in a Ruby configuration file (e.g., `config.rb`):
```ruby
# Конфігурація для FreeRange::Config
self.username = "korystuvach"
self.password = "abrakadabra"
define_singleton_method(:ssh_command) do
  "sshpass -p \"#{@login[:password]}\" ssh -C -x -4 -o StrictHostKeyChecking=no #{@login[:username]}@#{@login[:target]}"
end
define_singleton_method(:subscribers_command) do
  "/path/to/custom/radius-subscribers"
end
define_singleton_method(:command_interfaces) do
  'show configuration interfaces | no-more | display set | match dynamic-profile'
end
define_singleton_method(:command_ranges) do |interface = nil|
  interface ? "show configuration interfaces #{interface} | no-more | display set | match ranges" : 'show configuration interfaces | no-more | display set | match ranges'
end
define_singleton_method(:command_demux) do |interface = nil|
  interface ? "show configuration interfaces #{interface} | display set | match demux" : 'show configuration interfaces | display set | match demux'
end
define_singleton_method(:command_another) do |interface = nil|
  interface ? "show configuration interfaces #{interface} | display set | match vlan" : 'show configuration interfaces | display set | match vlan'
end
```

### Examples
```bash
free-range rhoh15-1.ukrhub.net -u korystuvach -p abrakadabra
free-range rhoh15-1.ukrhub.net -u korystuvach -p abrakadabra -t
free-range rhoh15-1.ukrhub.net -u korystuvach -p abrakadabra -g ./output -i xe-0/0/2
free-range rhoh15-1.ukrhub.net -u korystuvach -p abrakadabra -d -i all
free-range rhoh15-1.ukrhub.net -c config.rb
free-range rhoh15-1.ukrhub.net -c config.rb -t
free-range rhoh15-1.ukrhub.net -c config.rb -g ./output -i xe-0/0/2
free-range rhoh15-1.ukrhub.net -c config.rb -d -i all
```

## Documentation
To generate documentation locally:
```bash
gem install yard
yardoc 'lib/**/*.rb'
```
View the generated documentation in the `doc/` directory (open `doc/index.html` in a browser).

## Prerequisites
- Ensure `/usr/local/share/noc/bin/radius-subscribers` is accessible or provide an alternative script for subscriber data.
- For Windows, ensure `sshpass` is in PATH (via Cygwin or WSL).
- Supported interface names include `xe-0/0/2`, `ps0`, `ae1`, `irb`, etc., or `all` for all interfaces.

## Source Code
Available at: https://github.com/oldengremlin/free-range

## License
Apache-2.0
