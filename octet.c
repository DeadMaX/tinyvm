#define _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct {
	uint64_t regs[4]; //  CPU register
	size_t stackptr; //  Stack pointer
	const char *pc; // Program counter
	// CPU internal state
	bool equals:1;
	bool lesser:1;
	bool greater:1;
} cpustate;
// memory areas
static void *syms[256];
static uint8_t syms_type[256];
static uint64_t vmmem[256];
static uint64_t vmstack[1024];
static const char *strings[256];
const char *codestart;

static uint64_t readval(const void **_ptr) {
	uint64_t res = 0;
	const uint8_t *ptr = *_ptr;
	for(size_t i = 0; i < sizeof(uint64_t); ++i) {
		++ptr;
		res <<= 8;
		res += *ptr;
	}
	*_ptr = ptr;
	return res;
}

static void _llll(cpustate *state) {
	uint8_t _1111 = ((*state->pc) & 0x30) >> 4;
	uint8_t _111l = ((*state->pc) & 0xc0) >> 6;
	switch (_111l) {
		case 0: ++state->pc; state->regs[_1111] = (uintptr_t)&vmmem[*(uint8_t *)(state->pc)]; break;
		case 1: ++state->pc; state->regs[_1111] = vmmem[*(uint8_t *)(state->pc)]; break;
		case 2: ++state->pc; state->regs[_1111] = (uintptr_t)(strings[*(uint8_t *)(state->pc)]); break;
		case 3: state->regs[_1111] = readval((const void**)&state->pc); break;
	}
}

static void _lll1(cpustate *state) {
	++state->pc;
	vmmem[*(uint8_t *)(state->pc)] = state->regs[((*state->pc) & 0x30) >> 4];
}

static void _ll1l(cpustate *state) {
	++state->pc;
	uint8_t _1111 = *(uint8_t *)(state->pc);
	switch(syms_type[_1111]) {
		case 0: ((void (*)(int))syms[_1111])(state->regs[0]); break;
		case 1: state->regs[0] = ((int (*)(void *))syms[_1111])((void *)state->regs[0]); break;
		case 2: state->regs[0] = ((int (*)(void))syms[_1111])(); break;
		case 3: state->regs[0] = (uintptr_t)((void *(*)(void *))syms[_1111])((void *)state->regs[0]); break;
		case 4: state->regs[0] = ((int (*)(int, void *, int))syms[_1111])((int)state->regs[0], (void *)state->regs[1], (int)state->regs[2]); break;
		case 5: state->regs[0] = ((int (*)(int, int))syms[_1111])((int)state->regs[0], (int)state->regs[1]); break;
		case 6: state->regs[0] = ((int (*)(int))syms[_1111])((int)state->regs[0]); break;
		case 7: state->regs[0] = ((int (*)(void *, void *, void *, void *, void *))syms[_1111])((void *)state->regs[0], (void *)state->regs[1], (void *)state->regs[2], (void *)state->regs[3], (void *)vmstack[state->stackptr - 1]); break;
		case 8: state->regs[0] = (uintptr_t)((void *(*)(void *, void *))syms[_1111])((void *)state->regs[0], (void *)state->regs[1]); break;
		case 9: state->regs[0] = ((int (*)(int, void *))syms[_1111])((int)state->regs[0], (void *)state->regs[1]); break;
		case 10: state->regs[0] = ((int (*)(int, int, void *))syms[_1111])((int)state->regs[0], (int)state->regs[1], (void *)state->regs[2]); break;
		case 11: state->regs[0] = (uintptr_t)((void *(*)(int, void *))syms[_1111])((int)state->regs[0], (void *)state->regs[1]); break;
		case 12: state->regs[0] = ((u_long (*)(int, void *, u_long))syms[_1111])((int)state->regs[0], (void *)state->regs[1], (u_long)state->regs[2]); break;
		case 13: state->regs[0] = ((u_long (*)(void *))syms[_1111])((void *)state->regs[0]); break;
		case 14: state->regs[0] = ((u_long (*)(void *, u_long, void *, void *))syms[_1111])((void *)state->regs[0], (u_long)state->regs[1], (void *)state->regs[2], (void *)state->regs[3]); break;
	}
}

static void _ll11(cpustate *state) {
	uint8_t _1111 = ((*state->pc) & 0x30) >> 4;

	if ((*state->pc) & 0x40) {
		--state->stackptr; state->regs[_1111] = vmstack[state->stackptr];
	} else {
		vmstack[state->stackptr] = state->regs[_1111]; ++state->stackptr;
	}
}

#define HARY(A, B) \
static void A(cpustate *state) { state->regs[0] = state->regs[((*state->pc) & 0x30) >> 4] B state->regs[((*state->pc) & 0xc0) >> 6]; }

HARY(_l1ll, +)
HARY(_l1l1, -)
HARY(_l11l, *)
HARY(_l111, /)
HARY(_1lll, %)

static void _1ll1(cpustate *state)
{
	uint8_t _11111 = ((*state->pc) & 0x30) >> 4;
	uint8_t _11112 = ((*state->pc) & 0xc0) >> 6;

	if (state->regs[_11111] == state->regs[_11112]) {
		state->equals = true;
		state->lesser = false;
		state->greater = false;
	} else if (state->regs[_11111] < state->regs[_11112]) {
		state->equals = false;
		state->lesser = true;
		state->greater = false;
	} else {
		state->equals = false;
		state->lesser = false;
		state->greater = true;
	}
}

static void _1l1l(cpustate *state)
{
	uint8_t _1111 = (*state->pc);
	uint64_t to = readval((const void **)&state->pc);

	if ((_1111 & 0x80)
	    && (!(((_1111 & 0x40) && state->greater)
		 || ((_1111 & 0x20) && state->lesser)
		 || ((_1111 & 0x10) && state->equals))))
			return;
	state->pc = codestart + to - 1;
}

static void _1l11(cpustate *state)
{
	uint8_t _1111 = ((*state->pc) & 0x30) >> 4;
	if (((*state->pc) & 0x80))
		state->regs[_1111]--;
	else
		state->regs[_1111]++;
}

static void runcode(const char *code)
{
	cpustate state = {0};
	codestart = code;

	for (state.pc = code;; ++state.pc) {
		switch ((*state.pc) & 0xF) {
			case 0: _llll(&state); break;
			case 1: _lll1(&state); break;
			case 2: _ll1l(&state); break;
			case 3: _ll11(&state); break;
			case 4: _l1ll(&state); break;
			case 5: _l1l1(&state); break;
			case 6: _l11l(&state); break;
			case 7: _l111(&state); break;
			case 8: _1lll(&state); break;
			case 9: _1ll1(&state); break;
			case 10: _1l1l(&state); break;
			case 11: _1l11(&state); break;
		}
	}
}

static void readsyms(char **_data) {
	char *data = *_data;
	size_t i = 0;
	for (char *next = strchr(data, '\0'); next; next = strchr(data, '\0'), ++i) {
		if (!*data) break;
		for (size_t i = 0; data[i] != '\0'; ++i) data[i] += '`';
		syms[i] = dlsym(RTLD_NEXT, data);
		next++;
		syms_type[i] = *next;
		data = next + 1;
		if (!*data) break;
	}
	++data;
	*_data = data;
}

static void readstrings(char **_data) {
	char *data = *_data;
	size_t i = 0;
	for (char *next = strchr(data, '\0'); next; next = strchr(data, '\0'), ++i) {
		if (!*data) break;
		for (size_t i = 0; data[i] != '\0'; ++i) data[i] += '`';
		strings[i] = data;
		data = next + 1;
		if (!*data) break;
	}
	++data;
	*_data = data;
}

static void readvars(char **_data) {
	char *data = *_data;
	uint8_t count = *(uint8_t *)data;
	++data;
	for (uint8_t v = 0; v < count; ++v) vmmem[v] = readval((const void **)&data);
	*_data = data;
}

static void vmrun(char *data) {
	readsyms(&data);
	readstrings(&data);
	readvars(&data);
	runcode(data);
}

int main(int argc, const char *argv[])
{
	size_t len = 1024;
	size_t off = 0;
	char *buffer = malloc(len);
	ssize_t rlen;
	int fd = 0;

	if (argc < 2) exit(1);
	fd = open(argv[1], O_RDONLY);
	for (rlen = read(fd, buffer + off, len - off); rlen > 0; rlen = read(fd, buffer + off, len - off)) {
		off += rlen;
		if (off == len) {
			len <<= 1;
			buffer = realloc(buffer, len);
		}
	}
	vmrun(buffer);
}
