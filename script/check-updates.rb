#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require "date"
require "net/http"
require_relative "../lib/rbs/shifter"
require_relative "../lib/rbs/shifter/update_check"

def fetch_update_source(url)
  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
    http.get(uri.request_uri)
  end
  unless response.is_a?(Net::HTTPSuccess)
    raise RBS::Shifter::Error, "Cannot fetch #{url}: HTTP #{response.code}"
  end
  response.body
end

begin
  raise RBS::Shifter::Error, "usage: ruby script/check-updates.rb" unless ARGV.empty?

  config = JSON.parse(File.read(File.expand_path("../rules/core.json", __dir__)))
  gem = JSON.parse(fetch_update_source("https://rubygems.org/api/v1/gems/rbs.json"))
  raise RBS::Shifter::Error, "Invalid RubyGems RBS metadata" unless gem.is_a?(Hash)

  releases = YAML.safe_load(fetch_update_source("https://raw.githubusercontent.com/ruby/www.ruby-lang.org/master/_data/releases.yml"), permitted_classes: [Date])
  branches = YAML.safe_load(fetch_update_source("https://raw.githubusercontent.com/ruby/www.ruby-lang.org/master/_data/branches.yml"), permitted_classes: [Date])
  updates = RBS::Shifter::UpdateCheck.new(config: config).check(rbs_version: gem["version"], releases: releases, branches: branches)
  puts JSON.pretty_generate({ "updates" => updates })
  exit(updates.empty? ? 0 : 2)
rescue StandardError => error
  warn "update check failed: #{error.class}: #{error.message}"
  exit 1
end
