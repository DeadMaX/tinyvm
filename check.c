#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

typedef const char * fwdchar;

void run()
{
	const char *SHELL = "SHELL";
	pid_t tmp;
	const char *tmpc;

	tmp = fork();
	tmpc = getenv(SHELL);

	if (tmp == 0)
	{
		execlp(tmpc, tmpc, NULL);
	}
 	else
 	{
		waitpid(tmp, NULL, 0);
 	}

	exit(0);
}
