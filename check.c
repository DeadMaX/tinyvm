#include <stdlib.h>
#include <stdio.h>

void run()
{
	int a = 2;
	char *msg = "C'est la chenille qui redémarre :)";

	a *= a;
	a += 1 + 1;
	a = a * 7;
	puts(msg);
	puts(msg);
	puts(msg);
	exit(a);
}
