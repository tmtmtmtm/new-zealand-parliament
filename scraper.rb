#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'combine_popolo_memberships'
require 'csv'
require 'pry'
require 'require_all'
require 'scraped'
require 'scraperwiki'

require_rel 'lib'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

EPTERMS = 'https://raw.githubusercontent.com/everypolitician/everypolitician-data/master/data/New_Zealand/House/sources/morph/terms.csv'
all_terms = CSV.parse(
  open(EPTERMS).read, headers: true, header_converters: :symbol
).map(&:to_h)

WANTED = %w[52].to_set

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
current = 'https://www.parliament.nz/en/mps-and-electorates/members-of-parliament/'
scrape(current => CurrentMembersPage).member_urls.each do |url|
  data = scrape(url => CurrentMemberPage).to_h
  memberships = data.delete(:memberships).map(&:to_h).each { |m| m[:id] = data[:id] }
  combined = CombinePopoloMemberships.combine(id: memberships, term: all_terms)
  current = combined.select { |t| WANTED.include? t[:term].to_s }

  wanted = %i[start_date end_date area party term]
  mems = current.map { |mem| data.merge(mem.keep_if { |k, _v| wanted.include? k }) }
  mems.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']
  warn "No current memberships on #{url}" if mems.empty?

  ScraperWiki.save_sqlite(%i[id term start_date], mems)
  rows = ScraperWiki.select('COUNT(*) AS rows FROM data WHERE id = ?', data[:id]).first['rows']
  warn "Row mismatch for #{data[:id]}: Have #{rows}, expected #{mems.count}" if rows != mems.count
end
