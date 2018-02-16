#include <stdlib.h>
#include <stdio.h>

void run()
{
	int a = 3;
	char *msg = "C'est la chenille qui redémarre :)";

	a *= 2;
	a = a * 7;
	puts(msg);
	puts(msg);
	puts(msg);
	exit(a);
}
