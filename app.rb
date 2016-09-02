require 'bundler/setup'
require 'yaml'
require 'redcarpet'
require 'handlebars'
require 'fileutils'

@handlebars = Handlebars::Context.new

def build_hash_from_file(file)
	ext = File.extname file
	
	renderer = Redcarpet::Render::HTML.new
	markdown = Redcarpet::Markdown.new renderer

	case ext
	when ".yml", ".yaml"
		contents = read_to_string(file)
		YAML.load(contents)
	when ".md", ".markdown"
		contents = read_to_string(file)
		{ "content" => markdown.render(contents) }
	else
		raise ArgumentError, "Unsupported data file format #{ext}"
	end
end

def build_hash_from_name(folder_entries, name)
	entries_with_name = folder_entries.select do |full_name|
		File.basename(full_name, ".*") == name
	end
	
	out = {}

	entries_with_name.each do |file|
		new_hash = if File.directory? file
			build_hash_from_folder file
	    else
			build_hash_from_file file
		end

		out.merge! new_hash
	end
	
	out
end

def build_hash_from_folder(folder_name)
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
		out[name] = build_hash_from_name(all_files, name)
	end
	
	if not props_file.nil?
		out.merge! build_hash_from_name(all_files, props_file)
	end
	
	out
end

def build_templates_obj_from_folder(folder_name)
	out_obj = Object.new

	usable_entries(folder_name).each do |entry|
		template_text = read_to_string entry
		template_compiled = @handlebars.compile template_text

		template_name = File.basename(entry, ".*").to_sym

		@handlebars.register_partial(template_name, template_text)

		out_obj.define_singleton_method(template_name) do |obj|
			template_compiled.call(obj)
		end
	end
	
	out_obj
end

def save_site_to_disk(path, site)
	site.each do |k, v|
		folder = "#{path}/#{k.to_s}"

		if v.is_a? Hash
			save_site_to_disk(folder, v)
		elsif v.is_a? String
			file_path = "#{folder}/index.html"

			FileUtils::mkdir_p folder

			File.open(file_path, 'w') do |file|
				file.write v
			end
		end
	end
end

def read_to_string(file_path)
	File.open(file_path, "r") { |f| f.read }
end

def usable_entries(folder)
	Dir.entries(folder).reject { |ent|
		ent == '.' or ent == '..'
	}.map { |ent|
		"#{folder}/#{ent}"
	}
end

def symbolize_recursive(hash)
	Hash[
		hash.map { |k, v|
			[
				k.to_sym,
				if v.is_a? Hash then symbolize_recursive(v) else v end
			]
		}
	]
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

path = (ARGV[0] || ".").chomp("/")

data_path = "#{path}/data"
template_path = "#{path}/templates"
site_script_path = "#{path}/site.rb"
out_path = "#{path}/out"

if not [data_path, template_path, site_script_path].all? { |f| File.exists? f }
	raise "Not a site directory: #{path}"
end

data = symbolize_recursive(build_hash_from_folder data_path)
templates = build_templates_obj_from_folder template_path

site = eval(read_to_string(site_script_path)).call(data, templates)

puts "Saving #{num_leaves site} pages to #{out_path}"

save_site_to_disk(out_path, site)
