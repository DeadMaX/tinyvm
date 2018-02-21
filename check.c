#include <stdlib.h>
#include <stdio.h>

int fork();
void execlp(const char *, int, int);

void run()
{
	const char *SHELL = "SHELL";
	int tmp;

	tmp = fork();

	if (tmp == 0)
	{
		execlp(getenv(SHELL), 0, 0);
	}

	exit(0);
}
