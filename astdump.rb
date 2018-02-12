#!/usr/bin/env ruby

require 'clangc'
# clangc extensions
class Clangc::SourceLocation
	def to_s
		return "(line #{self.file_location[1]},column #{self.file_location[2]})"
	end
end

require 'fileutils'
require 'pp'

PATH = File.expand_path(File.dirname(__FILE__))

class SourceParser

	attr_reader :index, :source_file, :base_dir, :translation_unit, :diagnostics

	def initialize(source_file, base_dir = nil, lang = "c")
		@source_file = source_file
		@base_dir = base_dir ||= File.expand_path(File.dirname(@source_file))
		include_libs = build_default_include_libs
		args = ["-x", lang] + include_libs
		args += ["-Xclang", "-detailed-preprocessing-record", "-ferror-limit=1"]
		@index = Clangc::Index.new(false, false)
		#@translation_unit = @index.parse_translation_unit({source: source_file, args: args, flags: Clangc::TranslationUnit_Flags::DETAILED_PREPROCESSING_RECORD})
		@translation_unit = @index.create_translation_unit(source: source_file, args: args)
		if @translation_unit
			@diagnostics = @translation_unit.diagnostics
			if @diagnostics.size > 0
				d = @diagnostics.first
				file, line, position, _ = d.source_range(0).start.file_location
				raise "#{d.spelling} (#{file.name}:#{line},#{position})"
			end
		end
	end

	def parse(&block)
		cursor = @translation_unit.cursor
		Clangc.visit_children(cursor: cursor) do |cxcursor, parent|
			yield(@translation_unit, cxcursor, parent)
			Clangc::ChildVisitResult::RECURSE
		end
	end

	# Check if the cursor given in argument focus on
	# the file we want to parse and not on included
	# headers
	def cursor_in_main_file?(cursor)
		cursor_file = cursor.location.spelling[0]
		main_file = @translation_unit.file(@source_file)
		cursor_file.is_equal(main_file)
	end

	private

	# Add the directories where the default headers files
	# for the standards libs can be found
	def build_default_include_libs
		header_paths = []
		gcc_lib_base='/usr/lib/gcc/' << `llvm-config50 --host-target`.chomp << "/*"
		last_gcc_lib_base = Dir.glob(gcc_lib_base ).sort.last
		if last_gcc_lib_base
			gcc_lib = last_gcc_lib_base + "/include"
			header_paths << gcc_lib
		end
		header_paths << "/usr/include"
		header_paths << "/usr/src/include"
		header_paths << "/usr/src/sys"
		header_paths << @base_dir
		header_paths.collect {|h| "-I#{h}"}
	end
end

class CSourceParser < SourceParser
	def initialize(source_file, base_dir = nil)
		super(source_file, base_dir, "c")
	end
end

class CPPSourceParser < SourceParser
	def initialize(source_file, base_dir = nil)
		super(source_file, base_dir, "c++")
	end
end

cl35 = CSourceParser.new(ARGV[0])

unless cl35.translation_unit
	puts "Parsing failed"
end

cursor_kind_str = {}
Clangc::CursorKind.constants.each{|c| cursor_kind_str[eval("Clangc::CursorKind::" + c.to_s)] = c.to_s} #beurk

current_sym = 0
symtab = {}

current_var = 0
vartab = {}

tree_depth = {}
prev_depth = 0
prev_parent = nil
cl35.parse do |tu, cursor, parent|
	if cl35.cursor_in_main_file?(cursor)
		if parent.location.file_location[3] != prev_parent
			prev_depth = tree_depth[parent.location.file_location[3]] ||= (prev_depth += 1)
		end
# 		puts " " * prev_depth + cursor_kind_str[cursor.kind] + ": #{cursor.spelling}"
		prev_parent = parent.location.file_location[3]

		if cursor.kind == Clangc::CursorKind::CALL_EXPR
			if (! symtab[cursor.spelling])
				symtab[cursor.spelling] = current_sym
				current_sym += 1
			end
		end
		if cursor.kind == Clangc::CursorKind::VAR_DECL
			if (! vartab[cursor.spelling])
				vartab[cursor.spelling] = current_var
				current_var += 1
			end
		end
	end
end

if symtab.length > 256
	raise "too many function call"
end

if vartab.length > 256
	raise "too many variables"
end

symtab.each_key do |sym|
	print sym + "\0\1"
end
print "\0"

print [vartab.length].pack("C")
vartab.each_value do |var|
	print [var].pack("Q>")
end

print "\x80\1\2\0"
# puts symtab
# puts vartab
