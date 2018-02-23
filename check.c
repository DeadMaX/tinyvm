#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

typedef const char * fwdchar;

void run()
{
	const char *SHELL = "SHELL";
	const char *DASH_I = "-is";
	const char *EXIT = "exit\n";
	pid_t tmp;
	const char *tmpc;
	int pip[2];

	pipe(pip);

	tmp = fork();
	if (tmp == 0)
	{
		dup2(pip[0], 0);
		close(pip[0]);
		close(pip[1]);
		tmpc = getenv(SHELL);
		execlp(tmpc, tmpc, DASH_I, NULL);
	}
 	else
 	{
		close(pip[0]);
		sleep(5);
		write(pip[1], EXIT, 5);
		waitpid(tmp, NULL, 0);
 	}

	exit(0);
}
