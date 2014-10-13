
$canvas_databases = ['canvas_development',
                    'canvas_queue_development',
                    'canvas_test'
                    ]

$ruby_packages = ['ruby1.9.1',
                  'ruby1.9.1-dev',
                  'zlib1g-dev',
                  'rake',
                  'rubygems1.9.1',
                  'irb',
                  'libhttpclient-ruby',
                  'libsqlite3-dev',
                  'imagemagick',
                  'irb1.9.1' ,
                  'python-software-properties'
                  ]

$canvas_env_vars = ['CANVAS_LMS_ADMIN_EMAIL=admin@example.com',
                    'CANVAS_LMS_ADMIN_PASSWORD=password',
                    'CANVAS_LMS_STATS_COLLECTION=1',
                    'CANVAS_LMS_ACCOUNT_NAME=Test'
                    ]

# Make sure apt-get -y update runs before anything else.
stage { 'preinstall': before => Stage['main'] }
stage { 'canvas_setup': require => Stage['main'] }
stage { 'canvas_bundle': require => Stage['canvas_setup'] }

class apt_get_update {
  exec { '/usr/bin/apt-get -y update':
    user => 'root'
  }
}
class { 'apt_get_update':
  stage => preinstall
}

class install_postgres {
  class { 'postgresql': }

  class { 'postgresql::server': }

  pg_user { 'vagrant':
    ensure    => present,
    superuser => true,
    require   => Class['postgresql::server']
  }

  pg_user { 'canvas':
    ensure   => present,
    password => 'canvas',
    require  => Class['postgresql::server']
  }

  pg_database { $::canvas_databases:
    ensure   => present,
    owner    => 'canvas',
    encoding => 'UTF8',
    require  => [Class['postgresql::server'], Pg_user['canvas']]
  }

  package { 'libpq-dev':
    ensure => installed
  }
}
class { 'install_postgres': }

class install_core_packages {
  package { ['build-essential', 'git-core'] :
    ensure => installed
  }
}
class { 'install_core_packages': }

class install_ruby {
  package {$::ruby_packages:
    ensure => installed
  }

  exec { '/usr/bin/update-alternatives --set ruby /usr/bin/ruby1.9.1':
    user    => 'root',
    require => Package['ruby1.9.1'],
    before  => Exec['/usr/bin/gem install bundler -v 1.5.2']
  }

  exec { '/usr/bin/update-alternatives --set gem /usr/bin/gem1.9.1':
    user    => 'root',
    require => Package['rubygems1.9.1'],
    before  => Exec['/usr/bin/gem install bundler -v 1.5.2']
  }

  exec { '/usr/bin/gem install bundler -v 1.5.2':
    unless  => '/usr/bin/gem list | grep bundler',
    user    => 'root',
    require => Package['rubygems1.9.1']
  }
}
class { 'install_ruby': }

class install_nokogiri_dependencies {
  package { ['libxml2', 'libxml2-dev', 'libxslt1-dev']:
    ensure => installed
  }
}
class { 'install_nokogiri_dependencies': }

class install_libxmlsec_dependencies {
  package { [libxmlsec1-dev]:
    ensure => installed
  }
}
class { 'install_libxmlsec_dependencies': }

# Required for typheous gem
class install_curl_dependencies {
  package { ['curl', 'libcurl3-dev']:
    ensure => installed
  }
}
class { 'install_curl_dependencies': }

class install_js_dependencies {
  include apt
  apt::ppa{'ppa:chris-lea/node.js':}
  package { ['nodejs', 'coffeescript']:
    ensure  => installed,
    require => Apt::Ppa['ppa:chris-lea/node.js']
  }
}
class { 'install_js_dependencies': }

class setup_canvas_configs {
  exec { 'copy_configs' :
    cwd     => '/vagrant/canvas-lms',
    command => '/bin/bash -c "for config in amazon_s3 delayed_jobs domain file_store outgoing_mail security scribd external_migration; do cp config/\$config.yml.example config/\$config.yml; done"',
    path    => '/bin'
  }
}
class { 'setup_canvas_configs': stage => canvas_setup }

class setup_canvas_db_config {
  file { '/vagrant/canvas-lms/config/database.yml':
    ensure => present,
    source => 'puppet:///modules/canvas/database.yml';
  }
}
class { 'setup_canvas_db_config': stage => canvas_setup }

class setup_canvas_bundle {
  notify{'Installing canvas gem dependencies... This can take a few minutes.':}
  exec { 'bundle_install' :
    cwd     => '/vagrant/canvas-lms',
    command => 'bundle install --without mysql',
    path    => ['/bin', '/usr/bin', '/usr/local/bin'],
    timeout => 0,
  }

  exec{'npm install':
    cwd     => '/vagrant/canvas-lms',
    command => 'npm install',
    path    => ['/bin', '/usr/bin', '/usr/local/bin'],
    timeout => 0
  }

  exec{'initializing DB':
    cwd         => '/vagrant/canvas-lms',
    command     => 'bundle exec rake db:initial_setup',
    path        => ['/bin', '/usr/bin', '/usr/local/bin'],
    environment => $::canvas_env_vars,
    timeout     => 0,
    require     => Exec['bundle_install']
  }

  exec{'compile assets':
    cwd     => '/vagrant/canvas-lms',
    command => 'bundle exec rake canvas:compile_assets',
    path    => ['/bin', '/usr/bin', '/usr/local/bin'],
    timeout => 0,
    require => [Exec['bundle_install'], Exec['initializing DB']]
  }
  
  notify{"Login Creds : email => $::canvas_env_vars["CANVAS_LMS_ADMIN_PASSWORD"] , Password => $::canvas_env_vars["CANVAS_LMS_ADMIN_PASSWORD"]":
  }

  exec{'start server':
    cwd     => '/vagrant/canvas-lms',
    command => 'bundle exec rails server -d',
    path    => ['/bin', '/usr/bin', '/usr/local/bin'],
    timeout => 0,
    require => Exec['compile assets']
  }
}
class { 'setup_canvas_bundle': stage => canvas_bundle }
