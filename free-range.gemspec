Gem::Specification.new do |s|
  s.name        = 'free-range'
  s.version     = '0.2.1'
  s.summary     = 'VLAN distribution analysis tool'
  s.description = 'A Ruby script to analyze VLAN distribution on network devices, generating tables or PNG images.'
  s.authors     = ['Oleksandr Russkikh //aka Olden Gremlin']
  s.email       = 'olden@ukr-com.net'
  s.files       = Dir['lib/**/*', 'bin/**/*']
  s.executables = ['free-range']
  s.homepage    = 'https://github.com/oldengremlin/free-range'
  s.license     = 'Apache-2.0'

  s.add_dependency 'rmagick', '~> 5.3'
  s.add_development_dependency 'bundler', '~> 2.0'
  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'yard', '~> 0.9'
end
