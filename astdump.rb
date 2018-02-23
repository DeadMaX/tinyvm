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
			if text == "NULL"
				return 0
			end
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
		def CONDoperator
			['==',
			 '<=',
			 '>=',
			 '!=',
			 '<',
			 '>'
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

$code_offset = 0

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
		"-0P44" => 6,
		"-PP" => 7,
		"-4PPP" => 8,
		"-44P4" => 9,
		"-444" => 10,
		"-44" => 11,
		"-4PPPPP" => 12,
		"-4PPPP" => 13,
		"-84P8" => 14,
		}

	key = ""

	case val1.type.kind
	when Clangc::TypeKind::VOID
		key += "-0"
	when Clangc::TypeKind::U_INT
		key += "-4"
	when Clangc::TypeKind::INT
		key += "-4"
	when Clangc::TypeKind::POINTER
		key += "-P"
	when Clangc::TypeKind::TYPEDEF
		case val1.type.size_of
		when 4
			key += "-4"
		when 8
			key += "-8"
		else
			raise "Invalid return size " + val1.type.size_of.to_s
		end
	else
		raise "Unknown return type " + $type_kind_str[val1.type.kind]
	end

	val2.each do |arg|
		case arg.type.kind
		when Clangc::TypeKind::U_INT
			key += "4"
		when Clangc::TypeKind::INT
			key += "4"
		when Clangc::TypeKind::POINTER
			key += "P"
		when Clangc::TypeKind::TYPEDEF
			case arg.type.size_of
			when 4
				key += "4"
			when 8
				key += "8"
			else
				raise "Invalid call size " + val1.type.size_of.to_s
			end
		else
			raise "Unknown parameter type \"" + $type_kind_str[arg.type.kind] + "\""
		end
	end

	if (!hash[key])
		raise "Not function type defined for " + val1.spelling + ": " + key
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
			if cursor.type.pointee_type.kind != Clangc::TypeKind::CHAR_S
				raise "Invalid pointee type " + $type_kind_str[cursor.type.pointee_type.kind]
			end
			$vartab[cursor.spelling] = 0
		when Clangc::TypeKind::TYPEDEF
			raise "Type too long" if cursor.type.size_of > 8
			$vartab[cursor.spelling] = 0
		when Clangc::TypeKind::CONSTANT_ARRAY
			count = 0
			while count < cursor.type.size_of
				$vartab[cursor.spelling + count.to_s] = 0
				count += 8
			end
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
 	when Clangc::CursorKind::C_STYLE_CAST_EXPR
 		return false
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
	when Clangc::CursorKind::TYPE_REF
		raise "Type too long" if cursor.type.size_of > 8
		@prev = parent
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
				if (! $symtab[cursor.spelling])
					$symtab[cursor.spelling] = [$current_sym, getcall(cursor, cursor.arguments)]
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
	def backup_stack(reg, cursor, stream)
		return if cursor.location.to_s == $function_start.location.to_s
		reg <<= 4
		reg |= 0x3
		stream.print [reg].pack("C")
	end

	def restore_stack(reg, cursor, stream)
		return if cursor.location.to_s == $function_start.location.to_s
		reg <<= 4;
		reg |= 0x43
		stream.print [reg].pack("C")
	end

	def get_mem(name)
		idx = 0
		$vartab.each_key do |key|
			break if key == name
			idx = idx + 1
		end
		raise "Unknown var " + name if idx >= $vartab.length
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
	def compile(cursor, parent, stream)
		stream.print "\xc0" + [@me.data].pack("Q>")
		return true
	end
end

$in_func_def = false
class DeclRef < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
	end
	def compile(cursor, parent, stream)
		case @me.type.kind
		when Clangc::TypeKind::TYPEDEF
			raise "Type too long" if cursor.type.size_of > 8
			stream.print "\x40" + [get_mem(@me.spelling)].pack("C")
		when Clangc::TypeKind::INT
			stream.print "\x40" + [get_mem(@me.spelling)].pack("C")
		when Clangc::TypeKind::POINTER
			if $vartab[@me.spelling]
				stream.print "\x40" + [get_mem(@me.spelling)].pack("C")
			else
				stream.print "\x80" + [get_str(@me)].pack("C")
			end
		when Clangc::TypeKind::FUNCTION_PROTO
			raise "Not in function" if ! $in_func_def
		when Clangc::TypeKind::CONSTANT_ARRAY
			raise "unknown var " +@me.spelling + "0" if !$vartab[@me.spelling + "0"]
			stream.print "\x00" + [get_mem(@me.spelling + "0")].pack("C")
		else
			raise "Unknown type " + $type_kind_str[@me.type.kind]
		end
		return true
	end
end

class ArrayStuff < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
		@cast = nil
		@var = nil
		@expr = nil
	end

	def compile(cursor, parent, stream)
		if @cast == nil
			raise "bug" if parent.location.to_s != @me.location.to_s
			raise "bug" if cursor.kind != Clangc::CursorKind::UNEXPOSED_EXPR
			@cast = cursor
			return false
		end
		if @var == nil
			raise "bug" if parent.location.to_s != @cast.location.to_s
			@var = cursor
			return false
		end
		if @expr == nil
			raise "bug" if parent.location.to_s != @me.location.to_s
			case cursor.kind
			when Clangc::CursorKind::INTEGER_LITERAL
				@expr = cursor.data
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
#		return false if @expr.parse(cursor, parent, stream) == false

		raise "Type too long" if @me.type.size_of > 8
		
		offset = (@me.type.size_of * @expr) % 8;
		var_num = (@me.type.size_of * @expr) / 8;

		stream.print "\x40" + [get_mem(@var.spelling + var_num.to_s)].pack("C")
		if offset == 0
			return true
		end

		backup_stack(1, @me, stream)
		stream.print "\xd0" + [2**(offset * 8)].pack("Q>") + "\x47"
		restore_stack(1, @me, stream)

		return true
	end
end

class UnexposedExpr < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
		@next = nil
	end

	def compile(cursor, parent, stream)
		if @next == nil
			raise "bug" if parent.location.to_s != @me.location.to_s

			case cursor.kind
			when Clangc::CursorKind::PAREN_EXPR
				@next = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@next = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::C_STYLE_CAST_EXPR
				@next = UnexposedExpr.new(cursor, parent)
			when Clangc::CursorKind::INTEGER_LITERAL
				@next = IntLit.new(cursor, parent)
			when Clangc::CursorKind::DECL_REF_EXPR
				@next = DeclRef.new(cursor, parent)
			when Clangc::CursorKind::CALL_EXPR
				@next = CallExpr.new(cursor, parent)
			when Clangc::CursorKind::ARRAY_SUBSCRIPT_EXPR
				@next = ArrayStuff.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
		return @next.compile(cursor, parent, stream)
	end
end

class BinOP < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@ope = cursor
		@left = nil
		@right = nil
	end

	def compile(cursor, parent, stream)

		if @left == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s
			backup_stack(1, @up, stream)

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
				return false if @left.compile(cursor, parent, stream) == false
			end

			# migrate data
			backup_stack(0, @ope, stream)
			restore_stack(1, @ope, stream)

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
		return false if @right.compile(cursor, parent, stream) == false

		case @ope.BINoperator
		when "+"
			stream.print "\x14"
		when "*"
			stream.print "\x16"
		when "="
			stream.print "\x41" + [get_mem(@left.spelling)].pack("C")
		else
			raise "Unimplemented " + @ope.BINoperator
		end

		restore_stack(1, @up, stream)

		@up = nil
		@ope = nil
		@left = nil
		@right = nil
		return true
	end
end

class CondOP < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@ope = cursor
		@left = nil
		@right = nil
	end

	def compile(cursor, parent, stream)

		if @left == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s
			case cursor.kind
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@left = UnexposedExpr.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end

		if @right == nil
			return false if @left.compile(cursor, parent, stream) == false

			# migrate data
			backup_stack(0, @ope, stream)
			restore_stack(1, @ope, stream)

			raise "bug" if parent.location.to_s != @ope.location.to_s

			case cursor.kind
			when Clangc::CursorKind::UNEXPOSED_EXPR
				@right = UnexposedExpr.new(cursor, parent)
 			when Clangc::CursorKind::INTEGER_LITERAL
 				@right = IntLit.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
		return false if @right.compile(cursor, parent, stream) == false

		case @ope.CONDoperator
		when "=="
			stream.print "\x19\xea"
# 		when "*"
# 			stream.print "\x16"
# 		when "="
# 			stream.print "\x41" + [get_mem(@left)].pack("C")
		else
			raise "Unimplemented " + @ope.CONDoperator
		end

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
	end

	def compile(cursor, parent, stream)
		if @left == nil
			raise "bug" if parent.location.to_s != @ope.location.to_s

			backup_stack(1, @up, stream)
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

		return false if @right.compile(cursor, parent, stream) == false

		raise "missing param" if @ope == nil || @left == nil || @right == nil
		raise "Unknown result type" if @left.kind != Clangc::CursorKind::DECL_REF_EXPR

		stream.print "\x50" + [get_mem(@left.spelling)].pack("C")
		case @ope.CAoperator
		when "*="
			stream.print "\x16"
		when "+="
			stream.print "\x14"
		else
			raise "Unimplemented"
		end

		stream.print "\x41" + [get_mem(@left.spelling)].pack("C")

		restore_stack(1, @up, stream)

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
		when Clangc::CursorKind::PAREN_EXPR
			pp = UnexposedExpr.new(cursor, parent)
		when Clangc::CursorKind::BINARY_OPERATOR
			pp = BinOP.new(cursor, parent)
		when Clangc::CursorKind::INTEGER_LITERAL
			pp = IntLit.new(cursor, parent)
		else
			raise "Unhandled " + $cursor_kind_str[cursor.kind]
		end
		@params[@params.length] = [pp, StringIO.new]
	end

	def compile(cursor, parent, stream)

		if !@def_done
			if @def == nil
				$in_func_def = true

				raise "bug" if cursor.kind != Clangc::CursorKind::UNEXPOSED_EXPR
				@def = UnexposedExpr.new(cursor, parent)
				return false
			end
			return false if @def.compile(cursor, parent, stream) == false
			@def_done = true
			$in_func_def = false
		end

		if @call.num_arguments == 0
			raise "bug" if parent.location.to_s == @call.location.to_s

			stream.print "\x2" + [get_call(@call)].pack("C")
			return true
		end

		if @params.length == 0
			newchild(cursor, parent)
			return false
		end

		if @params.length < @call.num_arguments
			return false if @params[@params.length - 1][0].compile(cursor, parent, @params[@params.length - 1][1]) == false
			backup_stack(0, @call, @params[@params.length - 1][1])
			$code_offset += @params[@params.length - 1][1].length
			newchild(cursor, parent)
			return false
		end
		return false if @params[@params.length - 1][0].compile(cursor, parent, @params[@params.length - 1][1]) == false
		backup_stack(0, @call, @params[@params.length - 1][1])
		$code_offset += @params[@params.length - 1][1].length

		i = @call.num_arguments - 1
		while i >= 0
			stream << @params[i][1].string
			$code_offset -= @params[i][1].length
			i -= 1
		end
		
		restore_stack(0, @call, stream) if @call.num_arguments > 0
		restore_stack(1, @call, stream) if @call.num_arguments > 1
		restore_stack(2, @call, stream) if @call.num_arguments > 2
		restore_stack(3, @call, stream) if @call.num_arguments > 3

		stream.print "\x2" + [get_call(@call)].pack("C")

		i = 4
		while i < @call.num_arguments
			restore_stack(1, @call, stream)
			i += 1
		end

		return true
	end
end

class Compo < Basic_compile
	def initialize(cursor, parent)
		@me = cursor
		@cur = nil
		@skipping = false
	end

	def compile(cursor, parent, stream)
		if @cur == nil
			return false if @skipping && parent.location.to_s != @me.location.to_s
			@skipping = false
			return true if parent == nil || parent.location.to_s != @me.location.to_s
			case cursor.kind
			when Clangc::CursorKind::DECL_STMT
				@skipping = true
			when Clangc::CursorKind::BINARY_OPERATOR
				@cur = BinOP.new(cursor, parent)
			when Clangc::CursorKind::CALL_EXPR
				@cur = CallExpr.new(cursor, parent)
			when Clangc::CursorKind::IF_STMT
				@cur = IfExpr.new(cursor, parent)
			else
				raise "Unhandled " + $cursor_kind_str[cursor.kind]
			end
			return false
		end
		return false if @cur.compile(cursor, parent, stream) == false
		@cur = nil
		return compile(cursor, parent, stream)
	end
end

class IfExpr < Basic_compile
	def initialize(cursor, parent)
		@up = parent
		@stmt = cursor
		@cond = nil
		@cond_done = false
		@then = nil
		@then_done = false
		@then_stream = StringIO.new
		@else = nil
		@else_stream = StringIO.new
	end
	def compile(cursor, parent, stream)
		if @cond_done == false
			if @cond == nil
				raise "bug" if parent.location.to_s != @stmt.location.to_s

				case cursor.kind
				when Clangc::CursorKind::BINARY_OPERATOR
					@cond = CondOP.new(cursor, parent)
#	 			when Clangc::CursorKind::UNEXPOSED_EXPR
# 				when Clangc::CursorKind::INTEGER_LITERAL
				else
					raise "Unhandled " + $cursor_kind_str[cursor.kind]
				end
				return false
			else
				return false if @cond.compile(cursor, parent, stream) == false
				@cond_done = true
			end
		end
		if @then_done == false
			if @then == nil
				raise "bug" if parent.location.to_s != @stmt.location.to_s
				raise "bug" if cursor.kind != Clangc::CursorKind::COMPOUND_STMT
				$code_offset += stream.length + 8
				@then = Compo.new(cursor, parent)
				return false
			end
			return false if @then.compile(cursor, parent, @then_stream) == false
			@then_done = true
		end

		if @else == nil
			if parent.location.to_s != @stmt.location.to_s
				jump = $code_offset + @then_stream.length
				$code_offset -= stream.length + 8
				stream.print [jump].pack("Q>") + @then_stream.string
				return true
			end
			raise "bug" if cursor.kind != Clangc::CursorKind::COMPOUND_STMT
			@else = Compo.new(cursor, parent)
			jump = $code_offset + @then_stream.length + 9
			stream.print [jump].pack("Q>") + @then_stream.string + "\xa"
			return false
		end
		return false if @else.compile(cursor, parent, @else_stream) == false

		jump = $code_offset + @else_stream.length
		$code_offset -= stream.length + 8
		stream.print [jump].pack("Q>") + @else_stream.string

		return true
	end
end

module State
  OUT = 0
  FUNC_BODY = 1
  IN_PARSE = 2
end
machine_status = State::OUT
cur_parse = nil

codeBuffer=StringIO.new

cl35.parse do |tu, cursor, parent|
	next if ! cl35.cursor_in_main_file?(cursor)

	re_run = true
	while re_run
		case machine_status
		when State::OUT
			if cursor.kind == Clangc::CursorKind::FUNCTION_DECL and cursor.spelling == "run"
				machine_status = State::FUNC_BODY
			end
		when State::FUNC_BODY
			raise "No function body" if cursor.kind != Clangc::CursorKind::COMPOUND_STMT
			$function_start = cursor
			cur_parse = Compo.new(cursor, parent)
			machine_status = State::IN_PARSE
		when State::IN_PARSE
			re_run = cur_parse.compile(cursor, parent, codeBuffer)
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
cur_parse.compile(nil, nil, codeBuffer) # flush
STDOUT << codeBuffer.string

