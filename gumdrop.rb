#! /usr/bin/ruby

require 'bundler/setup'
require 'json'
require 'yaml'
require 'redcarpet'
require 'handlebars'
require 'fileutils'
require 'optparse'

@handlebars = Handlebars::Context.new

renderer = Redcarpet::Render::HTML.new
@markdown = Redcarpet::Markdown.new renderer

YAML::add_builtin_type('markdown') do |type, text|
	proc{ |*args| Handlebars::SafeString.new(@markdown.render(text)) }
end

def build_hash_from_file(processors, file)
	ext = File.extname(file).reverse.chomp(".").reverse

	if processors[ext]
		return processors[ext].call(file)
	end
	
	case ext
	when "yml", "yaml"
		contents = read_to_string(file)
		YAML.load(contents)
	when "md", "markdown"
		contents = read_to_string(file)
		{
			"content" => proc do |*args|
				Handlebars::SafeString.new(@markdown.render(contents))
			end
		}
	when "rb"
		contents = read_to_string(file)
		eval(contents, nil, File.expand_path(file))
	else
		raise ArgumentError.new("Unsupported type: #{ext}")
	end
end

def build_hash_from_path(processors, path)
	if File.directory? path
		build_hash_from_folder processors, path
	else
		build_hash_from_file processors, path
	end
end

def build_hash_from_name(processors, folder_entries, name)
	entries_with_name = folder_entries.select do |full_name|
		File.basename(full_name, ".*") == name
	end
	
	if entries_with_name.length == 1
		build_hash_from_path(processors, entries_with_name.first)
	else
		out = {}
		entries_with_name.each do |file|
			out.merge! build_hash_from_path(processors, file)
		end
		
		out
	end
end

def build_hash_from_folder(processors, folder_name)
	# The file name that holds all the folder's inherent properties
	# These override properties defined as files
	folder_props_file_name = "index"
	
	all_files = usable_entries(folder_name)
	is_props_file = Proc.new { |file| file == folder_props_file_name }

	all_names = all_files.map { |f| File.basename(f, ".*") }.uniq

	props_file = all_names.select { |f| is_props_file.call f }.first
	names = all_names.select { |f| not is_props_file.call f }

	out = {}
	
	names.each do |name|
		out[name] = build_hash_from_name(processors, all_files, name)
	end

	if not props_file.nil?
		index = build_hash_from_name(processors, all_files, props_file)
		if out == {}
			index
		else
			out.merge index
		end
	else
		out
	end
end

def build_templates_obj_from_folder(folder_name, prefix="")
	out_obj = {}

	usable_entries(folder_name).each do |entry|
		if File.directory? entry
			template_name = File.basename entry
			
			template_set = build_templates_obj_from_folder(
				"#{folder_name}/#{template_name}",
				"#{prefix}#{template_name}/"
			)

			out_obj[template_name] = template_set
			
			out_obj.define_singleton_method(template_name) do ||
				template_set
			end
		elsif ['.hbs', '.handlebars'].include? File.extname(entry)
			template_text = read_to_string entry
			template_compiled = @handlebars.compile template_text

			template_name = File.basename(entry, ".*").to_sym

			@handlebars.register_partial(
				"#{prefix}#{template_name}",
				template_text
			)

			out_obj[template_name] = proc{ |obj| template_compiled.call(obj) }

			out_obj.define_singleton_method(template_name) do |obj|
				template_compiled.call(obj)
			end
		end
		# Otherwise, ignore file
	end
	
	out_obj
end

def save_site_to_disk(path, site)
	site.each do |k, v|
		name = k.to_s
		base = "#{path}/#{name}"

		if v.is_a? Hash
			save_site_to_disk(base, v)
		elsif v.is_a? String
			if name.start_with? '$'
				file_path = "#{path}/#{name[1..-1]}"

				FileUtils::mkdir_p path
			else
				file_path = "#{base}/index.html"

				FileUtils::mkdir_p base
			end

			File.open(file_path, 'w') do |file|
				file.write v
			end
		end
	end
end

def copy_static_files(output_folder, static_folder)
	if File.directory? static_folder
		FileUtils.cp_r Dir.glob("#{static_folder}/*"), output_folder
	end
	# Else noop
end

def read_to_string(file_path)
	File.open(file_path, "r") { |f| f.read }
end

def usable_entries(folder)
	if File.directory? folder
		Dir.entries(folder).reject { |ent|
			ent =~ /^\..*/
		}.map { |ent|
			"#{folder}/#{ent}"
		}
	else
		[]
	end
end

def symbolize_recursive(obj)
	if obj.is_a? Hash
		Hash[
			obj.map { |k, v|
				[
					k.to_sym,
					symbolize_recursive(v)
				]
			}
		]
	elsif obj.is_a? Enumerable
		obj.map { |s| symbolize_recursive(s) }
	else
		obj
	end
end

def num_leaves(hash)
	counter = 0

	hash.each do |k, v|
		if v.is_a? Hash
			counter += num_leaves v
		else
			counter += 1
		end
	end

	counter
end

def files_in_directory(dir)
	Dir[File.join(dir, "**", "*")].count { |f| File.file?(f) }
end

def get_paths(base)
	path = (base || ".").chomp("/")

	{
		path: path,
		helpers_path: "#{path}/helpers.rb",
		data_path: "#{path}/data",
		processors_path: "#{path}/processors",
		template_path: "#{path}/templates",
		site_script_path: "#{path}/site.rb",
		static_path: "#{path}/static",
		out_path: "#{path}/out",
	}
end

def check_is_site_dir(base, paths)
	paths.each do |p|
		if not File.exists? p
			raise "Not a site directory: #{base} (could not find #{p})"
		end
	end
end

def build_processors(processors_folder)
	Hash[
		usable_entries(processors_folder).map do |filename|
			["#{processors_folder}/#{filename}", filename.split('.')]
		end.select do |split|
			split[1][-1] == "rb" && split[1][0] == "process"
		end.flat_map do |split|
			prc = eval(read_to_string(split[0]), nil, File.expand_path(split[0]))

			split[1][1..-2].map do |filetype|
				[filetype, prc]
			end
		end
	]
end

def show_data(args)
	path, data_path, template_path, site_script_path, processors_path =
		get_paths(args[0]).values_at(
			:path,
			:data_path,
			:template_path,
			:site_script_path,
			:processors_path
		)
			
	check_is_site_dir path, [data_path, template_path, site_script_path]
	
	processors = build_processors processors_path

	puts JSON.pretty_generate(
		symbolize_recursive(build_hash_from_folder(processors, data_path))
	)
end

def build(args)
	path, data_path, template_path, site_script_path, static_path, out_path,
		helpers_path, processors_path =
		get_paths(args[0]).values_at(
			:path,
			:data_path,
			:template_path,
			:site_script_path,
			:static_path,
			:out_path,
			:helpers_path,
			:processors_path
		)
		
	check_is_site_dir path, [data_path, template_path, site_script_path]

	if File.exists? helpers_path
		helpers = eval(read_to_string(helpers_path), nil, File.expand_path(helpers_path))

		helpers.each do |name, func|
			@handlebars.register_helper(name, &func)
		end
	end
	
	processors = build_processors processors_path
	
	data = symbolize_recursive(build_hash_from_folder(processors, data_path))
	templates = build_templates_obj_from_folder template_path

	site = eval(read_to_string(site_script_path), nil, File.expand_path(site_script_path))
		.call(data, templates)

	num_generated = num_leaves site
	num_static = files_in_directory static_path
	puts "Saving #{num_generated} pages and #{num_static} files to #{out_path}"

	save_site_to_disk(out_path, site)
	copy_static_files(out_path, static_path)
end

options = {}

OptionParser.new do |opts|
	opts.banner = "Usage: gumdrop.rb [options] [path]"

	opts.on(
		"-c",
		"--compress",
		"Generate .gz versions of all output files"
	) do
		options[:compress] = true
	end

	opts.on("--show-data", "Show the parsed data as pretty JSON") do
		show_data ARGV
		exit
	end

	opts.on("--generate-sitemap", "Generate the sitemap .xml files") do
		puts "UNIMPLEMENTED"
		exit 1
	end

	opts.on("-h", "--help", "Display this screen") do
		puts opts
		exit
	end
end.parse!

build(ARGV)
