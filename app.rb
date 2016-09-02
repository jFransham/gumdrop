require 'bundler/setup'
require 'yaml'
require 'redcarpet'
require 'flavour_saver'
require 'recursive-open-struct'

def build_hash_from_file(file)
	ext = File.extname file
	
	renderer = Redcarpet::Render::HTML.new
	markdown = Redcarpet::Markdown.new renderer

	case ext
	when ".yml", ".yaml"
		contents = File.open(file) { |f| f.read }
		YAML.load(contents)
	when ".md", ".markdown"
		contents = File.open(file) { |f| f.read }
		{ "content" => markdown.render(contents) }
	else
		raise ArgumentError, "Unsupported data file format #{ext}"
	end
end

def build_hash_from_name(folder_entries, name)
	puts "Building hash for #{name}"
	
	entries_with_name = folder_entries.select do |full_name|
		File.basename(full_name, ".*") == name
	end
	
	out = {}

	entries_with_name.each do |file|
		puts "File = #{file}"

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

	save_names = [:object_id, :__send__]

	usable_entries(folder_name).each do |entry|
		template = File.open(entry) { |f| f.read }

		template_name = File.basename(entry, ".*").to_sym

		FS.register_partial(template_name, template)

		save_names.push template_name

		out_obj.define_singleton_method(template_name) do |obj|
			FS.evaluate(template, obj)
		end
	end
	
	s_class = out_obj.singleton_class
	
	out_obj.methods.reject { |m| save_names.include? m }.each do |meth|
		s_class.send :undef_method, meth
	end
	
	out_obj
end

def usable_entries(folder)
	Dir.entries(folder).reject { |ent|
		ent == '.' or ent == '..'
	}.map { |ent|
		"#{folder}/#{ent}"
	}
end

data = build_hash_from_folder "./examples/test-site/data"
struct_data = RecursiveOpenStruct.new data
puts data
puts build_templates_obj_from_folder("./examples/test-site/templates")
	.index(struct_data)
