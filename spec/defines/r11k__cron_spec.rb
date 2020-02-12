# frozen_string_literal: true

require 'spec_helper'

describe 'r11k::cron' do
  let(:pre_condition) { 'include r11k' }

  context 'with defaults' do
    let(:title) { 'default' }
    let(:params) { { 'git_base_repo' => '/path/to/repo' } }

    it do
      is_expected.to contain_cron('r11k::cron: default').with('ensure' => 'present',
                                                              'minute' => '*/4')
    end
  end

  context 'with ensure => absent' do
    let(:title) { 'default' }
    let(:params) { { 'ensure' => 'absent', 'git_base_repo' => '' } }

    it do
      is_expected.to contain_cron('r11k::cron: default').with('ensure' => 'absent')
    end
  end

  context 'with advanced schedule' do
    let(:title) { 'advanced' }
    let(:params) do
      {
        'git_base_repo' => '/path/to/repo',
        'job' => {
          'minute' => '*/10',
          'hour' => ['2-4'],
        },
      }
    end

    it do
      is_expected.to contain_cron('r11k::cron: advanced').with('minute' => '*/10',
                                                               'hour' => ['2-4'])
    end
  end

  context 'with allowed branch include parameter' do
    [
      'production',
      nil,
      ['production', 'features/.*'],
    ].each do |incl|
      describe "includes is a #{incl.class}" do
        let(:title) { 'default' }
        let(:params) do
          {
            'git_base_repo' => '/path/to/repo',
            'includes' => incl,
          }
        end

        it do
          is_expected.to contain_cron('r11k::cron: default')
        end
      end
    end
  end

  context 'with r11k command line' do
    let(:prefix) { ['/usr/local/bin/r11k'] }
    let(:suffix) { ['/local'] }
    let(:title) { 'default' }
    let(:default_params) { { 'git_base_repo' => '/local' } }

    {
      '--basedir /etc/puppetlabs/code/environments --no-wait --hooksdir /etc/r11k/hooks.d' => {
        # use all defaults.
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d' => {
        'basedir' => '/environments',
      },
      '--basedir /environments --no-wait --cachedir /tmp/cache --hooksdir /etc/r11k/hooks.d' => {
        'basedir' => '/environments',
        'cachedir' => '/tmp/cache',
      },
      '--basedir /environments --no-wait --cachedir /tmp/cache --hooksdir /etc/hooksdir' => {
        'basedir' => '/environments',
        'cachedir' => '/tmp/cache',
        'hooksdir' => '/etc/hooksdir',
      },
      '--basedir /environments --no-wait --hooksdir /etc/hooksdir' => {
        'basedir' => '/environments',
        'hooksdir' => '/etc/hooksdir',
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d --include production' => {
        'basedir' => '/environments',
        'includes' => 'production',
      },
      '--basedir /environments --no-wait --hooksdir /etc/r11k/hooks.d --include production:puppet/.\\*' => {
        'basedir' => '/environments',
        'includes' => ['production', 'puppet/.*'],
      },
      '--basedir /path\\ with/spaces/ --no-wait --hooksdir /etc/r11k/hooks.d' => {
        'basedir' => '/path with/spaces/',
      },
    }.each do |cmd, params|
      describe "expected result command: '#{cmd}'" do
        let(:params) { default_params.merge(params) }

        it 'matches' do
          is_expected.to contain_cron('r11k::cron: default').with_command([prefix, cmd, suffix].join(' '))
        end
      end
    end

    describe 'with prefix/suffix' do
      let(:params) do
        default_params.merge(
          command_prefix: '/usr/local/bin/wrapper',
          command_suffix: '2>&1',
          includes: ['production', 'puppet/.*'],
        )
      end

      it 'does not escape prefix/suffix' do
        is_expected.to contain_cron('r11k::cron: default').with_command(
          ['/usr/local/bin/wrapper',
           '/usr/local/bin/r11k --basedir /etc/puppetlabs/code/environments --no-wait --hooksdir /etc/r11k/hooks.d',
           '--include production:puppet/.\\*',
           '/local',
           '2>&1'].join(' '),
        )
      end
    end
  end
end
