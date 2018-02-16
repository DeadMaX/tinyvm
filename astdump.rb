#!/usr/bin/env ruby

require 'clangc'
# clangc extensions
module Clangc
	class Cursor
		def text
			range = self.extent
			file = range.start.spelling[0]
			offset = range.start.spelling[3]
			count = range.end.spelling[3] - offset
			return Object::File.read(file.name, count, offset)
		end
		def data
			return eval(text)
		end
	end

	class SourceLocation
		def to_s
			return "(line #{self.file_location[1]},column #{self.file_location[2]})"
		end
	end
end

require 'fileutils'
require 'pp'

$current_sym = 0
$symtab = {}

$current_str = 0
$strtab = {}

$current_var = 0
$vartab = {}

$cursor_kind_str = {}
Clangc::CursorKind.constants.each{|c| $cursor_kind_str[eval("Clangc::CursorKind::" + c.to_s)] = c.to_s} #beurk

$type_kind_str = {}
Clangc::TypeKind.constants.each{|c| $type_kind_str[eval("Clangc::TypeKind::" + c.to_s)] = c.to_s} #beurk

$function_start = nil

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
		gcc_lib_base='/usr/lib/gcc/' << `llvm-config40 --host-target`.chomp << "/*"
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

def getcall(val1, val2)
	hash = {
		"-0" => 0,
	    "-04" => 1,
		"-4P" => 2
		}

	key = ""

	case val1
	when Clangc::TypeKind::VOID
		key += "-0"
	when Clangc::TypeKind::INT
		key += "-4"
	else
		raise "Unknown return type " + $type_kind_str[val1]
	end

	val2.each do |arg|
		case arg.type.kind
		when Clangc::TypeKind::INT
			key += "4"
		when Clangc::TypeKind::POINTER
			key += "P"
		else
			raise "Unknown parameter type \"" + $type_kind_str[arg.type.kind] + "\""
		end
	end

	if (!hash[key])
		raise "Not function type defined: " + key
	end

	return hash[key]
end

def parse_var(cursor, parent, is_new)
	@prev ||= nil
	@root ||= nil

	if is_new
		if ($vartab[cursor.spelling])
			raise "Double var definition"
		end

		case cursor.type.kind
		when Clangc::TypeKind::INT
			$vartab[cursor.spelling] = 0
		when Clangc::TypeKind::POINTER
		else
			raise "unknown type " + $type_kind_str[cursor.type.kind]
		end
		@root = cursor
		@prev = cursor
		return false
	end

	if parent.location.to_s != @prev.location.to_s
		return true
	end
	@prev = cursor

	case cursor.kind
 	when Clangc::CursorKind::UNEXPOSED_EXPR
 		return false
	when Clangc::CursorKind::STRING_LITERAL
		$vartab.delete(@root.spelling)
		if (! $strtab[cursor.data])
			$strtab[cursor.data] = $current_str
			$current_str += 1
		end
	when Clangc::CursorKind::INTEGER_LITERAL
		$vartab[@root.spelling] = cursor.data
		$current_var += 1
	else
		raise "Unknown variable type " + $cursor_kind_str[cursor.kind]
	end

	return false
end


first_pass = 0
cl35.parse do |tu, cursor, parent|
	next if ! cl35.cursor_in_main_file?(cursor)

	loop = true
	while loop
		case first_pass
		when 0
			if (cursor.kind == Clangc::CursorKind::CALL_EXPR)
				if (cursor.num_arguments > 4)
					raise "too many argument"
				end

				if (! $symtab[cursor.spelling])
					$symtab[cursor.spelling] = [$current_sym, getcall(cursor.type.kind, cursor.arguments)]
					$current_sym += 1
				end
			end
			if cursor.kind == Clangc::CursorKind::VAR_DECL
				parse_var(cursor, parent, true)
				first_pass = 1
			end
		when 1
			loop = parse_var(cursor, parent, false)
			if (loop)
				first_pass = 0
				next
			end
		else
			raise "Invalid state"
		end
		loop = false
	end
end

if $symtab.length > 256
	raise "too many function call"
end

if $strtab.length > 256
	raise "too many strings"
end

if $vartab.length > 256
	raise "too many variables"
end

$symtab.each do |sym, val|
	print sym + "\0" + [val[1]].pack("C")
end
print "\0"

$strtab.each_key do |str|
	print str + "\0"
end
print "\0"

print [$vartab.length].pack("C")
$vartab.each_value do |var|
	print [var].pack("Q>")
end

def compute_and_assign(cursor, parent, is_new)
	@prev ||= nil
	@root ||= nil

	if is_new
		STDERR.puts "Start assign operator >" + cursor.result_type.kind.to_s + "<"

		@root = cursor
		@prev = cursor
		return false
	end
	return false
end

module State
  OUT = 0
  FUNC_DECL = 1
  FUNC_BODY = 2
  COMPOUND_ASSIGN = 3
end
machine_status = State::OUT

cl35.parse do |tu, cursor, parent|
	next if ! cl35.cursor_in_main_file?(cursor)

	loop = true
	while loop
		case machine_status
		when State::OUT
			if cursor.kind == Clangc::CursorKind::FUNCTION_DECL and cursor.spelling == "run"
				machine_status = State::FUNC_DECL
			end
		when State::FUNC_DECL
			if cursor.kind != Clangc::CursorKind::COMPOUND_STMT
				raise "No function body"
			end
			machine_status = State::FUNC_BODY
			$function_start = cursor
		when State::FUNC_BODY
			if parent.location.to_s == $function_start.location.to_s
				case cursor.kind
				when Clangc::CursorKind::DECL_STMT
					# IGNORE
				when Clangc::CursorKind::COMPOUND_ASSIGN_OPERATOR
					compute_and_assign(cursor, parent, true)
				else
					raise "Unknown cursor " + $cursor_kind_str[cursor.kind] + " " + $cursor_kind_str[parent.kind]
				end
			end
		when State::COMPOUND_ASSIGN
			loop = compute_and_assign(cursor, parent, false)
			if (loop)
				machine_status = State::FUNC_BODY
				next
			end
		else
			raise "Invalid state"
		end
		loop = false
	end
end

print "\x80\0\2\0\x40\0\2\1"
