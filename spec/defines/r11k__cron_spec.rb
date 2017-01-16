require 'spec_helper'

describe 'r11k::cron' do
  let(:pre_condition) { 'include r11k' }
  context 'defaults' do
    let(:title) { 'default' }
    let(:params) { { 'git_base_repo' => '/path/to/repo' } }

    it do
      is_expected.to contain_cron('r11k::cron: default').with('ensure' => 'present',
                                                              'minute' => '*/4')
    end
  end
  context 'ensure => absent' do
    let(:title) { 'default' }
    let(:params) { { 'ensure' => 'absent', 'git_base_repo' => '' } }
    it do
      is_expected.to contain_cron('r11k::cron: default').with('ensure' => 'absent')
    end
  end
  context 'advanced schedule' do
    let(:title) { 'advanced' }
    let(:params) do
      {
        'git_base_repo' => '/path/to/repo',
        'job' => {
          'minute' => '*/10',
          'hour' => ['2-4']
        }
      }
    end

    it do
      is_expected.to contain_cron('r11k::cron: advanced').with('minute' => '*/10',
                                                               'hour' => ['2-4'])
    end
  end
  context 'allowed branch include parameter' do
    [
      'production',
      nil,
      ['production', 'features/.*']
    ].each do |incl|
      describe "includes is a #{incl.class}" do
        let(:title) { 'default' }
        let(:params) do
          {
            'git_base_repo' => '/path/to/repo',
            'includes' => incl
          }
        end
        it do
          is_expected.to contain_cron('r11k::cron: default')
        end
      end
    end
  end
  context 'r11k command line' do
    let(:prefix) { %w(/usr/local/bin/r11k) }
    let(:suffix) { %w(/local) }
    let(:title) { 'default' }
    let(:default_params) { { 'git_base_repo' => '/local' } }
    {
      '--basedir /etc/puppetlabs/code/environments --no-wait --hooksdir /etc/r11k/hooks.d' => {
        # use all defaults.
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d' => {
        'basedir' => '/environments'
      },
      '--basedir /environments --no-wait --cachedir /tmp/cache --hooksdir /etc/r11k/hooks.d' => {
        'basedir'  => '/environments',
        'cachedir' => '/tmp/cache'
      },
      '--basedir /environments --no-wait --cachedir /tmp/cache --hooksdir /etc/hooksdir' => {
        'basedir' => '/environments',
        'cachedir' => '/tmp/cache',
        'hooksdir' => '/etc/hooksdir'
      },
      '--basedir /environments --no-wait --hooksdir /etc/hooksdir' => {
        'basedir' => '/environments',
        'hooksdir' => '/etc/hooksdir'
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d --include production' => {
        'basedir' => '/environments',
        'includes' => 'production'
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d --include production:puppet/.\\*' => {
        'basedir' => '/environments',
        'includes' => ['production', 'puppet/.*']
      },
      '--basedir /path\\ with/spaces/ --no-wait --hooksdir /etc/r11k/hooks.d' => {
        'basedir' => '/path with/spaces/'
      }
    }.each do |cmd, params|
      describe "expected result command: '#{cmd}'" do
        let(:params) { default_params.merge(params) }
        it 'matches' do
          is_expected.to contain_cron('r11k::cron: default').with_command([prefix, cmd, suffix].join(' '))
        end
      end
    end
  end
end
