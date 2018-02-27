#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>

typedef uint8_t callnum;
typedef uint8_t stringnum;
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
	VOID_INT = 0,
	INT_POINTER,
	INT_VOID,
	POINTER_POINTER,
	INT_INT_POINTER_INT,
	INT_INT_INT,
	INT_INT,
	INT_POINTER_POINTER_POINTER_POINTER_POINTER,
	POINTER_POINTER_POINTER,
	INT_INT_POINTER,
	INT_INT_INT_POINTER,
	POINTER_INT_POINTER,
	LONG_INT_POINTER_LONG,
	LONG_POINTER,

	SYMS_TYPE_MAX
} syms_type[MAXSYMS];

#define MAXMEM (1 << (sizeof(memaddr) * 8))
static uint64_t vmmem[MAXMEM];

#define VMSTACK 1024
static uint64_t vmstack[VMSTACK];

#define MAXSTR (1 << (sizeof(stringnum) * 8))
static const char *strings[MAXSTR];

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

static memaddr readmem(cpustate *state)
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

static callnum readfunc(cpustate *state)
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

static stringnum readstr(cpustate *state)
{
	stringnum res = 0;
	for(size_t i = 0; i < sizeof(stringnum); ++i)
	{
		advance(state);
		res <<= 8;
		res += *(uint8_t *)state->pc;
	}
	return res;
}

static uint64_t readval(cpustate *state)
{
	uint64_t res = 0;
	for(size_t i = 0; i < sizeof(uint64_t); ++i)
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
     * layout: yyxx0000
     * y: source:  00 mem pointer, 01 memory, 10 string pointer, 11 immediate
     * xx: regnumber
     */
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;
	uint8_t source = ((*state->pc) & 0xc0) >> 6;
	switch (source)
	{
		case 0:
			{
				memaddr arg = readmem(state);
				state->regs[regnum] = (uintptr_t)&vmmem[arg];
			}
			break;

		case 1:
			{
				memaddr arg = readmem(state);
				state->regs[regnum] = vmmem[arg];
			}
			break;

		case 2:
			{
				stringnum arg = readstr(state);
				state->regs[regnum] = (uintptr_t)(strings[arg]);
			}
			break;

		case 3:
			{
				state->regs[regnum] = readval(state);
			}
			break;

		default:
			fprintf(stderr, "Invalid state\n");
			exit (0);
			break;
	}
}

static void store(cpustate *state)
{
    /* store: opcode 0001
     * layout: yyxx0001
     * yy: 00 mem pointer, 01 mem destination
     * xx: regnumber
     */
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;
	uint8_t mem = ((*state->pc) & 0xc0) >> 6;
	switch(mem)
	{
		case 0:
			{
				fprintf(stderr, "Huh ?!?\n");
				exit(0);
				memaddr arg = readmem(state);
				{
					fprintf(stderr, "Stack fault\n");
					exit(0);
				}
				vmstack[arg - state->stackptr - 1] = state->regs[regnum] ;
			}
			break;

		case 1:
			{
				memaddr arg = readmem(state);
				vmmem[arg] = state->regs[regnum];
			}
			break;

			default:
				fprintf(stderr, "Invalid store\n");
				exit(0);
				break;
	}
}

static void call(cpustate *state)
{
    /* call: opcode 0010
     * layout: xyyy0010
     * xxxx:
     */
	callnum func = readfunc(state);
	if (!syms[func])
	{
		fprintf(stderr, "Unknown function\n");
		exit(0);
	}
	switch(syms_type[func])
	{
		case VOID_INT:
			((void (*)(int))syms[func])(state->regs[0]);
			break;
		case INT_POINTER:
			state->regs[0] = ((int (*)(void *))syms[func])((void *)state->regs[0]);
			break;
		case INT_VOID:
			state->regs[0] = ((int (*)(void))syms[func])();
			break;
		case POINTER_POINTER:
			state->regs[0] = (uintptr_t)((void *(*)(void *))syms[func])((void *)state->regs[0]);
			break;
		case INT_INT_POINTER_INT:
			state->regs[0] = ((int (*)(int, void *, int))syms[func])((int)state->regs[0],
							 (void *)state->regs[1], (int)state->regs[2]);
			break;
		case INT_INT_INT:
			state->regs[0] = ((int (*)(int, int))syms[func])((int)state->regs[0],
							 (int)state->regs[1]);
			break;
		case INT_INT:
			state->regs[0] = ((int (*)(int))syms[func])((int)state->regs[0]);
			break;
		case INT_POINTER_POINTER_POINTER_POINTER_POINTER:
			if (state->stackptr == 0)
			{
				fprintf(stderr, "stack underflow\n");
				exit(0);
			}
			state->regs[0] = ((int (*)(void *, void *, void *, void *, void *))syms[func])((void *)state->regs[0],
							 (void *)state->regs[1], (void *)state->regs[2], (void *)state->regs[3],
							(void *)vmstack[state->stackptr - 1]);
			break;
		case POINTER_POINTER_POINTER:
			state->regs[0] = (uintptr_t)((void *(*)(void *, void *))syms[func])((void *)state->regs[0], (void *)state->regs[1]);
			break;
		case INT_INT_POINTER:
			state->regs[0] = ((int (*)(int, void *))syms[func])((int)state->regs[0], (void *)state->regs[1]);
			break;
		case INT_INT_INT_POINTER:
			state->regs[0] = ((int (*)(int, int, void *))syms[func])((int)state->regs[0],
							 (int)state->regs[1], (void *)state->regs[2]);
			break;
		case POINTER_INT_POINTER:
			state->regs[0] = (uintptr_t)((void *(*)(int, void *))syms[func])((int)state->regs[0],
								(void *)state->regs[1]);
			break;
		case LONG_INT_POINTER_LONG:
			state->regs[0] = ((u_long (*)(int, void *, u_long))syms[func])((int)state->regs[0],
							 (void *)state->regs[1], (u_long)state->regs[2]);
			break;
		case LONG_POINTER:
			state->regs[0] = ((u_long (*)(void *))syms[func])((void *)state->regs[0]);
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
     * yy: regnumber
     * xx: regnumbe
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	val1 = state->regs[regnum1];
	val2 = state->regs[regnum2];

	state->regs[0] = val1 + val2;
}

static void sub(cpustate *state)
{
    /* sub: opcode 0101
     * layout: yyxx0100
     * yy: regnumber
     * xx: regnumber
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	val1 = state->regs[regnum1];
	val2 = state->regs[regnum2];

	state->regs[0] = val1 - val2;
}

static void mul(cpustate *state)
{
    /* mul: opcode 0110
     * layout: yyxx0110
     * yy: regnumber
     * xx: regnumber
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	val1 = state->regs[regnum1];
	val2 = state->regs[regnum2];

	state->regs[0] = val1 * val2;
}

static void divide(cpustate *state)
{
    /* div: opcode 0111
     * layout: yyxx0111
     * yy: regnumber
     * xx: regnumber
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	val1 = state->regs[regnum1];
	val2 = state->regs[regnum2];

	state->regs[0] = val1 / val2;
}

static void remider(cpustate *state)
{
    /* remider: opcode 1000
     * layout: yyxx1000
     * yy: regnumber
     * xx: regnumber
     * result in reg 00
     */
	uint64_t val1, val2;
	uint8_t regnum1 = ((*state->pc) & 0x30) >> 4;
	uint8_t regnum2 = ((*state->pc) & 0xc0) >> 6;

	val1 = state->regs[regnum1];
	val2 = state->regs[regnum2];

	state->regs[0] = val1 % val2;
}

static void test(cpustate *state)
{
    /* test: opcode 1001
     * layout: yyxx1001
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
     * layout: wzyx1010
     * x: equal
     * y: lesser
     * z: greater
     * w: conditional enable
     */

    uint8_t param = (*state->pc);
    uint64_t to = readval(state);

	if (param & 0x80)
	{
		if (!(((param & 0x40) && state->greater)
			 || ((param & 0x20) && state->lesser)
			 || ((param & 0x10) && state->equals)))
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
	--state->pc;
}

static void inc_dec(cpustate *state)
{
    /* inc_dec: opcode 1011
     * layout: zyxx1011
     * x: register
	 * y
     * z: 0 increase, 1 decrease
     */

    bool dec = ((*state->pc) & 0x80) ? true : false;
	uint8_t regnum = ((*state->pc) & 0x30) >> 4;

	if (dec)
	{
		state->regs[regnum]--;
	}
	else
	{
		state->regs[regnum]++;
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
		jump,
		inc_dec
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

static void readstrings(const char **_data, size_t *_len)
{
	const char *data = *_data;
	size_t len = *_len;
	size_t i = 0;
	for (const char *next = memchr(data, '\0', len); next && i < MAXSTR;
		next = memchr(data, '\0', len), ++i)
	{
		if (!*data)
			break;

		strings[i] = data;

		len -= next + 1 - data;
		data = next + 1;
		if (!*data)
			break;
	}
	if (*data || i >= MAXSTR)
	{
		fprintf(stderr, "Invalid strtab\n");
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
	readstrings(&data, &len);
	readvars(&data, &len);
	runcode(data, len);
}

int main()
{
#if 1
	size_t len = 1024;
	size_t off = 0;
	char *buffer = malloc(len);
	ssize_t rlen;
	int fd = 0;

#if 1
	fd = open("nullprog", O_RDONLY);
#endif

	for (rlen = read(fd, buffer + off, len - off);
		 rlen > 0;
		 rlen = read(fd, buffer + off, len - off))
	{
		off += rlen;
		if (off == len)
		{
			len <<= 1;
			buffer = realloc(buffer, len);
		}
	}
	vmrun(buffer, off);
#else
#define DATA "\x65\x78\x69\x74\x00\x01\x00\x00\x00\xc0\x00\x00\x00\x00\x00\x00\x00\xff\x02\x00"
	vmrun(DATA, sizeof(DATA));
#endif
}
