# DNSimple Importer
# 2013 - Leon Miller-Out @ Singlebrook.com

require 'rubygems'
require 'dnsimple'

DnsRecord = Struct.new(:host, :type, :priority, :value, :ttl)

class DNSimpleImporter
  attr_reader :filename, :sections, :domain, :creds

  def initialize(args)
    die(usage) unless args.length == 2
    @filename = args[0]
    @domain = args[1]
    parse_creds
  end

  def run
    parse_file
    merge_sections
    toss_unwanted_records
    #output_zone
    upload_records
  end

  def usage
    usage =<<-EOF
      DNSimple importer - for bulk loading of records into a new domain

      Usage: bundle exec ruby dnsimple_importer.rb filename domain

      File structure (based on copy-and-paste from Hosting.com control panel)
        SECTION: singlebrook.com
        vps  A   208.112.1.158   3600
        intranet   CNAME   sb-intranet.heroku.com  3600
        singlebrook.com  NS  ns1.lnhi.net  3600
        singlebrook.com  A   75.101.163.44   3600
        www  CNAME   singlebrook.com   3600
        singlebrook.com  MX (1)  aspmx.l.google.com  3600
        SECTION: subdomain.singlebrook.com
        shmoo  CNAME  singlebrook.com  600
    EOF
    usage.gsub(/^\s{6}/, '')
  end

  private

  def die(text)
    puts text
    exit 1
  end

  def merge_sections
    @records = []
    @sections.each do |subdomain, records|
      records.each do |record|
        record.host = "#{record.host}.#{subdomain}" unless record.host.include? subdomain
        record.host = record.host.gsub(/.singlebrook.com\Z/, '')
        record.host = '@' if record.host == 'singlebrook.com'
        @records << record
      end
    end
  end

  def output_zone
    puts @records
  end

  def parse_creds
    @creds = YAML.load(File.open('/Users/leon/.dnsimple')).to_hash
    die('Could not find username in ~/.dnsimple') unless @creds['username']
    die('Could not find api_token in ~/.dnsimple') unless @creds['api_token']
  end

  def parse_file
    read_file_into_sections
    parse_sections
  end

  def parse_records(strings)
    strings.map do |string|
      matches = string.match %r{
        \A
        (?<host>.+?)(\s{2,})
        (?<type>[A-Z]+?)
        (\s\((?<priority>\d+)\))?
        (\s{2,})
        (?<value>.+?)(\s{2,})
        (?<ttl>\d+)(\s)?
      }x
      raise "Could not parse string (#{string})" unless matches
      DnsRecord.new(matches[:host], matches[:type], matches[:priority], matches[:value], matches[:ttl])
    end
  end

  def parse_sections
    @sections.each do |subdomain, strings|
      @sections[subdomain] = parse_records(strings)
    end
  end

  def read_file_into_sections
    @sections = {}
    current_subdomain = nil
    File.open(@filename).each_line do |line|
      matches = line.match /\ASECTION: (?<subdomain>.*)\Z/
      if matches
        current_subdomain = matches[:subdomain]
        sections[current_subdomain] = []
      else
        sections[current_subdomain] << line
      end
    end
  end

  def toss_unwanted_records
    @records.reject! {|record| record.type == "NS"}
  end

  def upload_records
    DNSimple::Client.username = creds['username']
    DNSimple::Client.api_token = creds['api_token']
    puts "Loading domain #{domain}"
    ds_domain = DNSimple::Domain.find(domain)
    @records.each do |record|
      puts "Uploading #{record.type} record for #{record.host}"
      DNSimple::Record.create(
        ds_domain,
        record.host,
        record.type,
        record.value,
        ttl: record.ttl,
        prio: record.priority,
      )
    end
  end

end

DNSimpleImporter.new(ARGV).run