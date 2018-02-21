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
		def CAoperator
			['*=',
			 '+='
			].each do |op|
				return op if text.index(op)
			end
			raise "Unknown operator"
		end
		def BINoperator
			['=',
			 '+',
			 '*',
			].each do |op|
				return op if text.index(op)
			end
			raise "Unknown operator in " + text
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
		"-4P" => 2,
		"-4P4" => 3,
		"-4P44" => 4,
		"-4" => 5,
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
			$strtab[cursor.data] = @root.spelling
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

	re_run = true
	while re_run
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
			re_run = parse_var(cursor, parent, false)
			if (re_run)
				first_pass = 0
				next
			end
		else
			raise "Invalid state"
		end
		re_run = false
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

class Basic_compile
	def backup_stack(reg, cursor)
		return if cursor.location.to_s == $function_start.location.to_s
		reg <<= 4
		reg |= 0x3
		print [reg].pack("C")
	end

	def restore_stack(reg, cursor)
		return if cursor.location.to_s == $function_start.location.to_s
		reg <<= 4;
		reg |= 0x43
		print [reg].pack("C")
	end

	def get_mem(cursor)
		idx = 0
		$vartab.each_key do |key|
			break if key == cursor.spelling
			idx = idx + 1
		end
		raise "Unknown var " + cursor.spelling if idx >= $vartab.length
		return idx
	end

	def get_call(cursor)
		idx = 0
		$symtab.each_key do |key|
			break if key == cursor.spelling
			idx = idx + 1
		end
		raise "Unknown call " + cursor.spelling if idx >= $symtab.length
		return idx
	end

	def get_str(cursor)
		idx = 0
		$strtab.each_value do |val|
			break if val == cursor.spelling
			idx = idx + 1
		end
		raise "Unknown str name " + cursor.spelling if idx >= $strtab.length
		return idx
	end
end

class IntLit < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
	end
	def compile(cursor, parent)
		print "\xc0" + [@me.data].pack("Q>")
		return true
	end
end

$in_func_def = false
class DeclRef < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
	end
	def compile(cursor, parent)
		case @me.type.kind
		when Clangc::TypeKind::INT
			print "\x40" + [get_mem(@me)].pack("C")
		when Clangc::TypeKind::POINTER
			print "\x80" + [get_str(@me)].pack("C")
		when Clangc::TypeKind::FUNCTION_PROTO
			raise "Not in function" if ! $in_func_def
		else
			raise "Unknown type " + $type_kind_str[@me.type.kind]
		end
		return true
	end
end

class UnexposedExpr < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
		@next = nil
	end

	def compile(cursor, parent)
		if @next == nil
			raise "bug" if parent.location.to_s != @me.location.to_s

			case cursor.kind
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@next = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::INTEGER_LITERAL
				@next = IntLit.new(cursor, parent)
			when Clangc::CursorKind::DECL_REF_EXPR
				@next = DeclRef.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
		return @next.compile(cursor, parent)
	end
end

class BinOP < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@ope = cursor
		@left = nil
		@right = nil
		backup_stack(1, @up)
	end

	def compile(cursor, parent)

		if @left == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s

			if @ope.BINoperator == "="
				case cursor.kind
				when Clangc::CursorKind::DECL_REF_EXPR
					@left = cursor
				else
					raise "Unhandled " + $cursor_kind_str[cursor.kind]
				end
			else
				case cursor.kind
				when Clangc::CursorKind::UNEXPOSED_EXPR
					@left = UnexposedExpr.new(cursor, parent)
				when Clangc::CursorKind::BINARY_OPERATOR
					@left = BinOP.new(cursor, parent)
				when Clangc::CursorKind::INTEGER_LITERAL
					@left = IntLit.new(cursor, parent)
				when Clangc::CursorKind::DECL_REF_EXPR
					@left = DeclRef.new(cursor, parent)
				else
					raise "Unhandled " + $cursor_kind_str[cursor.kind]
				end
			end
			return false
		end

		if @right == nil
			if @ope.BINoperator != "="
				return false if @left.compile(cursor, parent) == false
			end

			# migrate data
			backup_stack(0, @ope)
			restore_stack(1, @ope)

			raise "bug" if parent.location.to_s != @ope.location.to_s

			case cursor.kind
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@right = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::BINARY_OPERATOR
				@right = BinOP.new(cursor, parent)
			when Clangc::CursorKind::INTEGER_LITERAL
				@right = IntLit.new(cursor, parent)
			when Clangc::CursorKind::CALL_EXPR
				@right = CallExpr.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
		return false if @right.compile(cursor, parent) == false

		case @ope.BINoperator
		when "+"
			backup_stack(2, @ope)
			backup_stack(0, @ope)
			restore_stack(2, @ope)
			print "\x64"
			restore_stack(2, @ope)
		when "*"
			backup_stack(2, @ope)
			backup_stack(0, @ope)
			restore_stack(2, @ope)
			print "\x66"
			restore_stack(2, @ope)
		when "="
			print "\x41" + [get_mem(@left)].pack("C")
		else
			raise "Unimplemented " + @ope.BINoperator
		end

		restore_stack(1, @up)

		@up = nil
		@ope = nil
		@left = nil
		@right = nil
		return true
	end
end

class ComputeAndAssign < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@ope = cursor
		@left = nil
		@right = nil

		backup_stack(1, @up)
	end

	def compile(cursor, parent)
		if @left == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s

			@left = cursor
			return false
		end

		if @right == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s

			case cursor.kind
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@right = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::BINARY_OPERATOR
				@right = BinOP.new(cursor, parent)
			when Clangc::CursorKind::INTEGER_LITERAL
				@right = IntLit.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end

		return false if @right.compile(cursor, parent) == false

		raise "missing param" if @ope == nil || @left == nil || @right == nil
		raise "Unknown result type" if @left.kind != Clangc::CursorKind::DECL_REF_EXPR

		print "\x50" + [get_mem(@left)].pack("C")
		case @ope.CAoperator
		when "*="
			backup_stack(2, @ope)
			backup_stack(0, @ope)
			restore_stack(2, @ope)
			print "\x66"
			restore_stack(2, @ope)
		when "+="
			backup_stack(2, @ope)
			backup_stack(0, @ope)
			restore_stack(2, @ope)
			print "\x64"
			restore_stack(2, @ope)
		else
			raise "Unimplemented"
		end

		print "\x41" + [get_mem(@left)].pack("C")

		restore_stack(1, @up)

		@up = nil
		@ope = nil
		@left = nil
		@right = nil
		return true
	end
end

class CallExpr < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@call = cursor
		@def = nil
		@def_done = false
		@params = {}
	end

	def newchild(cursor, parent)
		case cursor.kind
		when Clangc::CursorKind::UNEXPOSED_EXPR
			pp = UnexposedExpr.new(cursor, parent)
		when Clangc::CursorKind::BINARY_OPERATOR
			pp = BinOP.new(cursor, parent)
		when Clangc::CursorKind::INTEGER_LITERAL
			pp = IntLit.new(cursor, parent)
		else
			raise "Unhandled " + $cursor_kind_str[cursor.kind]
		end
		@params[@params.length] = pp
	end

	def compile(cursor, parent)

		if !@def_done
			if @def == nil
				$in_func_def = true

				raise "bug" if cursor.kind != Clangc::CursorKind::UNEXPOSED_EXPR
				@def = UnexposedExpr.new(cursor, parent)
				return false
			end
			return false if @def.compile(cursor, parent) == false
			@def_done = true
			$in_func_def = false
		end

		if @call.num_arguments == 0
			raise "bug" if parent.location.to_s == @call.location.to_s

			print "\x2" + [get_call(@call)].pack("C")
			return true
		end

		if @params.length == 0
			newchild(cursor, parent)
			return false
		end

		if @params.length < @call.num_arguments
			return false if @params[@params.length - 1].compile(cursor, parent) == false
			backup_stack(0, @call)
			newchild(cursor, parent)
			return false
		end
		return false if @params[@params.length - 1].compile(cursor, parent) == false

		backup_stack(0, @call) if (@call.num_arguments != 1)

		restore_stack(3, @call) if @call.num_arguments > 3
		restore_stack(2, @call) if @call.num_arguments > 2
		restore_stack(1, @call) if @call.num_arguments > 1

		restore_stack(0, @call) if (@call.num_arguments != 1)

		print "\x2" + [get_call(@call)].pack("C")

		return true
	end
end

module State
  OUT = 0
  FUNC_DECL = 1
  FUNC_BODY = 2
  IN_PARSE = 3
end
machine_status = State::OUT
cur_parse = nil

cl35.parse do |tu, cursor, parent|
	next if ! cl35.cursor_in_main_file?(cursor)

	re_run = true
	while re_run
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
					cur_parse = ComputeAndAssign.new(cursor, parent)
				when Clangc::CursorKind::BINARY_OPERATOR
					cur_parse = BinOP.new(cursor, parent)
				when Clangc::CursorKind::CALL_EXPR
					cur_parse = CallExpr.new(cursor, parent)
				else
					raise "Unknown cursor " + $cursor_kind_str[cursor.kind] + " " + $cursor_kind_str[parent.kind]
				end
				machine_status = State::IN_PARSE if cur_parse != nil
			end
		when State::IN_PARSE
			re_run = cur_parse.compile(cursor, parent)
			if (re_run)
				machine_status = State::FUNC_BODY
				cur_parse = nil
				next
			end
		else
			raise "Invalid state"
		end
		re_run = false
	end
end
cur_parse.compile(nil, nil)

