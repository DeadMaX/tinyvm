#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>

typedef uint8_t callnum;
typedef uint8_t memaddr;
typedef struct
{
	uint64_t regs[4];
	size_t stackptr;
	const char *pc;

	bool equals:1;
	bool lesser:1;
	bool greater:1;
} cpustate;

typedef void (*op)(cpustate *);

#define MAXSYMS (1 << (sizeof(callnum) * 8))
static void *syms[MAXSYMS];
static enum
{
    /* return_param1_param2_param3_param4 */
	VOID_VOID = 0,
	VOID_INT,

	SYMS_TYPE_MAX
} syms_type[MAXSYMS];

#define MAXMEM (1 << (sizeof(memaddr) * 8))
static uint64_t vmmem[MAXMEM];

#define VMSTACK 1024
static uint64_t vmstack[VMSTACK];

static const char *codestart;
static const char *codeend;

static void advance(cpustate *state)
{
	++state->pc;
	if (state->pc < codestart || state->pc >= codeend)
	{
		fprintf(stderr, "Instruction decode\n");
		exit(0);
	}
}

memaddr readmem(cpustate *state)
{
	memaddr res = 0;
	for(size_t i = 0; i < sizeof(memaddr); ++i)
	{
		advance(state);
		res <<= 8;
		res += *(uint8_t *)state->pc;
	}
	return res;
}

callnum readfunc(cpustate *state)
{
	callnum res = 0;
	for(size_t i = 0; i < sizeof(callnum); ++i)
	{
		advance(state);
		res <<= 8;
		res += *(uint8_t *)state->pc;
	}
	return res;
}

static void load(cpustate *state)
{
    /* load: opcode 0000
     * layout: zyxx0000
     * z: 0 stack source, 1 mem source
     * y
     * xx: regnumber
     */
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;
	bool mem = ((*state->pc) & 0x80) ? true : false;
	memaddr arg = readmem(state);
	if (mem)
	{
		state->regs[regnum] = vmmem[arg];
	}
	else
	{
		if (arg >= state->stackptr)
		{
			fprintf(stderr, "Stack not init\n");
			exit(0);
		}
		state->regs[regnum] = vmstack[arg - state->stackptr - 1];
	}
}

static void store(cpustate *state)
{
    /* store: opcode 0001
     * layout: zyxx0000
     * z: 0 stack destination, 1 mem destination
     * y
     * xx: regnumber
     */
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;
	bool mem = ((*state->pc) & 0x80) ? true : false;
	memaddr arg = readmem(state);
	if (mem)
	{
		vmmem[arg] = state->regs[regnum];
	}
	else
	{
		if (arg >= state->stackptr)
		{
			fprintf(stderr, "Stack fault\n");
			exit(0);
		}
		vmstack[arg - state->stackptr - 1] = state->regs[regnum] ;
	}
}

static void call(cpustate *state)
{
    /* call: opcode 0010
     * layout: xyyy0010
     * x: 0 stack parameter, 1 mem parameter
     * yyy: argcount;
     */
	uint8_t paramcount = ((*state->pc) & 0x70) >> 4;
	bool mem = ((*state->pc) & 0x80) ? true : false;
	callnum func = readfunc(state);
	if (!syms[func])
	{
		fprintf(stderr, "Unknown function\n");
		exit(0);
	}
	switch(syms_type[func])
	{
		case VOID_VOID:
			((void (*)(void))syms[func])();
			break;
		case VOID_INT:
			((void (*)(int))syms[func])(state->regs[0]);
			break;

		default:
			fprintf(stderr, "Bad call\n");
			exit(0);
			break;
	}
}

static void push_pop(cpustate *state)
{
    /* push_pop: opcode 0011
     * layout: zyxx0011
     * z:
     * y: 0 push, 1 pop
     * xx: regnumber
     */
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;
	bool pop = ((*state->pc) & 0x40) ? true : false;

	if (pop)
	{
		if (state->stackptr == 0)
		{
			fprintf(stderr, "Stack underflow\n");
			exit(0);
		}

		--state->stackptr;
		state->regs[regnum] = vmstack[state->stackptr];
	}
	else
	{
		if (state->stackptr >= VMSTACK)
		{
			fprintf(stderr, "Stack overflow\n");
			exit(0);
		}

		vmstack[state->stackptr] = state->regs[regnum];
		++state->stackptr;
	}
}

static void add(cpustate *state)
{
    /* add: opcode 0100
     * layout: yyxx0100
     * yy: regnumber (00 for memory parameter)
     * xx: regnumber (00 for memory parameter)
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (regnum1 == 0)
	{
		memaddr a = readmem(state);
		val1 = vmmem[a];
	}
	else
	{
		val1 = state->regs[regnum1];
	}

	if (regnum2 == 0)
	{
		memaddr a = readmem(state);
		val2 = vmmem[a];
	}
	else
	{
		val2 = state->regs[regnum2];
	}

	state->regs[0] = val1 + val2;
}

static void sub(cpustate *state)
{
    /* sub: opcode 0101
     * layout: yyxx0100
     * yy: regnumber (00 for memory parameter)
     * xx: regnumber (00 for memory parameter)
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (regnum1 == 0)
	{
		memaddr a = readmem(state);
		val1 = vmmem[a];
	}
	else
	{
		val1 = state->regs[regnum1];
	}

	if (regnum2 == 0)
	{
		memaddr a = readmem(state);
		val2 = vmmem[a];
	}
	else
	{
		val2 = state->regs[regnum2];
	}

	state->regs[0] = val1 - val2;
}

static void mul(cpustate *state)
{
    /* mul: opcode 0110
     * layout: yyxx0100
     * yy: regnumber (00 for memory parameter)
     * xx: regnumber (00 for memory parameter)
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (regnum1 == 0)
	{
		memaddr a = readmem(state);
		val1 = vmmem[a];
	}
	else
	{
		val1 = state->regs[regnum1];
	}

	if (regnum2 == 0)
	{
		memaddr a = readmem(state);
		val2 = vmmem[a];
	}
	else
	{
		val2 = state->regs[regnum2];
	}

	state->regs[0] = val1 * val2;
}

static void divide(cpustate *state)
{
    /* div: opcode 0111
     * layout: yyxx0100
     * yy: regnumber (00 for memory parameter)
     * xx: regnumber (00 for memory parameter)
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (regnum1 == 0)
	{
		memaddr a = readmem(state);
		val1 = vmmem[a];
	}
	else
	{
		val1 = state->regs[regnum1];
	}

	if (regnum2 == 0)
	{
		memaddr a = readmem(state);
		val2 = vmmem[a];
	}
	else
	{
		val2 = state->regs[regnum2];
	}

	state->regs[0] = val1 / val2;
}

static void remider(cpustate *state)
{
    /* remider: opcode 1000
     * layout: yyxx1000
     * yy: regnumber (00 for memory parameter)
     * xx: regnumber (00 for memory parameter)
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (regnum1 == 0)
	{
		memaddr a = readmem(state);
		val1 = vmmem[a];
	}
	else
	{
		val1 = state->regs[regnum1];
	}

	if (regnum2 == 0)
	{
		memaddr a = readmem(state);
		val2 = vmmem[a];
	}
	else
	{
		val2 = state->regs[regnum2];
	}

	state->regs[0] = val1 % val2;
}

static void test(cpustate *state)
{
    /* test: opcode 1001
     * layout: yyxx1000
     */
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	if (state->regs[regnum1] == state->regs[regnum2])
	{
		state->equals = true;
		state->lesser = false;
		state->greater = false;
	}
	else if (state->regs[regnum1] < state->regs[regnum2])
	{
		state->equals = false;
		state->lesser = true;
		state->greater = false;
	}
	else
	{
		state->equals = false;
		state->lesser = false;
		state->greater = true;
	}
}

static void jump(cpustate *state)
{
    /* test: opcode 1010
     * layout: wzyx1000
     * x: equal
     * y: lesser
     * z: greater
     * w: conditional enable
     */

    uint8_t param = (*state->pc);
    memaddr to = readmem(state);

	if (param & 0x80)
	{
		if (!(((param & 0x40) && state->greater)
			 || ((param & 0x20) && state->lesser)
			 || ((param & 0x20) && state->lesser)))
		{
			return;
		}
	}
	state->pc = codestart + to;
	if (state->pc < codestart || state->pc >= codeend)
	{
		fprintf(stderr, "Invalid jump\n");
		exit (0);
	}
}

static void runcode(const char *code, size_t codelen)
{
	static const op opcodes[] =
	{
		load,
		store,
		call,
		push_pop,
		add,
		sub,
		mul,
		divide,
		remider,
		test,
		jump
	};
	cpustate state = {0};

	codestart = code;
	codeend = code + codelen;

	for (state.pc = code;
		 state.pc >= codestart && state.pc < codeend;
		 ++state.pc)
	{
		uint8_t op = (*state.pc) & 0xF;
		if (op > sizeof(opcodes) / sizeof(opcodes[0]))
		{
				fprintf(stderr, "Unknown OPCODE\n");
				exit(0);
		}
		opcodes[op](&state);
	}

	if (state.pc < codestart || state.pc >= codeend)
	{
		fprintf(stderr, "Invalid code\n");
		exit(0);
	}
}

static void readsyms(const char **_data, size_t *_len)
{
	const char *data = *_data;
	size_t len = *_len;
	size_t i = 0;
	for (const char *next = memchr(data, '\0', len); next && i < MAXSYMS;
		next = memchr(data, '\0', len), ++i)
	{
		if (!*data)
			break;

		syms[i] = dlsym(RTLD_NEXT, data);
		if (!syms[i])
		{
			fprintf(stderr, "Sym not found\n");
			exit(0);
		}
		next++;
		syms_type[i] = *next;
		if (syms_type[i] >= SYMS_TYPE_MAX)
		{
			fprintf(stderr, "Unknown sym sign\n");
			exit(0);
		}

		len -= next + 1 - data;
		data = next + 1;
		if (!*data)
			break;
	}
	if (*data || i >= MAXSYMS)
	{
		fprintf(stderr, "Invalid symtab\n");
		exit(0);
	}
	++data;
	*_len -= 1;
	*_data = data;
}

static void readvars(const char **_data, size_t *_len)
{
	const char *data = *_data;
	size_t len = *_len;
	memaddr count = 0;

	for (size_t i = 0; i < sizeof(memaddr) && len; ++i, ++data, --len)
	{
		count <<= 8;
		count += *(uint8_t *)data;
	}
	for (memaddr v = 0; v < count; ++v)
	{
		uint64_t val = 0;
		for (size_t i = 0; i < sizeof(val) && len; ++i, ++data, --len)
		{
			val <<= 8;
			val += *(uint8_t *)data;
		}
		vmmem[v] = val;
	}
	if (!len)
	{
		fprintf(stderr, "invalid vartab\n");
		exit(0);
	}

	*_data = data;
	*_len = len;
}

static void vmrun(const char *data, size_t len)
{
	readsyms(&data, &len);
	readvars(&data, &len);
	runcode(data, len);
}

int main() {
	size_t len = 1024;
	size_t off = 0;
	char *buffer = malloc(len);
	ssize_t rlen;

	for (rlen = read(0, buffer + off, len - off);
		 rlen > 0;
		 rlen = read(0, buffer + off, len - off))
	{
		off += rlen;
		if (off == len)
		{
			len <<= 1;
			buffer = realloc(buffer, len);
		}
	}
	vmrun(buffer, off);
}
