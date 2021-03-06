require 'rubygems/dependent/version'
require 'rubygems/dependent/parallel'
require 'rubygems/spec_fetcher'

module Gem
  class Dependent
    def self.find(gem, options={})
      # get all gems
      specs_and_sources = with_changed_gem_source(options[:source]) do
        all_specs_and_sources(:all_versions => options[:all_versions])
      end

      if options[:fetch_limit]
        specs_and_sources = specs_and_sources.first(options[:fetch_limit])
      end

      if options[:progress]
        $stderr.puts "Downloading specs for #{specs_and_sources.size} gems"
      end

      gems_and_dependencies = fetch_all_dependencies(specs_and_sources, options) do
        print_dot if options[:progress]
      end
      $stderr.print "\n" if options[:progress]

      select_dependent(gems_and_dependencies, gem, options)
    end

    private

    def self.fetch_all_dependencies(specs_and_sources, options={})
      parallel = (options[:parallel] || 15)
      Gem::Dependent::Parallel.map(specs_and_sources, :in_processes => parallel) do |spec, source|
        yield if block_given?
        name, version = if Gem::VERSION > "2"
          [spec.name, spec.version]
        else
          spec[0,2]
        end
        dependencies = fetch_dependencies(spec, source, options)
        [name, version, dependencies]
      end
    end

    def self.fetch_dependencies(spec, source, options={})
      begin
        fetcher = Gem::SpecFetcher.fetcher
        if Gem::VERSION > "2"
          source.fetch_spec(spec).dependencies
        else
          fetcher.fetch_spec(spec, URI.parse(source)).dependencies
        end
      rescue Object => e
        $stderr.puts e unless options[:all_versions]
        []
      end
    end

    def self.select_dependent(gems_and_dependencies, gem, options={})
      accepted_types = (options[:type] || [:development, :runtime])
      gems_and_dependencies.map do |name, version, dependencies|
        matching_dependencies = dependencies.select{|d| d.name == gem && accepted_types.include?(d.type) } rescue []
        next if matching_dependencies.empty?
        [name, version, matching_dependencies]
      end.compact
    end

    def self.print_dot
      $stderr.print '.'
      $stderr.flush if rand(20) == 0 # make progress visible
    end

    def self.all_specs_and_sources(options={})
      fetcher = Gem::SpecFetcher.fetcher
      all = true
      matching_platform = false
      prerelease = false
      matcher = without_deprecation_warning { Gem::Dependency.new(//, Gem::Requirement.default) } # any name, any version
      specs_and_sources = if Gem::VERSION > "2"
        fetcher.search_for_dependency(matcher, matching_platform).first
      else
        fetcher.find_matching matcher, all, matching_platform, prerelease
      end

      if options[:all_versions]
        specs_and_sources
      else
        uniq_by(specs_and_sources){|a| Gem::VERSION > "2" ? a.first.name : a.first.first }
      end
    end

    def self.without_deprecation_warning(&block)
      previous = Gem::Deprecate.skip
      Gem::Deprecate.skip = true
      yield
    ensure
      Gem::Deprecate.skip = previous
    end

    # get unique elements from an array (last found is used)
    # http://drawohara.com/post/146659159/ruby-enumerable-uniq-by
    def self.uniq_by(array, &block)
      uniq = {}
      array.each_with_index do |val, idx|
        key = block.call(val)
        uniq[key] = [idx, val]
      end
      values = uniq.values
      values.sort!{|a,b| a.first <=> b.first}
      values.map!{|pair| pair.last}
      values
    end

    def self.with_changed_gem_source(sources)
      sources = [*sources].compact
      if sources.empty?
        yield
      else
        begin
          old = Gem.sources
          Gem.sources = sources
          yield
        ensure
          Gem.sources = old
        end
      end
    end
  end
end
