#!/usr/bin/ruby
=begin
  lib/gettext_activerecord/parser.rb - parser for ActiveRecord

  Copyright (C) 2005-2009  Masao Mutoh
 
  You may redistribute it and/or modify it under the same
  license terms as Ruby.

  $Id$
=end

require 'gettext'
require 'gettext/tools/rgettext'
require 'gettext/parser/ruby'

include GetText

ActiveRecord::Base.instance_eval do
  alias inherited_without_log inherited

  @@active_record_classes_list = []

  def inherited(subclass)
    puts "registering an ActiveRecord model for later processing: #{subclass}"
    active_record_classes_list << "#{subclass}"
    inherited_without_log(subclass)
  end

  def active_record_classes_list
    @@active_record_classes_list
  end

  def reset_active_record_classes_list
    @@active_record_classes_list = []
  end
end

module GetText
  module ActiveRecordParser
    extend GetText
    include GetText
    bindtextdomain "gettext_activerecord"

    @config = {
      :db_yml => "config/database.yml",
      :db_mode => "development",
      :activerecord_classes => ["ActiveRecord::Base"],
      :untranslate_columns => ["id"],
      :use_classname => true,
    }

    @ar_re = nil

    module_function
    def require_rails(file) # :nodoc:
      begin
	require file
      rescue MissingSourceFile
	$stderr.puts _("'%{file}' is not found.") % {:file => file}
      end
    end

    # Sets some preferences to parse ActiveRecord files.
    #
    # * config: a Hash of the config. It can takes some values below:
    #   * :use_classname - If true, the msgids of ActiveRecord become "ClassName|FieldName" (e.g. "Article|Title"). Otherwise the ClassName is not used (e.g. "Title"). Default is true.
    #   * :db_yml - the path of database.yml. Default is "config/database.yml".
    #   * :db_mode - the mode of the database. Default is "development"
    #   * :activerecord_classes - an Array of the superclass of the models. The classes should be String value. Default is ["ActiveRecord::Base"]
    #   * :untranslate_columns - an Array of the column names which is ignored as the msgid.
    #   * :adapter - the options for ActiveRecord::Base.establish_connection. If this value is set, :db_yml option is ignored.
    #   * :host - ditto
    #   * :username - ditto
    #   * :password - ditto
    #   * :database - ditto
    #   * :socket - ditto
    #   * :encoding - ditto
    #
    # "ClassName|FieldName" uses GetText.sgettext. So you don't need to translate the left-side of "|". 
    # See <Documents for Translators for more details(http://www.yotabanana.com/hiki/ruby-gettext-translate.html)>.
    def init(config)
      puts "\nconfig: #{config.inspect}\n\n"
      if config
	config.each{|k, v|
	  @config[k] = v
	}
      end
      @ar_re = /class.*(#{@config[:activerecord_classes].join("|")})/
    end

    def untranslate_column?(klass, columnname)
      klass.untranslate?(columnname) || @config[:untranslate_columns].include?(columnname)
    end

    def parse(file, targets = []) # :nodoc:
      puts "parse file #{file}"
      
      GetText.locale = "en"
      old_constants = Object.constants
      begin
        eval(open(file).read, TOPLEVEL_BINDING)
      rescue
        $stderr.puts _("Ignored '%{file}'. Solve dependencies first.") % {:file => file}
        $stderr.puts $! 
      end
      #loaded_constants = Object.constants - old_constants
      loaded_constants = ActiveRecord::Base.active_record_classes_list
      ActiveRecord::Base.reset_active_record_classes_list
      loaded_constants.each do |classname|
	klass = eval(classname, TOPLEVEL_BINDING)
	if klass.is_a?(Class) && klass < ActiveRecord::Base
      puts "processing class #{klass.name}"
	  unless (klass.untranslate_all? || klass.abstract_class?)
	    add_target(targets, file, ::Inflector.singularize(klass.table_name.gsub(/_/, " ")))
	    unless klass.class_name == classname
	      add_target(targets, file, ::Inflector.singularize(classname.gsub(/_/, " ").downcase))
	    end
	    begin
	      klass.columns.each do |column|
		unless untranslate_column?(klass, column.name)
		  if @config[:use_classname]
		    msgid = classname + "|" +  klass.human_attribute_name(column.name)
		  else
		    msgid = klass.human_attribute_name(column.name)
		  end
		  add_target(targets, file, msgid)
		end
	      end
	    rescue
	      $stderr.puts _("No database is available.")
	      $stderr.puts $!
	    end
	  end
	end
      end
      if RubyParser.target?(file)
	targets = RubyParser.parse(file, targets)
      end
      targets.uniq!
      targets
    end

    def add_target(targets, file, msgid) # :nodoc:
      file_lineno = "#{file}:-"
      key_existed = targets.assoc(msgid)
      if key_existed 
        unless targets[targets.index(key_existed)].include?(file_lineno)
	  targets[targets.index(key_existed)] = key_existed << file_lineno
	end
      else
	targets << [msgid, "#{file}:-"]
      end
      targets
    end

    @@db_loaded = nil
    def target?(file) # :nodoc:
      init(nil) unless @ar_re
      data = IO.readlines(file)
      data.each do |v|
	if @ar_re =~ v
	  unless @@db_loaded
	    begin
	      require 'rubygems'
	    rescue LoadError
	      $stderr.puts _("rubygems are not found.") if $DEBUG
	    end
	    begin
	      ENV["RAILS_ENV"] = @config[:db_mode]
	      require 'config/boot.rb'
	      require 'config/environment.rb'
#	      require 'app/controllers/application.rb'
	    rescue LoadError
	      require_rails 'rubygems'
# seems not to work, at least with my rubygems 1.3; is obsolete anyway, remove?
#              if Kernel.respond_to? :gem
                gem 'activerecord'
#              else
#                require_gem 'activerecord'
#              end
	      require_rails 'active_record'
	      require_rails 'gettext/active_record'
	    end
	    if @config[:adapter]
	      ActiveRecord::Base.establish_connection(@config)
	    else
	      begin
		yml = YAML.load(ERB.new(IO.read(@config[:db_yml])).result)
	      rescue
		return false
	      end
	    end
	  end
	  @@db_loaded = true
	  return true
	end
      end
      false
    end
  end
 
  RGetText.add_parser(GetText::ActiveRecordParser)
end
