#include <stdlib.h>
#include <stdio.h>

void run()
{
	int a = 6;
	char *msg = "C'est la chenille qui redémarre :)";

	a *= 7;
	puts(msg);
	puts(msg);
	puts(msg);
	exit(a);
}
