# frozen_string_literal: true

require 'spec_helper'

describe 'r11k::hook' do
  let(:pre_condition) { 'include r11k' }
  let(:title) { 'default' }
  let(:params) { { hook_content: 'foobar' } }

  context 'with defaults' do
    it do
      is_expected.to contain_file('/etc/r11k/hooks.d/default').with_content('foobar').with_ensure('file')
    end
  end

  context 'env hook' do
    let(:params) { super().merge(env_hook: true) }

    it do
      is_expected.to contain_file('/etc/r11k/env.hooks.d/default').with_content('foobar').with_ensure('file')
    end
  end

  context 'config file' do
    let(:params) do
      super().merge(
        config_file: '/etc/r11k/config/foobar.yaml',
        config_source: 'puppet:///modules/foobar/config.yaml',
      )
    end

    it do
      is_expected.to contain_file('/etc/r11k/config/foobar.yaml')
        .with_ensure('file')
        .with_source('puppet:///modules/foobar/config.yaml')
        .with_before('File[/etc/r11k/hooks.d/default]')
    end
  end

  context 'with ensure => "absent"' do
    let(:params) do
      super().merge(
        ensure: 'absent',
        config_file: '/etc/r11k/config/foobar.yaml',
      )
    end

    it do
      is_expected.to contain_file('/etc/r11k/hooks.d/default').with_ensure('absent')
    end
    it do
      is_expected.to contain_file('/etc/r11k/config/foobar.yaml').with_ensure('absent')
    end
  end

  context 'parameter validation' do
    describe 'hook missing content or source' do
      let(:params) { super().merge(hook_content: :undef) }

      it { is_expected.to compile.and_raise_error(%r{either the content or the source of the hook}) }
    end

    describe 'hook both content and source' do
      let(:params) { super().merge(hook_source: 'puppet:///modules/foobar/default.sh') }

      it { is_expected.to compile.and_raise_error(%r{either the content or the source of the hook. Not both}) }
    end

    describe 'config missing content or source' do
      let(:params) { super().merge(config_file: '/etc/r11k/config/foobar.yaml') }

      it { is_expected.to compile.and_raise_error(%r{config file, you must provide either the source or the content}) }
    end

    describe 'config both content and source' do
      let(:params) do
        super().merge(
          config_file: '/etc/r11k/config/foobar.yaml',
          config_source: 'puppet:///modules/foobar/config.yaml',
          config_content: '---\nfoo',
        )
      end

      it { is_expected.to compile.and_raise_error(%r{config file, you must provide either the source or the content. Not both}) }
    end
  end

  context 'hook_dependencies' do
    let(:dependencies) do
      {
        'barfoo' => {},
        'xfoo' => :undef,
        'foobar' => { 'ensure' => 'latest' },
      }
    end

    let(:params) do
      super().merge(
        hook_dependencies: dependencies,
      )
    end

    it { is_expected.to contain_package('barfoo').with_ensure('installed') }
    it { is_expected.to contain_package('xfoo').with_ensure('installed') }
    it { is_expected.to contain_package('foobar').with_ensure('latest') }
  end
end
